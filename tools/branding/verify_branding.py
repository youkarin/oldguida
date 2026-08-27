"""Verify OldGuida display metadata while preserving internal identifiers."""

from __future__ import annotations

import argparse
from pathlib import Path


VISIBLE_NAME_FILES = {
    "lib/main.dart": "title: 'OldGuida'",
    "lib/Screen/Homepage.dart": "OldGuida",
    "android/app/src/main/AndroidManifest.xml": 'android:label="OldGuida"',
    "ios/Runner/Info.plist": "<string>OldGuida</string>",
    "macos/Runner/Configs/AppInfo.xcconfig": "PRODUCT_NAME = OldGuida",
    "windows/runner/main.cpp": 'window.Create(L"OldGuida"',
    "windows/runner/Runner.rc": 'VALUE "ProductName", "OldGuida"',
    "linux/runner/my_application.cc": 'gtk_header_bar_set_title(header_bar, "OldGuida")',
    "web/manifest.json": '"name": "OldGuida"',
    "web/index.html": "<title>OldGuida</title>",
}

PRESERVED_IDENTIFIERS = {
    "pubspec.yaml": "name: italian_driving_app",
    "android/app/build.gradle.kts": 'applicationId = "com.example.italian_driving_app"',
    "ios/Runner.xcodeproj/project.pbxproj": "PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp;",
    "macos/Runner/Configs/AppInfo.xcconfig": "PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp",
    "linux/CMakeLists.txt": 'set(APPLICATION_ID "com.example.italian_driving_app")',
    "windows/CMakeLists.txt": 'set(BINARY_NAME "italian_driving_app")',
}


def verify(root: Path, checks: dict[str, str], category: str) -> list[str]:
    """Return a failure message for every expected string absent from a file."""
    failures: list[str] = []
    for relative_path, expected in checks.items():
        path = root / relative_path
        try:
            content = path.read_text(encoding="utf-8")
        except OSError as error:
            failures.append(f"FAIL {category}: {relative_path} ({error})")
            continue
        if expected in content:
            print(f"PASS {category}: {relative_path}")
        else:
            failures.append(f"FAIL {category}: {relative_path} missing {expected!r}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True, help="repository root")
    args = parser.parse_args()

    root = args.root.resolve()
    failures = verify(root, VISIBLE_NAME_FILES, "visible name")
    failures.extend(verify(root, PRESERVED_IDENTIFIERS, "preserved identifier"))
    if failures:
        print(*failures, sep="\n")
        return 1

    print("PASS: OldGuida branding metadata verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
