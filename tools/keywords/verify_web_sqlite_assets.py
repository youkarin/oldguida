import argparse
import hashlib
import json
import mimetypes
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


class VerificationError(Exception):
    pass


@dataclass(frozen=True)
class AssetSpec:
    content_types: tuple[str, ...]
    exact_size: int
    sha256: str
    magic: bytes = b""


ASSET_SPECS = {
    "/sqflite_sw.js": AssetSpec(
        ("text/javascript", "application/javascript"),
        263_999,
        "e53506d863d17357ebf15488be0069c3e8d234afdfeaa5bd896817d8312826a3",
    ),
    "/sqlite3.wasm": AssetSpec(
        ("application/wasm",),
        733_428,
        "8766db025f5d5b6f24c6a51cc9dec843ab7a7720e3dfa5b47d70d33db96d506b",
        b"\x00asm",
    ),
}

# sqflite_common_ffi_web 1.1.1's setup downloads the sqlite3 3.1.2 WASM
# release. That binary provenance is separate from the resolved Dart sqlite3
# package version below; exact asset hashes protect the downloaded binaries.
EXPECTED_LOCK_PACKAGES = {
    "sqflite_common_ffi_web": {
        "source": "hosted",
        "name": "sqflite_common_ffi_web",
        "url": "https://pub.dev",
        "version": "1.1.1",
        "sha256": "79338d0b69521d70cea10f841209ac87ce617921aaf7d33e7380682c83da1f06",
    },
    "sqlite3": {
        "source": "hosted",
        "name": "sqlite3",
        "url": "https://pub.dev",
        "version": "3.5.2",
        "sha256": "4c7fe79840389aaeaf05fd093f795b631b5a98e2bd28d54e555c100f4a9c7a1c",
    },
}


def verify_asset_response(path, status, content_type, body):
    spec = ASSET_SPECS[path]
    if status != 200:
        raise VerificationError(f"{path}: expected HTTP 200, got {status}")
    normalized_content_type = (content_type or "").split(";", 1)[0].strip().casefold()
    normalized_prefix = body[:64].lstrip().lower()
    if normalized_content_type == "text/html" or normalized_prefix.startswith(
        (b"<!doctype html", b"<html")
    ):
        raise VerificationError(
            f"{path}: asset is missing and the server returned the SPA fallback"
        )
    if normalized_content_type not in spec.content_types:
        raise VerificationError(
            f"{path}: expected content type in {spec.content_types}, "
            f"got {content_type!r}"
        )
    if len(body) != spec.exact_size:
        raise VerificationError(
            f"{path}: expected length {spec.exact_size}, got {len(body)}"
        )
    if spec.magic and not body.startswith(spec.magic):
        raise VerificationError(f"{path}: invalid file signature")
    actual_sha256 = hashlib.sha256(body).hexdigest()
    if actual_sha256 != spec.sha256:
        raise VerificationError(
            f"{path}: expected SHA-256 {spec.sha256}, got {actual_sha256}"
        )


def verify_http(base_url):
    for path in ASSET_SPECS:
        url = f"{base_url.rstrip('/')}{path}"
        spec = ASSET_SPECS[path]
        try:
            with urlopen(url, timeout=10) as response:
                verify_asset_response(
                    path,
                    response.status,
                    response.headers.get("Content-Type"),
                    response.read(spec.exact_size + 1),
                )
        except VerificationError:
            raise
        except HTTPError as error:
            detail = _single_line(error.reason)
            raise VerificationError(
                f"{path}: failed to fetch {url}: HTTP {error.code} {detail}"
            ) from error
        except URLError as error:
            raise VerificationError(
                f"{path}: failed to fetch {url}: {_single_line(error.reason)}"
            ) from error
        except (OSError, ValueError) as error:
            raise VerificationError(
                f"{path}: failed to fetch {url}: {_single_line(error)}"
            ) from error


def _single_line(value):
    return " ".join(str(value).split())


def verify_directory(directory):
    root = Path(directory)
    for path in ASSET_SPECS:
        asset = root / path.removeprefix("/")
        try:
            body = asset.read_bytes()
        except FileNotFoundError as error:
            raise VerificationError(f"{path}: asset is missing from {root}") from error
        content_type, _ = mimetypes.guess_type(asset.name)
        verify_asset_response(path, 200, content_type, body)


def verify_lock_file(lock_file):
    lock_path = Path(lock_file)
    try:
        contents = lock_path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerificationError(f"dependency lock is missing: {lock_path}") from error

    packages = _parse_lock_packages(contents)
    for package, expected_fields in EXPECTED_LOCK_PACKAGES.items():
        actual_fields = packages.get(package)
        if actual_fields is None:
            raise VerificationError(f"{package}: package is missing from {lock_path}")
        for field, expected in expected_fields.items():
            actual = actual_fields.get(field)
            if actual is None:
                raise VerificationError(
                    f"{package}: lock field {field} is missing from {lock_path}"
                )
            if actual != expected:
                raise VerificationError(
                    f"{package}: lock field {field} expected {expected!r}, "
                    f"got {actual!r} in {lock_path}"
                )


def _parse_lock_packages(contents):
    packages = {}
    in_packages = False
    packages_section_seen = False
    current_package = None
    current_fields = None
    in_description = False

    for line_number, line in enumerate(contents.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            if stripped == "packages:":
                if packages_section_seen:
                    raise VerificationError("dependency lock has duplicate packages block")
                packages_section_seen = True
                in_packages = True
            else:
                in_packages = False
            current_package = None
            current_fields = None
            in_description = False
        elif in_packages and indent == 2 and stripped.endswith(":"):
            package = stripped[:-1]
            in_description = False
            if package not in EXPECTED_LOCK_PACKAGES:
                current_package = None
                current_fields = None
                continue
            if package in packages:
                raise VerificationError(f"duplicate target package {package}")
            current_package = package
            current_fields = {}
            packages[package] = current_fields
        elif in_packages and current_package is not None:
            if indent == 4:
                key, raw_value = _parse_lock_mapping(line_number, stripped)
                if key not in {"dependency", "description", "source", "version"}:
                    raise VerificationError(
                        f"{current_package}: unknown lock field {key!r} on line {line_number}"
                    )
                if key in current_fields:
                    raise VerificationError(
                        f"{current_package}: duplicate lock field {key}"
                    )
                if key == "description":
                    if raw_value:
                        raise VerificationError(
                            f"{current_package}: invalid description block"
                        )
                    current_fields["description"] = {}
                    in_description = True
                else:
                    current_fields[key] = _parse_lock_scalar(
                        current_package,
                        key,
                        raw_value,
                    )
                    in_description = False
            elif indent == 6 and in_description:
                key, raw_value = _parse_lock_mapping(line_number, stripped)
                if key not in {"name", "sha256", "url"}:
                    raise VerificationError(
                        f"{current_package}: unknown description field {key!r} "
                        f"on line {line_number}"
                    )
                description = current_fields["description"]
                if key in description:
                    raise VerificationError(
                        f"{current_package}: duplicate description field {key}"
                    )
                description[key] = _parse_lock_scalar(
                    current_package,
                    key,
                    raw_value,
                )
            else:
                raise VerificationError(
                    f"{current_package}: invalid lock structure on line {line_number}"
                )

    flattened = {}
    for package, fields in packages.items():
        description = fields.pop("description", {})
        flattened[package] = {**fields, **description}
    return flattened


def _parse_lock_mapping(line_number, stripped):
    key, separator, raw_value = stripped.partition(":")
    if not separator or not key:
        raise VerificationError(f"invalid dependency lock mapping on line {line_number}")
    return key, raw_value.strip()


def _parse_lock_scalar(package, field, raw_value):
    if not raw_value:
        raise VerificationError(f"{package}: lock field {field} is missing")
    if raw_value.startswith('"'):
        try:
            value = json.loads(raw_value)
        except (json.JSONDecodeError, TypeError) as error:
            raise VerificationError(
                f"{package}: invalid quoted value for {field}"
            ) from error
        if not isinstance(value, str):
            raise VerificationError(f"{package}: lock field {field} must be text")
        return value
    if any(character.isspace() for character in raw_value):
        raise VerificationError(f"{package}: invalid unquoted value for {field}")
    return raw_value


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Verify deployed Web SQLite runtime assets and dependency lock."
    )
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--directory", type=Path)
    target.add_argument("--url")
    parser.add_argument(
        "--lock-file",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "pubspec.lock",
    )
    args = parser.parse_args(argv)

    try:
        verify_lock_file(args.lock_file)
        if args.directory is not None:
            verify_directory(args.directory)
            verified_target = str(args.directory)
        else:
            verify_http(args.url)
            verified_target = args.url
    except VerificationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Web SQLite deployment assets verified: {verified_target}")
    for path, spec in ASSET_SPECS.items():
        print(f"  {path}: {spec.exact_size} bytes, sha256={spec.sha256}")
    for package, fields in EXPECTED_LOCK_PACKAGES.items():
        print(f"  {package}: {fields['version']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
