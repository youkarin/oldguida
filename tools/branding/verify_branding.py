"""Verify OldGuida display metadata and protected application identifiers."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree


DISPLAY_NAME = "OldGuida"
WEB_DESCRIPTION = "意大利驾考学习工具"
RUNNER_BLUEPRINT_ID = "33CC10EC2044A3C60003C045"
EXPECTED_DART_PACKAGE_IMPORTS = 53


class MetadataParser(HTMLParser):
    """Collect the title and named meta elements without matching comments."""

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
        if self._in_title:
            self.titles.append(data.strip())


class BrandingVerifier:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.failures: list[str] = []

    def require(self, location: str, condition: bool, actual: object | None = None) -> None:
        if condition:
            print(f"PASS {location}")
            return
        detail = "" if actual is None else f" (actual: {actual!r})"
        self.failures.append(f"FAIL {location}{detail}")

    def text(self, relative_path: str) -> str | None:
        try:
            return (self.root / relative_path).read_text(encoding="utf-8")
        except OSError as error:
            self.failures.append(f"FAIL {relative_path}: unable to read file ({error})")
            return None

    def json(self, relative_path: str) -> dict[str, object] | None:
        content = self.text(relative_path)
        if content is None:
            return None
        try:
            return json.loads(content)
        except json.JSONDecodeError as error:
            self.failures.append(f"FAIL {relative_path}: invalid JSON ({error.msg})")
            return None

    def plist(self, relative_path: str) -> dict[str, object] | None:
        try:
            with (self.root / relative_path).open("rb") as source:
                return plistlib.load(source)
        except (OSError, plistlib.InvalidFileException) as error:
            self.failures.append(f"FAIL {relative_path}: invalid plist ({error})")
            return None

    def xml(self, relative_path: str) -> ElementTree.Element | None:
        try:
            return ElementTree.parse(self.root / relative_path).getroot()
        except (OSError, ElementTree.ParseError) as error:
            self.failures.append(f"FAIL {relative_path}: invalid XML ({error})")
            return None

    def require_pattern(self, location: str, content: str | None, pattern: str, *, count: int = 1) -> None:
        if content is None:
            return
        matches = re.findall(pattern, content, flags=re.MULTILINE)
        self.require(location, len(matches) == count, f"matched {len(matches)}, expected {count}")

    def verify_visible_names(self) -> None:
        main = self.text("lib/main.dart")
        self.require_pattern(
            "lib/main.dart: MaterialApp.title",
            main,
            r"return\s+MaterialApp\(\s*title:\s*'OldGuida',",
        )

        homepage = self.text("lib/Screen/Homepage.dart")
        self.require_pattern(
            "lib/Screen/Homepage.dart: home AppBar title",
            homepage,
            r"(?s)appBar:\s*AppBar\(.*?title:\s*const Text\('OldGuida',",
        )

        manifest = self.xml("android/app/src/main/AndroidManifest.xml")
        if manifest is not None:
            namespace = "{http://schemas.android.com/apk/res/android}"
            application = manifest.find("application")
            label = application.get(f"{namespace}label") if application is not None else None
            self.require("android/app/src/main/AndroidManifest.xml: application android:label", label == DISPLAY_NAME, label)

        info_plist = self.plist("ios/Runner/Info.plist")
        if info_plist is not None:
            self.require("ios/Runner/Info.plist: CFBundleDisplayName", info_plist.get("CFBundleDisplayName") == DISPLAY_NAME, info_plist.get("CFBundleDisplayName"))

        app_info = self.text("macos/Runner/Configs/AppInfo.xcconfig")
        self.require_pattern(
            "macos/Runner/Configs/AppInfo.xcconfig: PRODUCT_NAME",
            app_info,
            r"^PRODUCT_NAME\s*=\s*OldGuida\s*$",
        )

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

        scheme = self.xml("macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme")
        if scheme is not None:
            runner_references = [
                reference
                for reference in scheme.findall(".//BuildableReference")
                if reference.get("BlueprintIdentifier") == RUNNER_BLUEPRINT_ID
            ]
            names = [reference.get("BuildableName") for reference in runner_references]
            self.require(
                "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme: Runner BuildableName",
                len(names) == 4 and all(name == "OldGuida.app" for name in names),
                names,
            )

        windows_main = self.text("windows/runner/main.cpp")
        self.require_pattern(
            "windows/runner/main.cpp: window.Create title",
            windows_main,
            r'^\s*if \(!window\.Create\(L"OldGuida", origin, size\)\) \{$',
        )

        runner_rc = self.text("windows/runner/Runner.rc")
        self.require_pattern(
            "windows/runner/Runner.rc: FileDescription",
            runner_rc,
            r'^\s*VALUE "FileDescription", "OldGuida" "\\0"$',
        )
        self.require_pattern(
            "windows/runner/Runner.rc: ProductName",
            runner_rc,
            r'^\s*VALUE "ProductName", "OldGuida" "\\0"$',
        )

        linux_runner = self.text("linux/runner/my_application.cc")
        self.require_pattern(
            "linux/runner/my_application.cc: GTK header title",
            linux_runner,
            r'^\s*gtk_header_bar_set_title\(header_bar, "OldGuida"\);$',
        )
        self.require_pattern(
            "linux/runner/my_application.cc: GTK fallback window title",
            linux_runner,
            r'^\s*gtk_window_set_title\(window, "OldGuida"\);$',
        )

        web_manifest = self.json("web/manifest.json")
        if web_manifest is not None:
            self.require("web/manifest.json: name", web_manifest.get("name") == DISPLAY_NAME, web_manifest.get("name"))
            self.require("web/manifest.json: short_name", web_manifest.get("short_name") == DISPLAY_NAME, web_manifest.get("short_name"))
            self.require("web/manifest.json: description", web_manifest.get("description") == WEB_DESCRIPTION, web_manifest.get("description"))

        index_html = self.text("web/index.html")
        if index_html is not None:
            parser = MetadataParser()
            parser.feed(index_html)
            parser.close()
            meta = {entry.get("name"): entry.get("content") for entry in parser.meta if entry.get("name")}
            self.require("web/index.html: meta description", meta.get("description") == WEB_DESCRIPTION, meta.get("description"))
            self.require("web/index.html: apple-mobile-web-app-title", meta.get("apple-mobile-web-app-title") == DISPLAY_NAME, meta.get("apple-mobile-web-app-title"))
            self.require("web/index.html: title", parser.titles == [DISPLAY_NAME], parser.titles)

        readme = self.text("README.md")
        if readme is not None:
            first_nonempty = next((line for line in readme.splitlines() if line.strip()), "")
            self.require("README.md: primary heading", first_nonempty == "# OldGuida", first_nonempty)

    def verify_preserved_identifiers(self) -> None:
        pubspec = self.text("pubspec.yaml")
        self.require_pattern("pubspec.yaml: package name", pubspec, r"^name:\s*italian_driving_app\s*$")

        android_gradle = self.text("android/app/build.gradle.kts")
        self.require_pattern(
            "android/app/build.gradle.kts: namespace",
            android_gradle,
            r'^\s*namespace\s*=\s*"com\.example\.italian_driving_app"\s*$',
        )
        self.require_pattern(
            "android/app/build.gradle.kts: applicationId",
            android_gradle,
            r'^\s*applicationId\s*=\s*"com\.example\.italian_driving_app"\s*$',
        )

        ios_plist = self.plist("ios/Runner/Info.plist")
        if ios_plist is not None:
            self.require("ios/Runner/Info.plist: CFBundleIdentifier", ios_plist.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)", ios_plist.get("CFBundleIdentifier"))

        ios_project = self.text("ios/Runner.xcodeproj/project.pbxproj")
        self.require_pattern(
            "ios/Runner.xcodeproj/project.pbxproj: Runner bundle identifier",
            ios_project,
            r'^\s*PRODUCT_BUNDLE_IDENTIFIER = com\.example\.italianDrivingApp;$',
            count=3,
        )

        macos_app_info = self.text("macos/Runner/Configs/AppInfo.xcconfig")
        self.require_pattern(
            "macos/Runner/Configs/AppInfo.xcconfig: bundle identifier",
            macos_app_info,
            r"^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*com\.example\.italianDrivingApp\s*$",
        )

        linux_cmake = self.text("linux/CMakeLists.txt")
        self.require_pattern(
            "linux/CMakeLists.txt: APPLICATION_ID",
            linux_cmake,
            r'^set\(APPLICATION_ID "com\.example\.italian_driving_app"\)$',
        )
        self.require_pattern(
            "linux/CMakeLists.txt: BINARY_NAME",
            linux_cmake,
            r'^set\(BINARY_NAME "italian_driving_app"\)$',
        )

        windows_cmake = self.text("windows/CMakeLists.txt")
        self.require_pattern(
            "windows/CMakeLists.txt: BINARY_NAME",
            windows_cmake,
            r'^set\(BINARY_NAME "italian_driving_app"\)$',
        )

        windows_rc = self.text("windows/runner/Runner.rc")
        self.require_pattern(
            "windows/runner/Runner.rc: InternalName",
            windows_rc,
            r'^\s*VALUE "InternalName", "italian_driving_app" "\\0"$',
        )
        self.require_pattern(
            "windows/runner/Runner.rc: OriginalFilename",
            windows_rc,
            r'^\s*VALUE "OriginalFilename", "italian_driving_app\.exe" "\\0"$',
        )

        http_overrides = self.text("lib/utils/http_overrides_io.dart")
        self.require_pattern(
            "lib/utils/http_overrides_io.dart: HTTP user-agent",
            http_overrides,
            r"^\s*client\.userAgent\s*=\s*'italian_driving_app';$",
        )
        sanitizing_client = self.text("lib/utils/sanitizing_client_io.dart")
        self.require_pattern(
            "lib/utils/sanitizing_client_io.dart: HTTP user-agent",
            sanitizing_client,
            r"^\s*request\.headers\[HttpHeaders\.userAgentHeader\]\s*=\s*'italian_driving_app';$",
        )

        main = self.text("lib/main.dart")
        self.require_pattern(
            "lib/main.dart: package import",
            main,
            r"^import 'package:italian_driving_app/database/database_factory\.dart';$",
        )
        homepage = self.text("lib/Screen/Homepage.dart")
        self.require_pattern(
            "lib/Screen/Homepage.dart: package import",
            homepage,
            r"^import 'package:italian_driving_app/database/database_helper\.dart';$",
        )

        dart_files = [
            *sorted((self.root / "lib").rglob("*.dart")),
            *sorted((self.root / "test").rglob("*.dart")),
        ]
        package_import_pattern = re.compile(
            r"(?:^import\s+|^\s+if\s+\([^\n]+\)\s*)'package:italian_driving_app/[^']+'",
            re.MULTILINE,
        )
        oldguida_package_pattern = re.compile(r"package:OldGuida/")
        package_imports = 0
        oldguida_package_imports = 0
        for path in dart_files:
            content = path.read_text(encoding="utf-8")
            package_imports += len(package_import_pattern.findall(content))
            oldguida_package_imports += len(oldguida_package_pattern.findall(content))
        self.require(
            "lib/ and test/: italian_driving_app package import count",
            package_imports == EXPECTED_DART_PACKAGE_IMPORTS,
            package_imports,
        )
        self.require(
            "lib/ and test/: no OldGuida package imports",
            oldguida_package_imports == 0,
            oldguida_package_imports,
        )

    def run(self) -> int:
        self.verify_visible_names()
        self.verify_preserved_identifiers()
        if self.failures:
            print(*self.failures, sep="\n")
            print(f"FAIL: {len(self.failures)} branding check(s) failed")
            return 1
        print("PASS: OldGuida branding metadata verified")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True, help="repository root")
    args = parser.parse_args()
    return BrandingVerifier(args.root.resolve()).run()


if __name__ == "__main__":
    raise SystemExit(main())
