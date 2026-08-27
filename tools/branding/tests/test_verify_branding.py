import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree

from tools.branding.verify_branding import BrandingVerifier, RUNNER_BLUEPRINT_ID, verify


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

    def ios_project(self):
        return self.root / "ios/Runner.xcodeproj/project.pbxproj"

    def replace_runner_profile_name(self, replacement):
        project_path = self.ios_project()
        project = project_path.read_text(encoding="utf-8")
        start = project.index("249021D4217E4FDB00AE95B9 /* Profile */ = {")
        name_index = project.index("name = Profile;", start)
        project_path.write_text(project[:name_index] + replacement + project[name_index + len("name = Profile;") :], encoding="utf-8")

    def add_build_action_entry(self, blueprint_identifier, buildable_name, blueprint_name):
        scheme_path = self.root / "macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
        tree = ElementTree.parse(scheme_path)
        entries = tree.find("./BuildAction/BuildActionEntries")
        self.assertIsNotNone(entries)
        entry = ElementTree.SubElement(entries, "BuildActionEntry", {"buildForTesting": "YES"})
        ElementTree.SubElement(
            entry,
            "BuildableReference",
            {
                "BuildableIdentifier": "primary",
                "BlueprintIdentifier": blueprint_identifier,
                "BuildableName": buildable_name,
                "BlueprintName": blueprint_name,
                "ReferencedContainer": "container:Runner.xcodeproj",
            },
        )
        tree.write(scheme_path, encoding="utf-8", xml_declaration=True)

    def move_runner_debug_bundle_outside_build_settings(self):
        project_path = self.ios_project()
        project = project_path.read_text(encoding="utf-8")
        configuration_start = project.index("97C147061CF9000F007C117D /* Debug */ = {")
        settings_start = project.index("buildSettings = {", configuration_start)
        bundle_start = project.index("PRODUCT_BUNDLE_IDENTIFIER = com.example.italianDrivingApp;", settings_start)
        bundle_line_start = project.rfind("\n", settings_start, bundle_start) + 1
        bundle_line_end = project.index("\n", bundle_start) + 1
        bundle_line = project[bundle_line_start:bundle_line_end]
        project = project[:bundle_line_start] + project[bundle_line_end:]
        settings_end = project.index("};", settings_start) + len("};")
        project = project[:settings_end] + "\n" + bundle_line + project[settings_end:]
        project_path.write_text(project, encoding="utf-8")

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

    def test_returns_friendly_failure_for_unknown_plist_encoding(self):
        plist_path = self.root / "ios/Runner/Info.plist"
        plist = plist_path.read_bytes()
        self.assertIn(b"UTF-8", plist)
        plist_path.write_bytes(plist.replace(b"UTF-8", b"unknown-branding-encoding", 1))

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("ios/Runner/Info.plist: invalid plist" in failure for failure in failures))

    def test_returns_friendly_failure_for_unknown_xml_encoding(self):
        manifest_path = self.root / "android/app/src/main/AndroidManifest.xml"
        manifest = manifest_path.read_text(encoding="utf-8")
        manifest_path.write_text(
            '<?xml version="1.0" encoding="unknown-branding-encoding"?>\n' + manifest,
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("AndroidManifest.xml: invalid XML" in failure for failure in failures))

    def test_returns_friendly_failure_for_json_value_error(self):
        manifest_path = self.root / "web/manifest.json"
        manifest_path.write_text('{"value": ' + "1" * 5000 + "}", encoding="utf-8")

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("web/manifest.json: invalid JSON" in failure for failure in failures))

    def test_rejects_duplicate_html_attributes(self):
        index_path = self.root / "web/index.html"
        index = index_path.read_text(encoding="utf-8")
        index_path.write_text(
            index.replace(
                'name="description" content="意大利驾考学习工具"',
                'name="description" content="意大利驾考学习工具" content="意大利驾考学习工具"',
            ),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("duplicate HTML attribute 'content'" in failure for failure in failures))

    def test_rejects_reused_pbx_configuration_id(self):
        project_path = self.ios_project()
        project = project_path.read_text(encoding="utf-8")
        project_path.write_text(
            project.replace(
                "249021D4217E4FDB00AE95B9 /* Profile */,",
                "97C147061CF9000F007C117D /* Profile */,",
                1,
            ),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("Runner: configuration ID" in failure for failure in failures))

    def test_rejects_pbx_configuration_with_wrong_block_name(self):
        self.replace_runner_profile_name("name = Other;")

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("Runner Profile configuration block name" in failure for failure in failures))

    def test_rejects_bundle_identifier_outside_pbx_build_settings(self):
        self.move_runner_debug_bundle_outside_build_settings()

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("Runner Debug bundle identifier" in failure for failure in failures))

    def test_allows_other_target_second_build_action_entry(self):
        self.add_build_action_entry("331C80D4294CF70F00263BE5", "RunnerTests.xctest", "RunnerTests")

        code, failures = self.run_verifier()

        self.assertEqual(code, 0)
        self.assertFalse(failures)

    def test_rejects_runner_identifier_with_legacy_name_and_old_buildable_name(self):
        self.add_build_action_entry(RUNNER_BLUEPRINT_ID, "italian_driving_app.app", "LegacyRunner")

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("BuildActionEntry Runner BuildableReference" in failure for failure in failures))

    def test_ignores_dart_block_comment_import(self):
        source_path = self.root / "lib/Services/auth_service.dart"
        source_path.write_text(
            source_path.read_text(encoding="utf-8") + "\n/* import 'package:oldguida/ignored.dart'; */\n",
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 0)
        self.assertFalse(failures)

    def test_ignores_dart_triple_quoted_string_import(self):
        source_path = self.root / "lib/Services/auth_service.dart"
        source_path.write_text(
            source_path.read_text(encoding="utf-8") + '\nconst ignoredImport = """\nimport \'package:oldguida/ignored.dart\';\n""";\n',
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 0)
        self.assertFalse(failures)

    def test_ignores_dart_raw_triple_quoted_string_import(self):
        source_path = self.root / "lib/Services/auth_service.dart"
        raw_source = 'const ignoredRawImport = r"""\\nimport \'package:oldguida/ignored.dart\';\\n""";\n'
        source_path.write_text(source_path.read_text(encoding="utf-8") + "\n" + raw_source, encoding="utf-8")

        tokens = BrandingVerifier(self.root).dart_tokens("lib/Services/auth_service.dart", raw_source)
        self.assertIn(("string", "\\nimport 'package:oldguida/ignored.dart';\\n", True), tokens)

        code, failures = self.run_verifier()

        self.assertEqual(code, 0)
        self.assertFalse(failures)

    def test_allows_declared_cupertino_icons_dependency(self):
        source_path = self.root / "lib/Services/auth_service.dart"
        source_path.write_text(
            "import 'package:cupertino_icons/cupertino_icons.dart';\n" + source_path.read_text(encoding="utf-8"),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 0)
        self.assertFalse(failures)

    def test_allows_quoted_pubspec_dependency_key(self):
        pubspec_path = self.root / "pubspec.yaml"
        pubspec_path.write_text(
            pubspec_path.read_text(encoding="utf-8").replace("  cupertino_icons:", '  "cupertino_icons":'),
            encoding="utf-8",
        )
        source_path = self.root / "lib/Services/auth_service.dart"
        source_path.write_text(
            "import 'package:cupertino_icons/cupertino_icons.dart';\n" + source_path.read_text(encoding="utf-8"),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 0)
        self.assertFalse(failures)

    def test_rejects_oldguida_package_with_mixed_case(self):
        source_path = self.root / "lib/Services/auth_service.dart"
        source_path.write_text(
            "import 'package:OlDgUiDa/blocked.dart';\n" + source_path.read_text(encoding="utf-8"),
            encoding="utf-8",
        )

        code, failures = self.run_verifier()

        self.assertEqual(code, 1)
        self.assertTrue(any("oldguida package import" in failure for failure in failures))

    def test_repeated_verify_calls_do_not_leak_failures(self):
        first_success = verify(self.root)
        manifest_path = self.root / "web/manifest.json"
        original_manifest = manifest_path.read_text(encoding="utf-8")
        manifest_path.write_text(original_manifest.replace('"name": "OldGuida"', '"name": "Wrong"'), encoding="utf-8")
        failure = verify(self.root)
        manifest_path.write_text(original_manifest, encoding="utf-8")
        restored_success = verify(self.root)

        self.assertTrue(first_success.ok)
        self.assertFalse(failure.ok)
        self.assertTrue(restored_success.ok)

    def test_cli_reports_success_and_failure_exit_codes(self):
        command = [sys.executable, str(SOURCE_ROOT / "tools/branding/verify_branding.py"), "--root", str(self.root)]
        success = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(success.returncode, 0)
        self.assertIn("PASS: OldGuida branding metadata verified", success.stdout)

        manifest_path = self.root / "web/manifest.json"
        manifest_path.write_text(manifest_path.read_text(encoding="utf-8").replace('"name": "OldGuida"', '"name": "Wrong"'), encoding="utf-8")
        failure = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(failure.returncode, 1)
        self.assertIn("web/manifest.json: name", failure.stdout)
        self.assertIn("FAIL:", failure.stdout)


if __name__ == "__main__":
    unittest.main()
