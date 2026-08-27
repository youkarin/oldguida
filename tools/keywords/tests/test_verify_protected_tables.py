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
                INSERT INTO quiz VALUES (1, 'Domanda originale', 1, 10, '翻译', '说明', 100);
                INSERT INTO chapter VALUES (1, 10, 'Capitolo', 'chapter.png');
                INSERT INTO section VALUES (1, 10, 1, 'Sezione', 'section.png');
                """
            )
        finally:
            connection.close()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_snapshot_changes_when_a_question_changes(self):
        before = snapshot(self.db_path)

        connection = sqlite3.connect(self.db_path)
        try:
            connection.execute("UPDATE quiz SET question = 'changed' WHERE id = 1")
            connection.commit()
        finally:
            connection.close()

        after = snapshot(self.db_path)

        self.assertEqual(set(before), {"quiz", "chapter", "section"})
        self.assertEqual(before["quiz"]["rows"], after["quiz"]["rows"])
        self.assertNotEqual(before["quiz"]["sha256"], after["quiz"]["sha256"])
        self.assertEqual(before["chapter"], after["chapter"])
        self.assertEqual(before["section"], after["section"])

    def test_cli_writes_sorted_utf8_json(self):
        output_path = Path(self.temporary_directory.name) / "baseline.json"
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


if __name__ == "__main__":
    unittest.main()
