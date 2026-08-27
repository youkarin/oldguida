import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from tools.keywords.validate_source import (
    ValidationError,
    has_italian_boundaries,
    normalize_text,
    validate_source,
)


SOURCE_ROOT = Path(__file__).resolve().parents[3]
VALIDATOR_PATH = SOURCE_ROOT / "tools/keywords/validate_source.py"

VALID_ENTRY = {
    "term": "dare precedenza",
    "partOfSpeech": "固定短语",
    "translation": "让行；给予先行权",
    "note": "表示必须让其他道路使用者先通过。",
    "forms": ["dare precedenza", "dà precedenza"],
    "exampleQuestionId": 1,
}


class SourceValidationTest(unittest.TestCase):
    def setUp(self):
        self.quiz_rows = {
            1: "Il conducente deve dare precedenza all’autovettura.",
            2: "L’AUTOVETTURA è già ferma.",
        }

    def test_accepts_valid_entries_without_mutating_them_and_sorts_stably(self):
        autovettura = {
            "term": "autovettura",
            "partOfSpeech": "名词",
            "translation": "小客车",
            "note": "指主要用于载人的普通汽车。",
            "forms": ["autovettura", "autovetture"],
            "exampleQuestionId": 2,
        }
        source = [deepcopy(VALID_ENTRY), autovettura]
        before = deepcopy(source)

        validated = validate_source(source, self.quiz_rows, enforce_size=False)

        self.assertEqual([entry["term"] for entry in validated], ["autovettura", "dare precedenza"])
        self.assertEqual(source, before)

    def test_normalizes_unicode_case_apostrophes_and_whitespace(self):
        self.assertEqual(normalize_text("  L’AUTOVETTURA\tGIÀ  "), "l'autovettura già")
        self.assertTrue(has_italian_boundaries("L’AUTOVETTURA è già ferma.", "l'autovettura"))
        self.assertTrue(has_italian_boundaries("Deve   dare\tprecedenza, ora.", "dare precedenza"))

    def test_boundaries_reject_partial_accented_and_apostrophe_words(self):
        self.assertFalse(has_italian_boundaries("Una semiautovettura.", "autovettura"))
        self.assertFalse(has_italian_boundaries("È giàx tardi.", "già"))
        self.assertFalse(has_italian_boundaries("È stragià detto.", "già"))
        self.assertFalse(has_italian_boundaries("L'autoveicolo parte.", "auto"))
        self.assertTrue(has_italian_boundaries("L'auto parte.", "auto"))

    def test_rejects_source_and_entry_container_types(self):
        with self.assertRaisesRegex(ValidationError, "source must be a list"):
            validate_source({}, self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "entry 1 must be an object"):
            validate_source(["not an entry"], self.quiz_rows, enforce_size=False)

    def test_rejects_missing_or_extra_fields(self):
        missing = deepcopy(VALID_ENTRY)
        del missing["note"]
        extra = {**VALID_ENTRY, "frequency": 10}

        with self.assertRaisesRegex(ValidationError, "invalid fields"):
            validate_source([missing], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "invalid fields"):
            validate_source([extra], self.quiz_rows, enforce_size=False)

    def test_rejects_wrong_scalar_field_types(self):
        cases = {
            "term": 1,
            "partOfSpeech": None,
            "translation": ["让行"],
            "note": {"text": "解释"},
            "exampleQuestionId": "1",
        }
        for field, value in cases.items():
            with self.subTest(field=field):
                entry = {**VALID_ENTRY, field: value}
                with self.assertRaisesRegex(ValidationError, field):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

        boolean_id = {**VALID_ENTRY, "exampleQuestionId": True}
        with self.assertRaisesRegex(ValidationError, "exampleQuestionId"):
            validate_source([boolean_id], self.quiz_rows, enforce_size=False)

    def test_rejects_invalid_forms_types_and_empty_forms(self):
        for forms in ("dare precedenza", [], ["dare precedenza", 3], ["dare precedenza", " "]):
            with self.subTest(forms=forms):
                entry = {**VALID_ENTRY, "forms": forms}
                with self.assertRaisesRegex(ValidationError, "forms"):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_forms_without_italian_letters(self):
        entry = {**VALID_ENTRY, "forms": ["dare precedenza", "123"]}

        with self.assertRaisesRegex(ValidationError, "Italian letters"):
            validate_source([entry], {1: "Deve dare precedenza al veicolo 123."}, enforce_size=False)

    def test_requires_normalized_lowercase_term_and_forms(self):
        upper_term = {**VALID_ENTRY, "term": "Dare precedenza"}
        curly_form = {**VALID_ENTRY, "forms": ["dare precedenza", "dà  precedenza"]}

        with self.assertRaisesRegex(ValidationError, "term must be normalized"):
            validate_source([upper_term], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "form must be normalized"):
            validate_source([curly_form], self.quiz_rows, enforce_size=False)

    def test_requires_nonempty_chinese_translation_and_note(self):
        cases = {
            "translation": "yield",
            "note": "driving context",
            "partOfSpeech": "noun",
        }
        for field, value in cases.items():
            with self.subTest(field=field):
                entry = {**VALID_ENTRY, field: value}
                with self.assertRaisesRegex(ValidationError, field):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

        for field in ("translation", "note", "partOfSpeech"):
            with self.subTest(blank=field):
                entry = {**VALID_ENTRY, field: "  "}
                with self.assertRaisesRegex(ValidationError, field):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_unknown_part_of_speech_and_placeholder_copy(self):
        bad_part = {**VALID_ENTRY, "partOfSpeech": "术语"}
        placeholder_translation = {**VALID_ENTRY, "translation": "相关术语"}
        placeholder_note = {**VALID_ENTRY, "note": "这是驾考中的常见相关术语。"}

        with self.assertRaisesRegex(ValidationError, "partOfSpeech"):
            validate_source([bad_part], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "placeholder"):
            validate_source([placeholder_translation], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "placeholder"):
            validate_source([placeholder_note], self.quiz_rows, enforce_size=False)

    def test_rejects_duplicate_normalized_term(self):
        other = {
            **VALID_ENTRY,
            "forms": ["dà precedenza"],
        }
        with self.assertRaisesRegex(ValidationError, "duplicate normalized term"):
            validate_source([VALID_ENTRY, other], self.quiz_rows, enforce_size=False)

    def test_rejects_duplicate_normalized_form_within_one_entry(self):
        entry = {**VALID_ENTRY, "forms": ["dare precedenza", "dare precedenza"]}
        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_duplicate_normalized_form_across_entries(self):
        other = {
            "term": "precedenza",
            "partOfSpeech": "名词",
            "translation": "优先权",
            "note": "表示道路使用者依法享有的先行权。",
            "forms": ["precedenza", "dà precedenza"],
            "exampleQuestionId": 1,
        }
        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([VALID_ENTRY, other], self.quiz_rows, enforce_size=False)

    def test_reports_normalized_duplicate_before_noncanonical_spelling(self):
        other = {
            "term": "precedenza",
            "partOfSpeech": "名词",
            "translation": "优先权",
            "note": "表示道路使用者依法享有的先行权。",
            "forms": ["Dare precedenza"],
            "exampleQuestionId": 1,
        }

        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([VALID_ENTRY, other], self.quiz_rows, enforce_size=False)

    def test_rejects_missing_canonical_form(self):
        entry = {**VALID_ENTRY, "forms": ["dà precedenza"]}
        with self.assertRaisesRegex(ValidationError, "canonical term missing from forms"):
            validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_unknown_or_nonmatching_example(self):
        unknown = {**VALID_ENTRY, "exampleQuestionId": 999}
        with self.assertRaisesRegex(ValidationError, "unknown example question"):
            validate_source([unknown], self.quiz_rows, enforce_size=False)

        with self.assertRaisesRegex(ValidationError, "example does not contain"):
            validate_source([VALID_ENTRY], {1: "Il veicolo rallenta"}, enforce_size=False)

    def test_enforces_dictionary_size_by_default(self):
        with self.assertRaisesRegex(ValidationError, "outside 500..800"):
            validate_source([], {}, enforce_size=True)
        with self.assertRaisesRegex(ValidationError, "outside 500..800"):
            validate_source([{}] * 801, {}, enforce_size=True)


class SourceValidatorCliTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.database_path = self.directory / "quiz.db"
        connection = sqlite3.connect(self.database_path)
        try:
            connection.execute("CREATE TABLE quiz (id INTEGER PRIMARY KEY, question TEXT)")
            connection.execute("INSERT INTO quiz VALUES (1, 'Deve dare precedenza.')")
            connection.commit()
        finally:
            connection.close()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_cli_reports_json_io_and_sqlite_errors_without_tracebacks(self):
        malformed_json = self.directory / "malformed.json"
        malformed_json.write_text("{", encoding="utf-8")
        invalid_database = self.directory / "invalid.db"
        invalid_database.write_bytes(b"not sqlite")
        valid_source = self.directory / "source.json"
        valid_source.write_text("[]", encoding="utf-8")

        commands = [
            ["--db", str(self.database_path), "--source", str(malformed_json)],
            ["--db", str(self.database_path), "--source", str(self.directory / "missing.json")],
            ["--db", str(invalid_database), "--source", str(valid_source)],
        ]
        for arguments in commands:
            with self.subTest(arguments=arguments):
                result = self.run_cli(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_validation_errors_without_tracebacks(self):
        source_path = self.directory / "source.json"
        source_path.write_text(json.dumps({"entries": []}), encoding="utf-8")

        result = self.run_cli("--db", str(self.database_path), "--source", str(source_path))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("ERROR:", result.stderr)
        self.assertIn("source must be a list", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def run_cli(self, *arguments):
        return subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
