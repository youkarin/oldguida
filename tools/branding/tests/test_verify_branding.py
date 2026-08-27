import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree

from tools.branding.verify_branding import RUNNER_BLUEPRINT_ID, verify


SOURCE_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_FILES = (
    "README.md",
    "pubspec.yaml",
    "android/app/build.gradle.kts",
    "android/app/src/main/AndroidManifest.xml",
    "ios/Runner/Info.plist",
    "ios/Runner.xcodeproj/project.pbxproj",
    "linux/CMakeLists.txt",
    "linux/runner/my_application.cc",
    "macos/Runner/Configs/AppInfo.xcconfig",
    "macos/Runner.xcodeproj/project.pbxproj",
    "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme",
    "web/index.html",
    "web/manifest.json",
    "windows/CMakeLists.txt",
    "windows/runner/Runner.rc",
    "windows/runner/main.cpp",
)


class BrandingVerifierTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        for relative_path in FIXTURE_FILES:
            destination = self.root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE_ROOT / relative_path, destination)
        shutil.copytree(SOURCE_ROOT / "lib", self.root / "lib")
        shutil.copytree(SOURCE_ROOT / "test", self.root / "test")

    def tearDown(self):
        self.temporary_directory.cleanup()

    def run_verifier(self):
        result = verify(self.root)
        return (0 if result.ok else 1), result.failures

    def test_rejects_runner_scheme_node_compensated_by_testable_reference(self):
        scheme_path = self.root / "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
        tree = ElementTree.parse(scheme_path)
        build_reference = tree.find("./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")
        testable_reference = tree.find("./TestAction/Testables/TestableReference/BuildableReference")
        self.assertIsNotNone(build_reference)
        self.assertIsNotNone(testable_reference)
        build_reference.set("BlueprintIdentifier", "331C80D4294CF70F00263BE5")
        testable_reference.set("BlueprintIdentifier", RUNNER_BLUEPRINT_ID)
        testable_reference.set("BuildableName", "OldGuida.app")
        tree.write(scheme_path, encoding="utf-8", xml_declaration=True)

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("BuildActionEntry" in failure for failure in failures))

    def test_rejects_ios_bundle_identifiers_when_runner_and_tests_are_swapped(self):
        project_path = self.root / "ios/Runner.xcodeproj/project.pbxproj"
        project = project_path.read_text(encoding="utf-8")
        runner = "PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp;"
        tests = "PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp.RunnerTests;"
        swapped = project.replace(runner, "__RUNNER__").replace(tests, runner).replace("__RUNNER__", tests)
        project_path.write_text(swapped, encoding="utf-8")

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("Runner Debug bundle identifier" in failure for failure in failures))
        self.assertTrue(any("RunnerTests Debug bundle identifier" in failure for failure in failures))

    def test_rejects_duplicate_json_keys_instead_of_accepting_the_last_value(self):
        manifest_path = self.root / "web/manifest.json"
        manifest = manifest_path.read_text(encoding="utf-8")
        manifest_path.write_text(
            manifest.replace('"name": "OldGuida",', '"name": "OldGuida",\n    "name": "OldGuida",'),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("duplicate JSON key 'name'" in failure for failure in failures))

    def test_rejects_duplicate_html_metadata_even_when_the_last_value_is_correct(self):
        index_path = self.root / "web/index.html"
        index = index_path.read_text(encoding="utf-8")
        description = '<meta name="description" content="意大利驾考学习工具">'
        self.assertIn(description, index)
        index_path.write_text(index.replace(description, f"{description}\n  {description}"), encoding="utf-8")

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("web/index.html: meta description" in failure for failure in failures))

    def test_rejects_comment_compensated_and_case_variant_dart_package_import(self):
        source_path = self.root / "lib/Services/auth_service.dart"
        source = source_path.read_text(encoding="utf-8")
        source_path.write_text(
            source.replace(
                "import 'package:italian_driving_app/database/database_helper.dart';",
                "/*\nimport 'package:italian_driving_app/database/database_helper.dart';\n*/\n"
                "import 'package:oldguida/database/database_helper.dart';",
            ),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("oldguida package import" in failure for failure in failures))

    def test_returns_friendly_failures_for_non_mapping_and_undecodable_inputs(self):
        manifest_path = self.root / "web/manifest.json"
        manifest_path.write_text(json.dumps([]), encoding="utf-8")
        plist_path = self.root / "ios/Runner/Info.plist"
        with plist_path.open("wb") as source:
            plistlib.dump([], source)
        main_path = self.root / "lib/main.dart"
        main_path.write_bytes(b"\xff")

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("web/manifest.json: top-level JSON value must be an object" in failure for failure in failures))
        self.assertTrue(any("ios/Runner/Info.plist: top-level plist value must be a dictionary" in failure for failure in failures))
        self.assertTrue(any("lib/main.dart: unable to read UTF-8 text" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
