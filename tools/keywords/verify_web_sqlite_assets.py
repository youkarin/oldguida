import argparse
import hashlib
import mimetypes
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.request import urlopen


class VerificationError(Exception):
    pass


@dataclass(frozen=True)
class AssetSpec:
    content_type_token: str
    exact_size: int
    sha256: str
    magic: bytes = b""


ASSET_SPECS = {
    "/sqflite_sw.js": AssetSpec(
        "javascript",
        263_999,
        "e53506d863d17357ebf15488be0069c3e8d234afdfeaa5bd896817d8312826a3",
    ),
    "/sqlite3.wasm": AssetSpec(
        "wasm",
        733_428,
        "8766db025f5d5b6f24c6a51cc9dec843ab7a7720e3dfa5b47d70d33db96d506b",
        b"\x00asm",
    ),
}

# sqflite_common_ffi_web 1.1.1's setup downloads the sqlite3 3.1.2 WASM
# release. That binary provenance is separate from the resolved Dart sqlite3
# package version below; exact asset hashes protect the downloaded binaries.
EXPECTED_LOCK_VERSIONS = {
    "sqflite_common_ffi_web": "1.1.1",
    "sqlite3": "3.5.2",
}


def verify_asset_response(path, status, content_type, body):
    spec = ASSET_SPECS[path]
    if status != 200:
        raise VerificationError(f"{path}: expected HTTP 200, got {status}")
    normalized_content_type = (content_type or "").lower()
    normalized_prefix = body[:64].lstrip().lower()
    if "text/html" in normalized_content_type or normalized_prefix.startswith(
        (b"<!doctype html", b"<html")
    ):
        raise VerificationError(
            f"{path}: asset is missing and the server returned the SPA fallback"
        )
    if content_type is None or spec.content_type_token not in content_type:
        raise VerificationError(
            f"{path}: expected {spec.content_type_token} content type, "
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
        with urlopen(url, timeout=10) as response:
            verify_asset_response(
                path,
                response.status,
                response.headers.get("Content-Type"),
                response.read(),
            )


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

    versions = _parse_lock_versions(contents)
    for package, expected in EXPECTED_LOCK_VERSIONS.items():
        actual = versions.get(package)
        if actual != expected:
            raise VerificationError(
                f"{package}: expected {expected} in {lock_path}, got {actual}"
            )


def _parse_lock_versions(contents):
    versions = {}
    in_packages = False
    current_package = None
    for line in contents.splitlines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            in_packages = stripped == "packages:"
            current_package = None
        elif in_packages and indent == 2 and stripped.endswith(":"):
            current_package = stripped[:-1]
        elif (
            in_packages
            and current_package is not None
            and indent == 4
            and stripped.startswith("version:")
        ):
            versions[current_package] = stripped.partition(":")[2].strip().strip('"')
    return versions


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
    for package, version in EXPECTED_LOCK_VERSIONS.items():
        print(f"  {package}: {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
