"""Validate the curated Italian driving dictionary against real quiz questions."""

import argparse
import json
import re
import sqlite3
import sys
import unicodedata
from collections import Counter
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
ALLOWED_PARTS_OF_SPEECH = {
    "名词",
    "动词",
    "形容词",
    "副词",
    "固定短语",
    "名词/形容词",
    "动词/形容词",
    "形容词/名词",
    "无人称动词",
}
PLACEHOLDER_FRAGMENTS = {
    "todo",
    "placeholder",
    "待补充",
    "待翻译",
    "相关术语",
    "常见术语",
}
CHINESE_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
ITALIAN_LETTERS = "A-Za-zÀÈÉÌÒÓÙàèéìòóù"
ITALIAN_TERM_RE = re.compile(
    rf"[{ITALIAN_LETTERS}]+(?:[ '][{ITALIAN_LETTERS}]+)*\Z"
)
ITALIAN_WORD_CHARACTER_RE = re.compile(rf"[0-9{ITALIAN_LETTERS}]")
ITALIAN_TOKEN_RE = re.compile(rf"[{ITALIAN_LETTERS}]+")
APOSTROPHE_TRANSLATION = str.maketrans({"’": "'", "‘": "'", "`": "'", "´": "'"})
ALLOWED_SHORT_FORMS = frozenset({"kw"})
FUNCTION_TOKENS = frozenset(
    {
        "a",
        "ai",
        "al",
        "alla",
        "alle",
        "allo",
        "con",
        "da",
        "dai",
        "dal",
        "dalla",
        "dalle",
        "dallo",
        "de",
        "dei",
        "del",
        "della",
        "delle",
        "dello",
        "di",
        "e",
        "ed",
        "gli",
        "i",
        "il",
        "in",
        "la",
        "le",
        "lo",
        "non",
        "per",
        "su",
        "sui",
        "sul",
        "sulla",
        "sulle",
        "sullo",
        "un",
        "una",
        "uno",
    }
)
SIMPLE_INFLECTION_SUFFIXES = frozenset({"a", "e", "i", "o"})
ORTHOGRAPHIC_INFLECTION_PAIRS = frozenset(
    {
        frozenset({"a", "he"}),
        frozenset({"a", "hi"}),
        frozenset({"o", "he"}),
        frozenset({"o", "hi"}),
        frozenset({"ia", "e"}),
        frozenset({"io", "i"}),
    }
)
SHORT_INFLECTION_PAIRS = frozenset(
    {
        frozenset({"area", "aree"}),
        frozenset({"fine", "fini"}),
        frozenset({"luce", "luci"}),
        frozenset({"olio", "olii"}),
        frozenset({"urto", "urti"}),
        frozenset({"zona", "zone"}),
    }
)
IRREGULAR_FORMS = {
    "consentire": frozenset({"consente", "consentono"}),
    "dovere": frozenset({"deve", "devono"}),
    "imporre": frozenset({"impone"}),
    "indicare": frozenset({"indica", "indicano"}),
    "potere": frozenset({"può", "possono"}),
    "segnalare": frozenset({"segnala"}),
    "transitare": frozenset({"transiti"}),
    "vietare": frozenset({"vieta"}),
    "non può": frozenset({"non possono"}),
}


class ValidationError(ValueError):
    """Raised when dictionary source data violates its audited contract."""


def normalize_text(value: str) -> str:
    """Return the deterministic representation used for uniqueness and matching."""
    normalized = unicodedata.normalize("NFC", value).translate(APOSTROPHE_TRANSLATION)
    return " ".join(normalized.casefold().split())


def normalize_surface(value: str) -> str:
    """Normalize source typography while preserving intentional display case."""
    normalized = unicodedata.normalize("NFC", value).translate(APOSTROPHE_TRANSLATION)
    return " ".join(normalized.split())


def _is_word_character(value: str) -> bool:
    return bool(value and ITALIAN_WORD_CHARACTER_RE.fullmatch(value))


def has_italian_boundaries(text: str, form: str) -> bool:
    """Return whether a normalized form occurs as a complete Italian word or phrase."""
    normalized_text = normalize_text(text)
    normalized_form = normalize_text(form)
    if not normalized_form:
        return False

    start = normalized_text.find(normalized_form)
    while start >= 0:
        end = start + len(normalized_form)
        left_is_partial = start > 0 and _is_word_character(normalized_text[start - 1])
        right_is_partial = end < len(normalized_text) and _is_word_character(normalized_text[end])
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


def _validate_italian_surface(value: str, field: str) -> None:
    normalized = normalize_text(value)
    if value != normalize_surface(value):
        raise ValidationError(f"{field} must be normalized Italian: {value}")
    if not ITALIAN_TERM_RE.fullmatch(value):
        raise ValidationError(f"invalid Italian term grammar for {field}: {value}")
    compact_length = sum(len(token) for token in ITALIAN_TOKEN_RE.findall(value))
    if compact_length < 3 and normalized not in ALLOWED_SHORT_FORMS:
        raise ValidationError(f"invalid Italian term grammar for {field}: {value}")


def _tokens(value: str) -> list[str]:
    return ITALIAN_TOKEN_RE.findall(normalize_text(value))


def _has_inflectional_overlap(left: str, right: str) -> bool:
    if left == right:
        return left not in FUNCTION_TOKENS and len(left) >= 3
    if frozenset({left, right}) in SHORT_INFLECTION_PAIRS:
        return True
    for stem_length in range(min(len(left), len(right)) - 1, 3, -1):
        if left[:stem_length] != right[:stem_length]:
            continue
        left_suffix = left[stem_length:]
        right_suffix = right[stem_length:]
        suffix_pair = frozenset({left_suffix, right_suffix})
        if (
            left_suffix in SIMPLE_INFLECTION_SUFFIXES
            and right_suffix in SIMPLE_INFLECTION_SUFFIXES
        ):
            return True
        if suffix_pair == frozenset({"io", "i"}):
            return True
        if (
            suffix_pair in ORTHOGRAPHIC_INFLECTION_PAIRS
            and left[:stem_length].endswith(("c", "g"))
        ):
            return True
    return False


def forms_are_related(term: str, form: str) -> bool:
    """Conservatively accept inflectional, phrase, and audited irregular variants."""
    normalized_term = normalize_text(term)
    normalized_form = normalize_text(form)
    if normalized_term == normalized_form:
        return True
    if normalized_form in IRREGULAR_FORMS.get(normalized_term, frozenset()):
        return True
    return any(
        _has_inflectional_overlap(term_token, form_token)
        for term_token in _tokens(normalized_term)
        for form_token in _tokens(normalized_form)
    )


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

        if normalized_term in seen_terms:
            raise ValidationError(f"duplicate normalized term: {normalized_term}")
        _validate_italian_surface(term, "term")
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
                raise ValidationError(
                    f"forms item {form_number} must be a non-empty string: {term}"
                )
            normalized_form = normalize_text(form_value)
            if normalized_form in local_forms:
                raise ValidationError(f"duplicate normalized form: {normalized_form}")
            if normalized_form in seen_forms:
                raise ValidationError(
                    f"duplicate normalized form: {normalized_form} "
                    f"({seen_forms[normalized_form]} and {term})"
                )
            _validate_italian_surface(form_value, "form")
            local_forms.add(normalized_form)
            normalized_forms.append(normalized_form)

        if normalized_term not in local_forms:
            raise ValidationError(f"canonical term missing from forms: {normalized_term}")
        for form_value in forms_value:
            if not forms_are_related(term, form_value):
                raise ValidationError(f"unrelated form for {term}: {form_value}")

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


def validation_summary(
    entries: list[dict[str, object]],
    quiz_rows: Mapping[int, str],
) -> dict[str, int]:
    terms = [
        normalize_text(entry["term"])
        for entry in entries
        if type(entry.get("term")) is str and entry["term"].strip()
    ]
    forms = [
        normalize_text(form)
        for entry in entries
        if type(entry.get("forms")) is list
        for form in entry["forms"]
        if type(form) is str and form.strip()
    ]
    empty_definitions = sum(
        any(
            type(entry.get(field)) is not str or not entry[field].strip()
            for field in ("translation", "note")
        )
        for entry in entries
    )
    invalid_example_ids = sum(
        type(entry.get("exampleQuestionId")) is not int
        or entry["exampleQuestionId"] not in quiz_rows
        for entry in entries
    )
    return {
        "duplicateForms": sum(count - 1 for count in Counter(forms).values() if count > 1),
        "duplicateTerms": sum(count - 1 for count in Counter(terms).values() if count > 1),
        "emptyDefinitions": empty_definitions,
        "entries": len(entries),
        "forms": len(forms),
        "invalidExampleIds": invalid_example_ids,
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

    print(json.dumps(validation_summary(entries, quiz_rows), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
