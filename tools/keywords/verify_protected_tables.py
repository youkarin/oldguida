"""Create deterministic snapshots of quiz tables that dictionary imports must not change."""

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path


PROTECTED_QUERIES = {
    "quiz": "SELECT id, question, answer, section_id, translation, explanation, question_number FROM quiz ORDER BY id",
    "chapter": "SELECT id, chapter_id, name, image_path FROM chapter ORDER BY id",
    "section": "SELECT id, section_id, chapter_id, name, image_path FROM section ORDER BY id",
}


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database_path", type=Path)
    parser.add_argument("--out", type=Path, help="write the snapshot as UTF-8 JSON")
    args = parser.parse_args()

    serialized = json.dumps(snapshot(args.database_path), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is None:
        print(serialized, end="")
    else:
        args.out.write_text(serialized, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
