import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path


REVIEW_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REVIEW_DIR))

from validate_chapter import ValidationError, validate_chapter


class ValidateChapterTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.db_path = self.root / "quiz.db"
        self.manifest_path = self.root / "images.json"

        with closing(sqlite3.connect(self.db_path)) as connection:
            connection.executescript(
                """
                CREATE TABLE section (
                    section_id INTEGER PRIMARY KEY,
                    chapter_id INTEGER NOT NULL,
                    image_path TEXT
                );
                CREATE TABLE quiz (
                    id INTEGER PRIMARY KEY,
                    section_id INTEGER NOT NULL
                );
                INSERT INTO section (section_id, chapter_id, image_path) VALUES
                    (1, 1, NULL),
                    (2, 1, 'assets/images/section-2.png'),
                    (9, 2, 'assets/images/section-9.png');
                INSERT INTO quiz (id, section_id) VALUES
                    (1, 1),
                    (2, 1),
                    (3, 2),
                    (99, 9);
                """
            )
            connection.commit()

        self.write_json(
            self.manifest_path,
            {"chapter": 1, "section_ids": [2], "question_ids": [3]},
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    def write_json(self, path, value):
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def write_patch(self, name="patch-a.json", value=None):
        if value is None:
            value = {
                "slice": "1-3",
                "reviewed": 3,
                "items": [
                    {"id": 1, "translation": "Traduzione corretta"},
                    {"id": 3, "explanation": "Spiegazione corretta", "note": "checked"},
                ],
                "severe": [{"id": 2, "type": "source", "detail": "Needs review"}],
            }
        return self.write_json(self.root / name, value)

    def validate(self, patches=None, manifest_path=None, expect_reviewed=3):
        if patches is None:
            self.write_patch()
            patches = [str(self.root / "patch-*.json")]
        return validate_chapter(
            db_path=self.db_path,
            chapter=1,
            patch_patterns=patches,
            image_manifest_path=manifest_path or self.manifest_path,
            expect_reviewed=expect_reviewed,
        )

    def test_complete_valid_review_returns_summary(self):
        self.assertEqual(
            self.validate(),
            {
                "chapter": 1,
                "reviewed": 3,
                "items": 2,
                "severe": 1,
                "image_sections": 1,
                "image_questions": 1,
            },
        )

    def test_rejects_protected_item_field(self):
        patch = {
            "reviewed": 3,
            "items": [{"id": 1, "translation": "Valid", "answer": 1}],
            "severe": [],
        }
        self.write_patch(value=patch)

        with self.assertRaisesRegex(ValidationError, "answer"):
            self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_incomplete_image_question_ids(self):
        self.write_json(
            self.manifest_path,
            {"chapter": 1, "section_ids": [2], "question_ids": []},
        )

        with self.assertRaisesRegex(ValidationError, "question_ids"):
            self.validate()

    def test_rejects_duplicate_item_id_across_patches(self):
        self.write_patch(
            "patch-a.json",
            {"reviewed": 1, "items": [{"id": 1, "translation": "One"}], "severe": []},
        )
        self.write_patch(
            "patch-b.json",
            {"reviewed": 2, "items": [{"id": 1, "explanation": "Two"}], "severe": []},
        )

        with self.assertRaisesRegex(ValidationError, "duplicate item id 1"):
            self.validate(patches=[str(self.root / "patch-*.json")])

    def test_rejects_empty_translation(self):
        self.write_patch(
            value={
                "reviewed": 3,
                "items": [{"id": 1, "translation": "  "}],
                "severe": [],
            }
        )

        with self.assertRaisesRegex(ValidationError, "translation"):
            self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_empty_explanation(self):
        self.write_patch(
            value={
                "reviewed": 3,
                "items": [{"id": 1, "explanation": ""}],
                "severe": [],
            }
        )

        with self.assertRaisesRegex(ValidationError, "explanation"):
            self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_item_without_editable_value(self):
        self.write_patch(
            value={"reviewed": 3, "items": [{"id": 1, "note": "No edit"}], "severe": []}
        )

        with self.assertRaisesRegex(ValidationError, "translation or explanation"):
            self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_item_and_severe_ids_outside_chapter(self):
        cases = (
            {
                "reviewed": 3,
                "items": [{"id": 99, "translation": "Wrong chapter"}],
                "severe": [],
            },
            {
                "reviewed": 3,
                "items": [],
                "severe": [{"id": 99, "type": "source", "detail": "Wrong chapter"}],
            },
        )
        for index, patch in enumerate(cases):
            with self.subTest(index=index):
                self.write_patch(value=patch)
                with self.assertRaisesRegex(ValidationError, "chapter 1"):
                    self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_invalid_reviewed_counts(self):
        cases = (-1, True, 2)
        for reviewed in cases:
            with self.subTest(reviewed=reviewed):
                self.write_patch(value={"reviewed": reviewed, "items": [], "severe": []})
                with self.assertRaisesRegex(ValidationError, "reviewed"):
                    self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_database_question_count_mismatch(self):
        self.write_patch(value={"reviewed": 4, "items": [], "severe": []})

        with self.assertRaisesRegex(ValidationError, "database chapter 1 has 3 questions"):
            self.validate(
                patches=[str(self.root / "patch-a.json")],
                expect_reviewed=4,
            )

    def test_rejects_unknown_patch_and_severe_fields(self):
        cases = (
            ({"reviewed": 3, "items": [], "severe": [], "chapter": 1}, "chapter"),
            (
                {
                    "reviewed": 3,
                    "items": [],
                    "severe": [
                        {"id": 1, "type": "source", "detail": "Issue", "answer": 0}
                    ],
                },
                "answer",
            ),
        )
        for index, (patch, field) in enumerate(cases):
            with self.subTest(index=index):
                self.write_patch(value=patch)
                with self.assertRaisesRegex(ValidationError, field):
                    self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_missing_severe_type_or_detail(self):
        cases = (
            {"id": 1, "detail": "Issue"},
            {"id": 1, "type": "source"},
            {"id": 1, "type": " ", "detail": "Issue"},
            {"id": 1, "type": "source", "detail": " "},
        )
        for index, severe in enumerate(cases):
            with self.subTest(index=index):
                self.write_patch(
                    value={"reviewed": 3, "items": [], "severe": [severe]}
                )
                with self.assertRaisesRegex(ValidationError, "type|detail"):
                    self.validate(patches=[str(self.root / "patch-a.json")])

    def test_rejects_duplicate_image_manifest_ids(self):
        cases = (
            {"chapter": 1, "section_ids": [2, 2], "question_ids": [3]},
            {"chapter": 1, "section_ids": [2], "question_ids": [3, 3]},
        )
        for index, manifest in enumerate(cases):
            with self.subTest(index=index):
                self.write_json(self.manifest_path, manifest)
                with self.assertRaisesRegex(ValidationError, "duplicate"):
                    self.validate()

    def test_rejects_wrong_manifest_chapter(self):
        self.write_json(
            self.manifest_path,
            {"chapter": 2, "section_ids": [2], "question_ids": [3]},
        )

        with self.assertRaisesRegex(ValidationError, "manifest chapter"):
            self.validate()

    def test_cli_emits_single_line_json_on_success(self):
        self.write_patch()
        result = subprocess.run(
            [
                sys.executable,
                str(REVIEW_DIR / "validate_chapter.py"),
                "--db",
                str(self.db_path),
                "--chapter",
                "1",
                "--patches",
                str(self.root / "patch-*.json"),
                "--image-manifest",
                str(self.manifest_path),
                "--expect-reviewed",
                "3",
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)
        self.assertEqual(json.loads(result.stdout), self.validate())

    def test_cli_reports_validation_failure(self):
        self.write_patch(
            value={
                "reviewed": 3,
                "items": [{"id": 1, "translation": "Valid", "answer": 1}],
                "severe": [],
            }
        )
        result = subprocess.run(
            [
                sys.executable,
                str(REVIEW_DIR / "validate_chapter.py"),
                "--db",
                str(self.db_path),
                "--chapter",
                "1",
                "--patches",
                str(self.root / "patch-a.json"),
                "--image-manifest",
                str(self.manifest_path),
                "--expect-reviewed",
                "3",
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("validation failed: ", result.stderr)
        self.assertIn("answer", result.stderr)


if __name__ == "__main__":
    unittest.main()
