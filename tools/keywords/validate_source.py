"""Validate the curated Italian driving dictionary against real quiz questions."""

import argparse
import json
import re
import sqlite3
import sys
import unicodedata
from collections.abc import Mapping
from pathlib import Path


REQUIRED_FIELDS = {
    "term",
    "partOfSpeech",
    "translation",
    "note",
    "forms",
    "exampleQuestionId",
}
ALLOWED_PARTS_OF_SPEECH = {"名词", "动词", "形容词", "副词", "固定短语"}
PLACEHOLDER_FRAGMENTS = {
    "todo",
    "placeholder",
    "待补充",
    "待翻译",
    "相关术语",
    "常见术语",
}
CHINESE_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
ITALIAN_LETTER_RE = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿ]")
APOSTROPHE_TRANSLATION = str.maketrans({"’": "'", "‘": "'", "`": "'", "´": "'"})


class ValidationError(ValueError):
    """Raised when dictionary source data violates its audited contract."""


def normalize_text(value: str) -> str:
    """Return the deterministic representation used for uniqueness and matching."""
    normalized = unicodedata.normalize("NFC", value).translate(APOSTROPHE_TRANSLATION)
    return " ".join(normalized.casefold().split())


def _is_italian_letter(value: str) -> bool:
    return bool(value and ITALIAN_LETTER_RE.fullmatch(value))


def has_italian_boundaries(text: str, form: str) -> bool:
    """Return whether a normalized form occurs as a complete Italian word or phrase."""
    normalized_text = normalize_text(text)
    normalized_form = normalize_text(form)
    if not normalized_form:
        return False

    start = normalized_text.find(normalized_form)
    while start >= 0:
        end = start + len(normalized_form)
        left_is_partial = start > 0 and _is_italian_letter(normalized_text[start - 1])
        right_is_partial = end < len(normalized_text) and _is_italian_letter(normalized_text[end])
        if not left_is_partial and not right_is_partial:
            return True
        start = normalized_text.find(normalized_form, start + 1)
    return False


def _require_string(entry: dict[str, object], field: str, entry_number: int) -> str:
    value = entry[field]
    if type(value) is not str:
        raise ValidationError(f"entry {entry_number} {field} must be a string")
    if not value.strip():
        raise ValidationError(f"entry {entry_number} {field} must not be empty")
    return value


def _require_chinese(value: str, field: str, term: str) -> None:
    if not CHINESE_RE.search(value):
        raise ValidationError(f"{field} must contain Chinese text: {term}")


def _reject_placeholders(value: str, field: str, term: str) -> None:
    normalized = normalize_text(value)
    if any(fragment in normalized for fragment in PLACEHOLDER_FRAGMENTS):
        raise ValidationError(f"placeholder {field} is forbidden: {term}")


def validate_source(
    source: object,
    quiz_rows: Mapping[int, str],
    enforce_size: bool = True,
) -> list[dict[str, object]]:
    """Validate source records and return them in normalized-term order."""
    if type(source) is not list:
        raise ValidationError("source must be a list")
    if enforce_size and not 500 <= len(source) <= 800:
        raise ValidationError(f"entry count {len(source)} is outside 500..800")
    if not isinstance(quiz_rows, Mapping):
        raise ValidationError("quiz_rows must be a mapping")

    seen_terms: set[str] = set()
    seen_forms: dict[str, str] = {}
    validated: list[dict[str, object]] = []

    for entry_number, raw_entry in enumerate(source, start=1):
        if type(raw_entry) is not dict:
            raise ValidationError(f"entry {entry_number} must be an object")
        entry = raw_entry
        if set(entry) != REQUIRED_FIELDS:
            missing = sorted(REQUIRED_FIELDS - set(entry))
            extra = sorted(set(entry) - REQUIRED_FIELDS)
            raise ValidationError(
                f"invalid fields for entry {entry_number}: missing={missing}, extra={extra}"
            )

        term = _require_string(entry, "term", entry_number)
        part_of_speech = _require_string(entry, "partOfSpeech", entry_number)
        translation = _require_string(entry, "translation", entry_number)
        note = _require_string(entry, "note", entry_number)
        normalized_term = normalize_text(term)

        if term != normalized_term:
            raise ValidationError(f"term must be normalized lowercase Italian: {term}")
        if not ITALIAN_LETTER_RE.search(term):
            raise ValidationError(f"term must contain Italian letters: {term}")
        if normalized_term in seen_terms:
            raise ValidationError(f"duplicate normalized term: {normalized_term}")
        if part_of_speech not in ALLOWED_PARTS_OF_SPEECH:
            raise ValidationError(f"invalid partOfSpeech for {term}: {part_of_speech}")
        _require_chinese(part_of_speech, "partOfSpeech", term)
        _require_chinese(translation, "translation", term)
        _require_chinese(note, "note", term)
        _reject_placeholders(translation, "translation", term)
        _reject_placeholders(note, "note", term)

        forms_value = entry["forms"]
        if type(forms_value) is not list or not forms_value:
            raise ValidationError(f"forms must be a non-empty list: {term}")
        normalized_forms: list[str] = []
        local_forms: set[str] = set()
        for form_number, form_value in enumerate(forms_value, start=1):
            if type(form_value) is not str or not form_value.strip():
                raise ValidationError(f"forms item {form_number} must be a non-empty string: {term}")
            normalized_form = normalize_text(form_value)
            if not ITALIAN_LETTER_RE.search(normalized_form):
                raise ValidationError(f"form must contain Italian letters: {form_value}")
            if normalized_form in local_forms:
                raise ValidationError(f"duplicate normalized form: {normalized_form}")
            if normalized_form in seen_forms:
                raise ValidationError(
                    f"duplicate normalized form: {normalized_form} "
                    f"({seen_forms[normalized_form]} and {term})"
                )
            if form_value != normalized_form:
                raise ValidationError(f"form must be normalized lowercase Italian: {form_value}")
            local_forms.add(normalized_form)
            normalized_forms.append(normalized_form)

        if normalized_term not in local_forms:
            raise ValidationError(f"canonical term missing from forms: {normalized_term}")

        example_id = entry["exampleQuestionId"]
        if type(example_id) is not int:
            raise ValidationError(f"entry {entry_number} exampleQuestionId must be an int")
        question = quiz_rows.get(example_id)
        if question is None:
            raise ValidationError(f"unknown example question: {example_id}")
        if type(question) is not str:
            raise ValidationError(f"question text must be a string: {example_id}")
        if not any(has_italian_boundaries(question, form) for form in normalized_forms):
            raise ValidationError(f"example does not contain a form: {normalized_term}")

        seen_terms.add(normalized_term)
        seen_forms.update({form: term for form in normalized_forms})
        validated.append(entry)

    return sorted(validated, key=lambda item: normalize_text(item["term"]))


def read_source(source_path: Path) -> object:
    return json.loads(source_path.read_text(encoding="utf-8"))


def read_quiz_rows(database_path: Path) -> dict[int, str]:
    database_uri = database_path.resolve().as_uri() + "?mode=ro"
    connection = sqlite3.connect(database_uri, uri=True)
    try:
        return dict(connection.execute("SELECT id, question FROM quiz ORDER BY id"))
    finally:
        connection.close()


def validation_summary(entries: list[dict[str, object]]) -> dict[str, int]:
    return {
        "duplicateForms": 0,
        "duplicateTerms": 0,
        "emptyDefinitions": 0,
        "entries": len(entries),
        "forms": sum(len(entry["forms"]) for entry in entries),
        "invalidExampleIds": 0,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=Path, help="path to quiz.db")
    parser.add_argument("--source", required=True, type=Path, help="curated dictionary JSON")
    args = parser.parse_args(argv)

    try:
        source = read_source(args.source)
        quiz_rows = read_quiz_rows(args.db)
        entries = validate_source(source, quiz_rows)
    except (json.JSONDecodeError, OSError, UnicodeError, sqlite3.Error, ValidationError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(json.dumps(validation_summary(entries), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
