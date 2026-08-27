"""Build the validated offline dictionary inside the bundled quiz database."""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.keywords.validate_source import (
    ValidationError,
    has_italian_boundaries,
    normalize_text,
    read_source,
    validate_source,
)


SCHEMA_STATEMENTS = (
    """
    CREATE TABLE IF NOT EXISTS keyword_dictionary (
      id INTEGER PRIMARY KEY,
      term TEXT NOT NULL,
      normalized_term TEXT NOT NULL UNIQUE,
      part_of_speech TEXT NOT NULL,
      translation TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      frequency INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS keyword_forms (
      id INTEGER PRIMARY KEY,
      keyword_id INTEGER NOT NULL,
      form TEXT NOT NULL,
      normalized_form TEXT NOT NULL UNIQUE,
      FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS keyword_examples (
      id INTEGER PRIMARY KEY,
      keyword_id INTEGER NOT NULL,
      question_id INTEGER NOT NULL,
      rank INTEGER NOT NULL DEFAULT 0,
      UNIQUE(keyword_id, question_id),
      FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS dictionary_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_keyword_forms_keyword_id ON keyword_forms(keyword_id)",
    "CREATE INDEX IF NOT EXISTS idx_keyword_examples_keyword_rank ON keyword_examples(keyword_id, rank)",
    "CREATE INDEX IF NOT EXISTS idx_keyword_examples_question_id ON keyword_examples(question_id)",
)


def _require_positive_integer(value: object) -> int:
    if type(value) is not int or value <= 0:
        raise ValueError("dictionary version must be a positive integer")
    return value


def _arg_positive_integer(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def _prepare_rows(entries, questions):
    dictionary_rows = []
    form_rows = []
    example_rows = []
    next_form_id = 1

    for keyword_id, entry in enumerate(entries, start=1):
        normalized_forms = [normalize_text(value) for value in entry["forms"]]
        frequency = sum(
            1
            for question in questions.values()
            if any(has_italian_boundaries(question, form) for form in normalized_forms)
        )
        dictionary_rows.append(
            (
                keyword_id,
                entry["term"],
                normalize_text(entry["term"]),
                entry["partOfSpeech"],
                entry["translation"],
                entry["note"],
                frequency,
                keyword_id,
            )
        )
        for form, normalized_form in zip(entry["forms"], normalized_forms):
            form_rows.append((next_form_id, keyword_id, form, normalized_form))
            next_form_id += 1
        example_rows.append((keyword_id, keyword_id, entry["exampleQuestionId"], 0))

    return dictionary_rows, form_rows, example_rows


def _ensure_schema(connection: sqlite3.Connection) -> None:
    for statement in SCHEMA_STATEMENTS:
        connection.execute(statement)


def build_dictionary(
    db_path: Path,
    source_path: Path,
    version: int,
    enforce_size: bool = True,
) -> dict[str, int]:
    """Validate and atomically replace only the dictionary-owned data."""
    dictionary_version = _require_positive_integer(version)
    database_path = Path(db_path)
    source_file = Path(source_path)
    if not database_path.is_file():
        raise FileNotFoundError(f"database not found: {database_path}")

    source = read_source(source_file)
    connection = sqlite3.connect(database_path, isolation_level=None)
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        if connection.execute("PRAGMA foreign_keys").fetchone()[0] != 1:
            raise RuntimeError("could not enable SQLite foreign keys")

        questions = dict(connection.execute("SELECT id, question FROM quiz ORDER BY id"))
        entries = validate_source(source, questions, enforce_size=enforce_size)
        dictionary_rows, form_rows, example_rows = _prepare_rows(entries, questions)

        _ensure_schema(connection)
        connection.execute("BEGIN IMMEDIATE")
        try:
            connection.execute("DELETE FROM keyword_examples")
            connection.execute("DELETE FROM keyword_forms")
            connection.execute("DELETE FROM keyword_dictionary")
            connection.execute("DELETE FROM dictionary_meta")
            connection.executemany(
                """
                INSERT INTO keyword_dictionary (
                  id, term, normalized_term, part_of_speech,
                  translation, note, frequency, sort_order
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                dictionary_rows,
            )
            connection.executemany(
                """
                INSERT INTO keyword_forms (
                  id, keyword_id, form, normalized_form
                ) VALUES (?, ?, ?, ?)
                """,
                form_rows,
            )
            connection.executemany(
                """
                INSERT INTO keyword_examples (
                  id, keyword_id, question_id, rank
                ) VALUES (?, ?, ?, ?)
                """,
                example_rows,
            )
            connection.execute(
                "INSERT INTO dictionary_meta(key, value) VALUES (?, ?)",
                ("version", str(dictionary_version)),
            )
            connection.execute("PRAGMA user_version = 4")
            violations = connection.execute("PRAGMA foreign_key_check").fetchall()
            if violations:
                raise sqlite3.IntegrityError(
                    f"foreign key check failed with {len(violations)} violation(s)"
                )
            connection.execute("COMMIT")
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise
    finally:
        connection.close()

    return {
        "entries": len(dictionary_rows),
        "forms": len(form_rows),
        "examples": len(example_rows),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=Path, help="path to quiz.db")
    parser.add_argument("--source", required=True, type=Path, help="curated dictionary JSON")
    parser.add_argument(
        "--dictionary-version",
        required=True,
        type=_arg_positive_integer,
        help="positive dictionary data version",
    )
    args = parser.parse_args(argv)

    try:
        result = build_dictionary(
            args.db,
            args.source,
            version=args.dictionary_version,
        )
    except (
        json.JSONDecodeError,
        OSError,
        UnicodeError,
        sqlite3.Error,
        ValidationError,
        RuntimeError,
        ValueError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
