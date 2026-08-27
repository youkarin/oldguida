"""Create deterministic snapshots of quiz tables that dictionary imports must not change."""

import argparse
import hashlib
import json
import sqlite3
import sys
from pathlib import Path


PROTECTED_QUERIES = {
    "quiz": "SELECT id, question, answer, section_id, translation, explanation, question_number FROM quiz ORDER BY id",
    "chapter": "SELECT id, chapter_id, name, image_path FROM chapter ORDER BY id",
    "section": "SELECT id, section_id, chapter_id, name, image_path FROM section ORDER BY id",
}


def load_baseline(baseline_path: Path) -> dict[str, object]:
    """Read and validate a snapshot produced by this module."""
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid baseline JSON: {error.msg}") from error

    expected_tables = set(PROTECTED_QUERIES)
    if not isinstance(baseline, dict) or set(baseline) != expected_tables:
        raise ValueError(f"baseline tables must be exactly: {', '.join(sorted(expected_tables))}")

    for table in PROTECTED_QUERIES:
        value = baseline[table]
        if not isinstance(value, dict) or set(value) != {"rows", "sha256"}:
            raise ValueError(f"baseline {table} must contain only rows and sha256")
        rows = value["rows"]
        sha256 = value["sha256"]
        if isinstance(rows, bool) or not isinstance(rows, int) or rows < 0:
            raise ValueError(f"baseline {table}.rows must be a non-negative integer")
        if not isinstance(sha256, str) or len(sha256) != 64 or any(character not in "0123456789abcdef" for character in sha256):
            raise ValueError(f"baseline {table}.sha256 must be a lowercase SHA-256 digest")
    return baseline


def snapshot(database_path: Path) -> dict[str, object]:
    """Return row counts and content hashes for tables that imports must preserve."""
    result: dict[str, object] = {}
    database_uri = database_path.resolve().as_uri() + "?mode=ro"
    connection = sqlite3.connect(database_uri, uri=True)
    try:
        for table, query in PROTECTED_QUERIES.items():
            rows = connection.execute(query).fetchall()
            payload = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
            result[table] = {
                "rows": len(rows),
                "sha256": hashlib.sha256(payload.encode("utf-8")).hexdigest(),
            }
    finally:
        connection.close()
    return result


def differences(expected: dict[str, object], actual: dict[str, object]) -> list[str]:
    """Describe protected-table fields that do not match the expected snapshot."""
    result = []
    for table in PROTECTED_QUERIES:
        expected_table = expected[table]
        actual_table = actual[table]
        for field in ("rows", "sha256"):
            if expected_table[field] != actual_table[field]:
                result.append(f"{table}: {field} expected={expected_table[field]} actual={actual_table[field]}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database_path", type=Path)
    output_mode = parser.add_mutually_exclusive_group()
    output_mode.add_argument("--out", type=Path, help="write the snapshot as UTF-8 JSON")
    output_mode.add_argument("--compare", type=Path, help="compare the snapshot with a UTF-8 JSON baseline")
    args = parser.parse_args()

    try:
        if args.compare is not None:
            expected = load_baseline(args.compare)
            actual = snapshot(args.database_path)
            mismatches = differences(expected, actual)
            if mismatches:
                print("FAIL: protected tables differ", *mismatches, sep="\n", file=sys.stderr)
                return 1
            print("PASS: protected tables match baseline")
            return 0

        serialized = json.dumps(snapshot(args.database_path), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        if args.out is not None:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(serialized, encoding="utf-8")
        else:
            print(serialized, end="")
    except (OSError, sqlite3.Error) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
