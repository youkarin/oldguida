"""Extract deterministic Italian word and bigram candidates from quiz questions."""

import argparse
import json
import re
import sqlite3
import sys
from collections import Counter
from collections.abc import Iterable
from pathlib import Path


TOKEN_RE = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)?")
STOPWORDS = {
    "a",
    "ad",
    "al",
    "alla",
    "che",
    "con",
    "da",
    "dal",
    "di",
    "e",
    "il",
    "in",
    "la",
    "le",
    "lo",
    "o",
    "per",
    "si",
    "un",
    "una",
}
ELIDED_STOPWORD_PREFIXES = {
    "all",
    "dall",
    "dell",
    "l",
    "nell",
    "sull",
    "un",
}


def normalize(value: str) -> str:
    """Normalize case and apostrophe variants for deterministic matching."""
    return value.lower().replace("’", "'")


def normalize_token(value: str) -> str:
    """Discard Italian elided articles before counting their lexical word."""
    token = normalize(value)
    prefix, separator, remainder = token.partition("'")
    if separator and prefix in ELIDED_STOPWORD_PREFIXES:
        return remainder
    return token


def pack(counts: Counter[str]) -> list[dict[str, object]]:
    """Serialize frequencies in the stable ordering consumed by curation tools."""
    return [
        {"term": term, "frequency": frequency}
        for term, frequency in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]


def extract_candidates(questions: Iterable[str]) -> dict[str, list[dict[str, object]]]:
    """Return non-stopword words and useful adjacent bigrams from Italian text."""
    words: Counter[str] = Counter()
    phrases: Counter[str] = Counter()

    for question in questions:
        tokens = [normalize_token(token) for token in TOKEN_RE.findall(question)]
        words.update(token for token in tokens if token not in STOPWORDS)
        phrases.update(
            " ".join(pair)
            for pair in zip(tokens, tokens[1:])
            if pair[0] not in STOPWORDS or pair[1] not in STOPWORDS
        )

    return {"words": pack(words), "phrases": pack(phrases)}


def read_questions(database_path: Path) -> list[str]:
    """Load quiz text through a read-only SQLite connection."""
    database_uri = database_path.resolve().as_uri() + "?mode=ro"
    connection = sqlite3.connect(database_uri, uri=True)
    try:
        return [row[0] or "" for row in connection.execute("SELECT question FROM quiz ORDER BY id")]
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=Path, help="path to quiz.db")
    parser.add_argument("--out", required=True, type=Path, help="destination candidates JSON")
    args = parser.parse_args()

    try:
        questions = read_questions(args.db)
        payload = {"questions": len(questions), **extract_candidates(questions)}
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (OSError, sqlite3.Error) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
