"""Verify OldGuida display metadata and protected application identifiers."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree


DISPLAY_NAME = "OldGuida"
WEB_DESCRIPTION = "意大利驾考学习工具"
RUNNER_BLUEPRINT_ID = "33CC10EC2044A3C60003C045"
IOS_BUNDLE_PREFIX = "com.example.italianDrivingApp"
ALLOWED_THIRD_PARTY_PACKAGES = {
    "flutter",
    "flutter_swiper_view",
    "flutter_test",
    "http",
    "package_info_plus",
    "path",
    "path_provider",
    "shared_preferences",
    "sqflite",
    "sqflite_common_ffi",
    "sqflite_common_ffi_web",
    "supabase_flutter",
    "url_launcher",
    "uuid",
}


@dataclass(frozen=True)
class VerificationResult:
    failures: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.failures


class DuplicateJsonKeyError(ValueError):
    pass


class MetadataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.meta: list[dict[str, str]] = []
        self.titles: list[str] = []
        self._in_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "meta":
            self.meta.append({key.lower(): value or "" for key, value in attrs})
        elif tag == "title":
            self._in_title = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._in_title and data.strip():
            self.titles.append(data.strip())


class BrandingVerifier:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.failures: list[str] = []

    def require(self, location: str, condition: bool, actual: object | None = None) -> None:
        if condition:
            return
        detail = "" if actual is None else f" (actual: {actual!r})"
        self.failures.append(f"FAIL {location}{detail}")

    def text(self, relative_path: str) -> str | None:
        try:
            return (self.root / relative_path).read_text(encoding="utf-8")
        except UnicodeDecodeError as error:
            self.failures.append(f"FAIL {relative_path}: unable to read UTF-8 text ({error.reason})")
        except OSError as error:
            self.failures.append(f"FAIL {relative_path}: unable to read file ({error})")
        return None

    def json_object(self, relative_path: str) -> dict[str, object] | None:
        content = self.text(relative_path)
        if content is None:
            return None

        def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
            result: dict[str, object] = {}
            for key, value in pairs:
                if key in result:
                    raise DuplicateJsonKeyError(key)
                result[key] = value
            return result

        try:
            parsed = json.loads(content, object_pairs_hook=reject_duplicate_keys)
        except DuplicateJsonKeyError as error:
            self.failures.append(f"FAIL {relative_path}: duplicate JSON key {error.args[0]!r}")
            return None
        except json.JSONDecodeError as error:
            self.failures.append(f"FAIL {relative_path}: invalid JSON ({error.msg})")
            return None
        if not isinstance(parsed, dict):
            self.failures.append(f"FAIL {relative_path}: top-level JSON value must be an object")
            return None
        return parsed

    def plist_object(self, relative_path: str) -> dict[str, object] | None:
        try:
            with (self.root / relative_path).open("rb") as source:
                parsed = plistlib.load(source)
        except (OSError, UnicodeDecodeError, ValueError, plistlib.InvalidFileException) as error:
            self.failures.append(f"FAIL {relative_path}: invalid plist ({error})")
            return None
        if not isinstance(parsed, dict):
            self.failures.append(f"FAIL {relative_path}: top-level plist value must be a dictionary")
            return None
        return parsed

    def xml_root(self, relative_path: str) -> ElementTree.Element | None:
        try:
            return ElementTree.parse(self.root / relative_path).getroot()
        except (OSError, UnicodeDecodeError, ElementTree.ParseError) as error:
            self.failures.append(f"FAIL {relative_path}: invalid XML ({error})")
            return None

    def require_pattern(self, location: str, content: str | None, pattern: str, *, count: int = 1) -> None:
        if content is None:
            return
        matches = re.findall(pattern, content, flags=re.MULTILINE)
        self.require(location, len(matches) == count, f"matched {len(matches)}, expected {count}")

    def verify_visible_names(self) -> None:
        main = self.text("lib/main.dart")
        self.require_pattern("lib/main.dart: MaterialApp.title", main, r"return\s+MaterialApp\(\s*title:\s*'OldGuida',")

        homepage = self.text("lib/Screen/Homepage.dart")
        self.require_pattern(
            "lib/Screen/Homepage.dart: home AppBar title",
            homepage,
            r"(?s)appBar:\s*AppBar\(.*?title:\s*const Text\('OldGuida',",
        )

        manifest = self.xml_root("android/app/src/main/AndroidManifest.xml")
        if manifest is not None:
            namespace = "{http://schemas.android.com/apk/res/android}"
            application = manifest.find("application")
            label = application.get(f"{namespace}label") if application is not None else None
            self.require("android/app/src/main/AndroidManifest.xml: application android:label", label == DISPLAY_NAME, label)

        info_plist = self.plist_object("ios/Runner/Info.plist")
        if info_plist is not None:
            self.require("ios/Runner/Info.plist: CFBundleDisplayName", info_plist.get("CFBundleDisplayName") == DISPLAY_NAME, info_plist.get("CFBundleDisplayName"))

        app_info = self.text("macos/Runner/Configs/AppInfo.xcconfig")
        self.require_pattern("macos/Runner/Configs/AppInfo.xcconfig: PRODUCT_NAME", app_info, r"^PRODUCT_NAME\s*=\s*OldGuida\s*$")

        macos_project = self.text("macos/Runner.xcodeproj/project.pbxproj")
        self.require_pattern(
            "macos/Runner.xcodeproj/project.pbxproj: product file reference",
            macos_project,
            r'33CC10ED2044A3C60003C045 /\* OldGuida\.app \*/ = \{[^\n]*path = "OldGuida\.app"; sourceTree = BUILT_PRODUCTS_DIR; \};',
        )
        self.require_pattern(
            "macos/Runner.xcodeproj/project.pbxproj: Runner product reference",
            macos_project,
            r"productReference = 33CC10ED2044A3C60003C045 /\* OldGuida\.app \*/;",
        )
        self.require_pattern(
            "macos/Runner.xcodeproj/project.pbxproj: RunnerTests TEST_HOST",
            macos_project,
            r'^\s*TEST_HOST = "\$\(BUILT_PRODUCTS_DIR\)/OldGuida\.app/\$\(BUNDLE_EXECUTABLE_FOLDER_PATH\)/OldGuida";$',
            count=3,
        )
        self.verify_scheme()

        windows_main = self.text("windows/runner/main.cpp")
        self.require_pattern("windows/runner/main.cpp: window.Create title", windows_main, r'^\s*if \(!window\.Create\(L"OldGuida", origin, size\)\) \{$')

        runner_rc = self.text("windows/runner/Runner.rc")
        self.require_pattern("windows/runner/Runner.rc: FileDescription", runner_rc, r'^\s*VALUE "FileDescription", "OldGuida" "\\0"$')
        self.require_pattern("windows/runner/Runner.rc: ProductName", runner_rc, r'^\s*VALUE "ProductName", "OldGuida" "\\0"$')

        linux_runner = self.text("linux/runner/my_application.cc")
        self.require_pattern("linux/runner/my_application.cc: GTK header title", linux_runner, r'^\s*gtk_header_bar_set_title\(header_bar, "OldGuida"\);$')
        self.require_pattern("linux/runner/my_application.cc: GTK fallback window title", linux_runner, r'^\s*gtk_window_set_title\(window, "OldGuida"\);$')

        web_manifest = self.json_object("web/manifest.json")
        if web_manifest is not None:
            self.require("web/manifest.json: name", web_manifest.get("name") == DISPLAY_NAME, web_manifest.get("name"))
            self.require("web/manifest.json: short_name", web_manifest.get("short_name") == DISPLAY_NAME, web_manifest.get("short_name"))
            self.require("web/manifest.json: description", web_manifest.get("description") == WEB_DESCRIPTION, web_manifest.get("description"))

        self.verify_html()
        readme = self.text("README.md")
        if readme is not None:
            first_nonempty = next((line for line in readme.splitlines() if line.strip()), "")
            self.require("README.md: primary heading", first_nonempty == "# OldGuida", first_nonempty)

    def verify_scheme(self) -> None:
        relative_path = "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
        scheme = self.xml_root(relative_path)
        if scheme is None:
            return
        references = {
            "BuildActionEntry": "./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference",
            "TestAction/MacroExpansion": "./TestAction/MacroExpansion/BuildableReference",
            "LaunchAction/BuildableProductRunnable": "./LaunchAction/BuildableProductRunnable/BuildableReference",
            "ProfileAction/BuildableProductRunnable": "./ProfileAction/BuildableProductRunnable/BuildableReference",
        }
        for context, path in references.items():
            reference = scheme.find(path)
            actual = None if reference is None else {
                "BlueprintIdentifier": reference.get("BlueprintIdentifier"),
                "BlueprintName": reference.get("BlueprintName"),
                "BuildableName": reference.get("BuildableName"),
            }
            self.require(
                f"{relative_path}: {context} Runner BuildableReference",
                reference is not None
                and reference.get("BlueprintIdentifier") == RUNNER_BLUEPRINT_ID
                and reference.get("BlueprintName") == "Runner"
                and reference.get("BuildableName") == "OldGuida.app",
                actual,
            )

    def verify_html(self) -> None:
        relative_path = "web/index.html"
        content = self.text(relative_path)
        if content is None:
            return
        try:
            parser = MetadataParser()
            parser.feed(content)
            parser.close()
        except (UnicodeDecodeError, ValueError) as error:
            self.failures.append(f"FAIL {relative_path}: invalid HTML metadata ({error})")
            return
        self.require(f"{relative_path}: title structure", not parser._in_title, "unclosed title" if parser._in_title else None)
        for name, expected in (("description", WEB_DESCRIPTION), ("apple-mobile-web-app-title", DISPLAY_NAME)):
            values = [entry.get("content") for entry in parser.meta if entry.get("name") == name]
            self.require(f"{relative_path}: meta {name}", values == [expected], values)
        self.require(f"{relative_path}: title", parser.titles == [DISPLAY_NAME], parser.titles)

    def verify_preserved_identifiers(self) -> None:
        pubspec = self.text("pubspec.yaml")
        self.require_pattern("pubspec.yaml: package name", pubspec, r"^name:\s*italian_driving_app\s*$")

        android_gradle = self.text("android/app/build.gradle.kts")
        self.require_pattern("android/app/build.gradle.kts: namespace", android_gradle, r'^\s*namespace\s*=\s*"com\.example\.italian_driving_app"\s*$')
        self.require_pattern("android/app/build.gradle.kts: applicationId", android_gradle, r'^\s*applicationId\s*=\s*"com\.example\.italian_driving_app"\s*$')

        ios_plist = self.plist_object("ios/Runner/Info.plist")
        if ios_plist is not None:
            self.require("ios/Runner/Info.plist: CFBundleIdentifier", ios_plist.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)", ios_plist.get("CFBundleIdentifier"))
        self.verify_ios_bundle_identifiers()

        macos_app_info = self.text("macos/Runner/Configs/AppInfo.xcconfig")
        self.require_pattern("macos/Runner/Configs/AppInfo.xcconfig: bundle identifier", macos_app_info, r"^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*com\.example\.italianDrivingApp\s*$")

        linux_cmake = self.text("linux/CMakeLists.txt")
        self.require_pattern("linux/CMakeLists.txt: APPLICATION_ID", linux_cmake, r'^set\(APPLICATION_ID "com\.example\.italian_driving_app"\)$')
        self.require_pattern("linux/CMakeLists.txt: BINARY_NAME", linux_cmake, r'^set\(BINARY_NAME "italian_driving_app"\)$')
        windows_cmake = self.text("windows/CMakeLists.txt")
        self.require_pattern("windows/CMakeLists.txt: BINARY_NAME", windows_cmake, r'^set\(BINARY_NAME "italian_driving_app"\)$')

        windows_rc = self.text("windows/runner/Runner.rc")
        self.require_pattern("windows/runner/Runner.rc: InternalName", windows_rc, r'^\s*VALUE "InternalName", "italian_driving_app" "\\0"$')
        self.require_pattern("windows/runner/Runner.rc: OriginalFilename", windows_rc, r'^\s*VALUE "OriginalFilename", "italian_driving_app\.exe" "\\0"$')

        http_overrides = self.text("lib/utils/http_overrides_io.dart")
        self.require_pattern("lib/utils/http_overrides_io.dart: HTTP user-agent", http_overrides, r"^\s*client\.userAgent\s*=\s*'italian_driving_app';$")
        sanitizing_client = self.text("lib/utils/sanitizing_client_io.dart")
        self.require_pattern("lib/utils/sanitizing_client_io.dart: HTTP user-agent", sanitizing_client, r"^\s*request\.headers\[HttpHeaders\.userAgentHeader\]\s*=\s*'italian_driving_app';$")
        self.verify_dart_imports()

    def pbx_objects(self, content: str) -> dict[str, str]:
        objects: dict[str, str] = {}
        for match in re.finditer(r"(?m)^\s*([A-F0-9]+) /\* .*? \*/ = \{", content):
            object_id = match.group(1)
            depth = 1
            in_string = False
            escaped = False
            index = match.end()
            while index < len(content) and depth:
                character = content[index]
                if in_string:
                    if escaped:
                        escaped = False
                    elif character == "\\":
                        escaped = True
                    elif character == '"':
                        in_string = False
                elif character == '"':
                    in_string = True
                elif character == "{":
                    depth += 1
                elif character == "}":
                    depth -= 1
                index += 1
            if depth:
                self.failures.append(f"FAIL ios/Runner.xcodeproj/project.pbxproj: unterminated object {object_id}")
            else:
                objects[object_id] = content[match.end() : index - 1]
        return objects

    def verify_ios_bundle_identifiers(self) -> None:
        relative_path = "ios/Runner.xcodeproj/project.pbxproj"
        content = self.text(relative_path)
        if content is None:
            return
        objects = self.pbx_objects(content)
        expected_targets = {
            "Runner": IOS_BUNDLE_PREFIX,
            "RunnerTests": f"{IOS_BUNDLE_PREFIX}.RunnerTests",
            "RunnerUITests": f"{IOS_BUNDLE_PREFIX}.RunnerUITests",
        }
        found_targets: set[str] = set()
        for object_body in objects.values():
            if "isa = PBXNativeTarget;" not in object_body:
                continue
            target_match = re.search(r"(?m)^\s*name = (Runner(?:Tests|UITests)?);$", object_body)
            if target_match is None:
                continue
            target_name = target_match.group(1)
            found_targets.add(target_name)
            configuration_match = re.search(r"buildConfigurationList = ([A-F0-9]+) /\*", object_body)
            if configuration_match is None:
                self.failures.append(f"FAIL {relative_path}: {target_name} missing build configuration list")
                continue
            configuration_list = objects.get(configuration_match.group(1))
            if configuration_list is None:
                self.failures.append(f"FAIL {relative_path}: {target_name} missing configuration list object")
                continue
            configuration_ids = re.findall(r"(?m)^\s*([A-F0-9]+) /\* (Debug|Release|Profile) \*/,$", configuration_list)
            configurations = {name: object_id for object_id, name in configuration_ids}
            for configuration_name in ("Debug", "Release", "Profile"):
                configuration = objects.get(configurations.get(configuration_name, ""))
                bundle_match = None if configuration is None else re.search(r"(?m)^\s*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);$", configuration)
                actual = None if bundle_match is None else bundle_match.group(1)
                self.require(
                    f"{relative_path}: {target_name} {configuration_name} bundle identifier",
                    actual == expected_targets[target_name],
                    actual,
                )
        for target_name in ("Runner", "RunnerTests"):
            self.require(f"{relative_path}: {target_name} target", target_name in found_targets, sorted(found_targets))

    def strip_dart_comments(self, relative_path: str, content: str) -> str | None:
        result: list[str] = []
        index = 0
        quote = ""
        triple = False
        block_depth = 0
        while index < len(content):
            if quote:
                if triple and content.startswith(quote * 3, index):
                    result.append(quote * 3)
                    index += 3
                    quote = ""
                    triple = False
                elif not triple and content[index] == quote:
                    result.append(content[index])
                    index += 1
                    quote = ""
                elif content[index] == "\\" and index + 1 < len(content):
                    result.extend(content[index : index + 2])
                    index += 2
                else:
                    result.append(content[index])
                    index += 1
                continue
            if content.startswith("//", index):
                newline = content.find("\n", index)
                if newline == -1:
                    break
                result.append("\n")
                index = newline + 1
                continue
            if content.startswith("/*", index):
                block_depth = 1
                index += 2
                while index < len(content) and block_depth:
                    if content.startswith("/*", index):
                        block_depth += 1
                        index += 2
                    elif content.startswith("*/", index):
                        block_depth -= 1
                        index += 2
                    else:
                        if content[index] == "\n":
                            result.append("\n")
                        index += 1
                if block_depth:
                    self.failures.append(f"FAIL {relative_path}: unterminated block comment")
                    return None
                continue
            if content[index] in "'\"":
                quote = content[index]
                triple = content.startswith(quote * 3, index)
                width = 3 if triple else 1
                result.append(content[index : index + width])
                index += width
                continue
            result.append(content[index])
            index += 1
        return "".join(result)

    def verify_dart_imports(self) -> None:
        for directory in ("lib", "test"):
            for path in sorted((self.root / directory).rglob("*.dart")):
                relative_path = path.relative_to(self.root).as_posix()
                content = self.text(relative_path)
                if content is None:
                    continue
                uncommented = self.strip_dart_comments(relative_path, content)
                if uncommented is None:
                    continue
                for statement in re.finditer(r"(?ms)^\s*import\s+(.*?);", uncommented):
                    for uri in re.findall(r"['\"]([^'\"]+)['\"]", statement.group(1)):
                        if not uri.startswith("package:"):
                            continue
                        package_name = uri.removeprefix("package:").split("/", 1)[0]
                        if package_name.casefold() == "oldguida":
                            self.failures.append(f"FAIL {relative_path}: oldguida package import {uri!r}")
                        elif package_name == "italian_driving_app" or package_name in ALLOWED_THIRD_PARTY_PACKAGES:
                            continue
                        else:
                            self.failures.append(f"FAIL {relative_path}: unexpected package import {uri!r}")

    def verify(self) -> VerificationResult:
        self.verify_visible_names()
        self.verify_preserved_identifiers()
        return VerificationResult(tuple(self.failures))

    def run(self) -> int:
        return 0 if self.verify().ok else 1


def verify(root: Path) -> VerificationResult:
    return BrandingVerifier(root.resolve()).verify()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True, help="repository root")
    args = parser.parse_args()
    result = verify(args.root)
    if result.ok:
        print("PASS: OldGuida branding metadata verified")
        return 0
    print(*result.failures, sep="\n")
    print(f"FAIL: {len(result.failures)} branding check(s) failed")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
