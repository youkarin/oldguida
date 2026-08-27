import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.keywords.verify_protected_tables import snapshot


SOURCE_ROOT = Path(__file__).resolve().parents[3]


class ProtectedTableSnapshotTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temporary_directory.name) / "quiz.db"
        connection = sqlite3.connect(self.db_path)
        try:
            connection.executescript(
                """
                CREATE TABLE quiz (
                    id INTEGER PRIMARY KEY,
                    question TEXT,
                    answer INTEGER,
                    section_id INTEGER,
                    translation TEXT,
                    explanation TEXT,
                    question_number INTEGER
                );
                CREATE TABLE chapter (
                    id INTEGER PRIMARY KEY,
                    chapter_id INTEGER,
                    name TEXT,
                    image_path TEXT
                );
                CREATE TABLE section (
                    id INTEGER PRIMARY KEY,
                    section_id INTEGER,
                    chapter_id INTEGER,
                    name TEXT,
                    image_path TEXT
                );
                INSERT INTO quiz VALUES (1, 'L’autovettura originale', 1, 10, NULL, '说明', 100);
                INSERT INTO chapter VALUES (1, 10, 'Capitolo 中文', NULL);
                INSERT INTO section VALUES (1, 10, 1, 'Sezione', 'section.png');
                """
            )
        finally:
            connection.close()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_snapshot_changes_when_a_question_changes(self):
        before = snapshot(self.db_path)

        self.update("UPDATE quiz SET question = 'changed' WHERE id = 1")

        after = snapshot(self.db_path)

        self.assertEqual(set(before), {"quiz", "chapter", "section"})
        self.assertEqual(before["quiz"]["rows"], after["quiz"]["rows"])
        self.assertNotEqual(before["quiz"]["sha256"], after["quiz"]["sha256"])
        self.assertEqual(before["chapter"], after["chapter"])
        self.assertEqual(before["section"], after["section"])

    def test_snapshot_changes_when_a_chapter_changes(self):
        before = snapshot(self.db_path)

        self.update("UPDATE chapter SET name = 'changed' WHERE id = 1")

        after = snapshot(self.db_path)

        self.assertEqual(before["chapter"]["rows"], after["chapter"]["rows"])
        self.assertNotEqual(before["chapter"]["sha256"], after["chapter"]["sha256"])
        self.assertEqual(before["quiz"], after["quiz"])
        self.assertEqual(before["section"], after["section"])

    def test_snapshot_changes_when_a_section_changes(self):
        before = snapshot(self.db_path)

        self.update("UPDATE section SET name = 'changed' WHERE id = 1")

        after = snapshot(self.db_path)

        self.assertEqual(before["section"]["rows"], after["section"]["rows"])
        self.assertNotEqual(before["section"]["sha256"], after["section"]["sha256"])
        self.assertEqual(before["quiz"], after["quiz"])
        self.assertEqual(before["chapter"], after["chapter"])

    def test_snapshot_is_stable_for_null_integer_and_unicode_values(self):
        first = snapshot(self.db_path)
        second = snapshot(self.db_path)

        self.assertEqual(first, second)
        self.assertEqual(first["quiz"]["rows"], 1)
        self.assertEqual(first["chapter"]["rows"], 1)
        self.assertEqual(first["section"]["rows"], 1)

    def test_cli_creates_a_missing_output_parent_directory(self):
        output_path = Path(self.temporary_directory.name) / "missing" / "parent" / "baseline.json"
        command = [
            sys.executable,
            str(SOURCE_ROOT / "tools/keywords/verify_protected_tables.py"),
            str(self.db_path),
            "--out",
            str(output_path),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=False)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(json.loads(output_path.read_text(encoding="utf-8"))), ["chapter", "quiz", "section"])

    def test_cli_reports_a_friendly_error_for_an_invalid_database_path(self):
        command = [
            sys.executable,
            str(SOURCE_ROOT / "tools/keywords/verify_protected_tables.py"),
            str(Path(self.temporary_directory.name) / "missing.db"),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("ERROR:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_pass_when_protected_tables_match(self):
        baseline_path = self.write_baseline(snapshot(self.db_path))

        result = self.run_cli(self.db_path, "--compare", baseline_path)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS: protected tables match", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_cli_reports_row_count_mismatch_for_the_affected_table(self):
        baseline = snapshot(self.db_path)
        baseline["quiz"]["rows"] = 2
        baseline_path = self.write_baseline(baseline)

        result = self.run_cli(self.db_path, "--compare", baseline_path)

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("FAIL: protected tables differ", result.stderr)
        self.assertIn("quiz: rows expected=2 actual=1", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_hash_mismatch_for_the_affected_table(self):
        baseline = snapshot(self.db_path)
        baseline["chapter"]["sha256"] = "0" * 64
        baseline_path = self.write_baseline(baseline)

        result = self.run_cli(self.db_path, "--compare", baseline_path)

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("chapter: sha256 expected=", result.stderr)
        self.assertIn("actual=", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_friendly_errors_for_missing_or_invalid_baselines(self):
        invalid_table = snapshot(self.db_path)
        invalid_table["section"] = {"rows": 1}
        cases = {
            "missing": Path(self.temporary_directory.name) / "missing-baseline.json",
            "invalid-json": self.write_text("invalid.json", "{"),
            "invalid-schema": self.write_text("invalid-schema.json", "{}"),
            "invalid-table-schema": self.write_text("invalid-table-schema.json", json.dumps(invalid_table)),
        }

        for case, baseline_path in cases.items():
            with self.subTest(case=case):
                result = self.run_cli(self.db_path, "--compare", baseline_path)

                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_cli_rejects_out_and_compare_together(self):
        baseline_path = self.write_baseline(snapshot(self.db_path))
        output_path = Path(self.temporary_directory.name) / "output.json"

        result = self.run_cli(self.db_path, "--out", output_path, "--compare", baseline_path)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not allowed with argument", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(output_path.exists())

    def run_cli(self, database_path, *arguments):
        return subprocess.run(
            [
                sys.executable,
                str(SOURCE_ROOT / "tools/keywords/verify_protected_tables.py"),
                str(database_path),
                *(str(argument) for argument in arguments),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def write_baseline(self, baseline):
        path = Path(self.temporary_directory.name) / "baseline.json"
        path.write_text(json.dumps(baseline), encoding="utf-8")
        return path

    def write_text(self, name, content):
        path = Path(self.temporary_directory.name) / name
        path.write_text(content, encoding="utf-8")
        return path

    def update(self, statement):
        connection = sqlite3.connect(self.db_path)
        try:
            connection.execute(statement)
            connection.commit()
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
