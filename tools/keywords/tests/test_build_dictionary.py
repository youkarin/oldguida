import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from tools.keywords.build_dictionary import build_dictionary
from tools.keywords.verify_protected_tables import snapshot


SOURCE_ROOT = Path(__file__).resolve().parents[3]
BUILD_SCRIPT = SOURCE_ROOT / "tools/keywords/build_dictionary.py"

SOURCE_ENTRIES = [
    {
        "term": "dare precedenza",
        "partOfSpeech": "固定短语",
        "translation": "让行；给予先行权",
        "note": "表示必须让其他道路使用者先通过。",
        "forms": ["dare precedenza", "dà precedenza"],
        "exampleQuestionId": 1,
    },
    {
        "term": "auto",
        "partOfSpeech": "名词",
        "translation": "汽车",
        "note": "指道路上的汽车。",
        "forms": ["auto"],
        "exampleQuestionId": 4,
    },
]

DICTIONARY_SCHEMA = """
CREATE TABLE keyword_dictionary (
  id INTEGER PRIMARY KEY,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL UNIQUE,
  part_of_speech TEXT NOT NULL,
  translation TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  frequency INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE keyword_forms (
  id INTEGER PRIMARY KEY,
  keyword_id INTEGER NOT NULL,
  form TEXT NOT NULL,
  normalized_form TEXT NOT NULL UNIQUE,
  FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
);
CREATE TABLE keyword_examples (
  id INTEGER PRIMARY KEY,
  keyword_id INTEGER NOT NULL,
  question_id INTEGER NOT NULL,
  rank INTEGER NOT NULL DEFAULT 0,
  UNIQUE(keyword_id, question_id),
  FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
);
CREATE TABLE dictionary_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
"""


class DictionaryBuildTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.db_path = root / "quiz.db"
        self.source_path = root / "dictionary.json"
        self.source_path.write_text(
            json.dumps(SOURCE_ENTRIES, ensure_ascii=False),
            encoding="utf-8",
        )
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
                INSERT INTO quiz VALUES
                    (1, 'Dare precedenza e dare precedenza.', 1, 10, '让行。', '说明一', 1),
                    (2, 'Dà precedenza oppure dare precedenza.', 1, 10, '让行。', '说明二', 2),
                    (3, 'La precedenza è importante.', 1, 10, '优先权。', '说明三', 3),
                    (4, 'AUTO2 non è auto.', 1, 10, '汽车。', '说明四', 4);
                INSERT INTO chapter VALUES (1, 10, 'Capitolo', NULL);
                INSERT INTO section VALUES (1, 10, 1, 'Sezione', 'section.png');
                """
            )
        finally:
            connection.close()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_build_replaces_only_dictionary_tables_and_sets_versions(self):
        protected_before = snapshot(self.db_path)

        result = build_dictionary(
            self.db_path,
            self.source_path,
            version=1,
            enforce_size=False,
        )

        self.assertEqual(snapshot(self.db_path), protected_before)
        self.assertEqual(result, {"entries": 2, "forms": 3, "examples": 2})
        with closing(sqlite3.connect(self.db_path)) as connection:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 4)
            self.assertEqual(
                connection.execute(
                    "SELECT value FROM dictionary_meta WHERE key = ?",
                    ("version",),
                ).fetchone()[0],
                "1",
            )

    def test_assigns_deterministic_ids_and_counts_distinct_questions(self):
        build_dictionary(self.db_path, self.source_path, version=1, enforce_size=False)

        with closing(sqlite3.connect(self.db_path)) as connection:
            dictionary_rows = connection.execute(
                "SELECT id, term, normalized_term, frequency, sort_order "
                "FROM keyword_dictionary ORDER BY id"
            ).fetchall()
            form_rows = connection.execute(
                "SELECT id, keyword_id, form, normalized_form FROM keyword_forms ORDER BY id"
            ).fetchall()
            example_rows = connection.execute(
                "SELECT id, keyword_id, question_id, rank FROM keyword_examples ORDER BY id"
            ).fetchall()

        self.assertEqual(
            dictionary_rows,
            [
                (1, "auto", "auto", 1, 1),
                (2, "dare precedenza", "dare precedenza", 2, 2),
            ],
        )
        self.assertEqual(
            form_rows,
            [
                (1, 1, "auto", "auto"),
                (2, 2, "dare precedenza", "dare precedenza"),
                (3, 2, "dà precedenza", "dà precedenza"),
            ],
        )
        self.assertEqual(example_rows, [(1, 1, 4, 0), (2, 2, 1, 0)])

    def test_creates_required_schema_indexes_and_foreign_keys(self):
        build_dictionary(self.db_path, self.source_path, version=1, enforce_size=False)

        with closing(sqlite3.connect(self.db_path)) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = ?",
                    ("table",),
                )
            }
            dictionary_columns = connection.execute(
                "PRAGMA table_info(keyword_dictionary)"
            ).fetchall()
            index_names = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = ? AND name LIKE ?",
                    ("index", "idx_keyword_%"),
                )
            }
            forms_foreign_keys = connection.execute(
                "PRAGMA foreign_key_list(keyword_forms)"
            ).fetchall()
            examples_foreign_keys = connection.execute(
                "PRAGMA foreign_key_list(keyword_examples)"
            ).fetchall()
            foreign_key_violations = connection.execute("PRAGMA foreign_key_check").fetchall()

        self.assertTrue(
            {"keyword_dictionary", "keyword_forms", "keyword_examples", "dictionary_meta"}
            <= tables
        )
        self.assertEqual(
            [(row[1], row[2], row[3], row[4], row[5]) for row in dictionary_columns],
            [
                ("id", "INTEGER", 0, None, 1),
                ("term", "TEXT", 1, None, 0),
                ("normalized_term", "TEXT", 1, None, 0),
                ("part_of_speech", "TEXT", 1, None, 0),
                ("translation", "TEXT", 1, None, 0),
                ("note", "TEXT", 1, "''", 0),
                ("frequency", "INTEGER", 1, "0", 0),
                ("sort_order", "INTEGER", 1, "0", 0),
            ],
        )
        self.assertEqual(
            index_names,
            {
                "idx_keyword_forms_keyword_id",
                "idx_keyword_examples_keyword_rank",
                "idx_keyword_examples_question_id",
            },
        )
        self.assertEqual(forms_foreign_keys[0][2:5], ("keyword_dictionary", "keyword_id", "id"))
        self.assertEqual(examples_foreign_keys[0][2:5], ("keyword_dictionary", "keyword_id", "id"))
        self.assertEqual(foreign_key_violations, [])

    def test_enables_foreign_keys_for_the_import_connection(self):
        with closing(sqlite3.connect(self.db_path)) as connection:
            connection.executescript(DICTIONARY_SCHEMA)
            connection.execute(
                """
                CREATE TRIGGER insert_orphan_form
                AFTER INSERT ON keyword_dictionary
                WHEN NEW.term = 'auto'
                BEGIN
                  INSERT INTO keyword_forms(id, keyword_id, form, normalized_form)
                  VALUES(9000, 9000, 'orfano', 'orfano');
                END
                """
            )

        with self.assertRaises(sqlite3.IntegrityError):
            build_dictionary(self.db_path, self.source_path, version=1, enforce_size=False)

        with closing(sqlite3.connect(self.db_path)) as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM keyword_dictionary").fetchone()[0], 0)
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM keyword_forms").fetchone()[0], 0)

    def test_rolls_back_every_replaced_value_when_an_insert_fails(self):
        with closing(sqlite3.connect(self.db_path)) as connection:
            connection.executescript(DICTIONARY_SCHEMA)
            connection.executescript(
                """
                INSERT INTO keyword_dictionary
                  (id, term, normalized_term, part_of_speech, translation, note, frequency, sort_order)
                VALUES (77, 'vecchio', 'vecchio', '形容词', '旧的', '旧数据。', 99, 77);
                INSERT INTO keyword_forms
                  (id, keyword_id, form, normalized_form)
                VALUES (88, 77, 'vecchio', 'vecchio');
                INSERT INTO keyword_examples
                  (id, keyword_id, question_id, rank)
                VALUES (99, 77, 3, 5);
                INSERT INTO dictionary_meta(key, value) VALUES ('version', '41');
                INSERT INTO dictionary_meta(key, value) VALUES ('custom', 'keep');
                PRAGMA user_version = 3;
                CREATE TRIGGER reject_new_form
                BEFORE INSERT ON keyword_forms
                WHEN NEW.normalized_form = 'dà precedenza'
                BEGIN
                  SELECT RAISE(FAIL, 'forced form failure');
                END;
                """
            )
        protected_before = snapshot(self.db_path)
        dictionary_before = self.dictionary_state()

        with self.assertRaisesRegex(sqlite3.IntegrityError, "forced form failure"):
            build_dictionary(self.db_path, self.source_path, version=9, enforce_size=False)

        self.assertEqual(snapshot(self.db_path), protected_before)
        self.assertEqual(self.dictionary_state(), dictionary_before)

    def test_rejects_non_positive_or_boolean_version_before_writing(self):
        for invalid_version in (0, -1, True):
            with self.subTest(version=invalid_version):
                with self.assertRaisesRegex(ValueError, "positive integer"):
                    build_dictionary(
                        self.db_path,
                        self.source_path,
                        version=invalid_version,
                        enforce_size=False,
                    )
                with closing(sqlite3.connect(self.db_path)) as connection:
                    tables = connection.execute(
                        "SELECT name FROM sqlite_master WHERE name = ?",
                        ("keyword_dictionary",),
                    ).fetchall()
                self.assertEqual(tables, [])

    def test_cli_rejects_non_positive_dictionary_version_without_traceback(self):
        result = self.run_cli(
            "--db",
            str(self.db_path),
            "--source",
            str(self.source_path),
            "--dictionary-version",
            "0",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("positive integer", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_database_source_validation_and_sqlite_errors_without_traceback(self):
        missing_db = self.run_cli(
            "--db",
            str(self.db_path.with_name("missing.db")),
            "--source",
            str(self.source_path),
            "--dictionary-version",
            "1",
        )
        missing_source = self.run_cli(
            "--db",
            str(self.db_path),
            "--source",
            str(self.source_path.with_name("missing.json")),
            "--dictionary-version",
            "1",
        )
        invalid_source_path = self.source_path.with_name("invalid.json")
        invalid_source_path.write_text("[]", encoding="utf-8")
        invalid_source = self.run_cli(
            "--db",
            str(self.db_path),
            "--source",
            str(invalid_source_path),
            "--dictionary-version",
            "1",
        )
        sqlite_db = self.db_path.with_name("no-quiz.db")
        sqlite3.connect(sqlite_db).close()
        sqlite_error = self.run_cli(
            "--db",
            str(sqlite_db),
            "--source",
            str(self.source_path),
            "--dictionary-version",
            "1",
        )

        for result in (missing_db, missing_source, invalid_source, sqlite_error):
            with self.subTest(stderr=result.stderr):
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def dictionary_state(self):
        with closing(sqlite3.connect(self.db_path)) as connection:
            return {
                "keyword_dictionary": connection.execute(
                    "SELECT * FROM keyword_dictionary ORDER BY id"
                ).fetchall(),
                "keyword_forms": connection.execute(
                    "SELECT * FROM keyword_forms ORDER BY id"
                ).fetchall(),
                "keyword_examples": connection.execute(
                    "SELECT * FROM keyword_examples ORDER BY id"
                ).fetchall(),
                "dictionary_meta": connection.execute(
                    "SELECT * FROM dictionary_meta ORDER BY key"
                ).fetchall(),
                "user_version": connection.execute("PRAGMA user_version").fetchone()[0],
            }

    def run_cli(self, *arguments):
        return subprocess.run(
            [sys.executable, str(BUILD_SCRIPT), *arguments],
            cwd=SOURCE_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
