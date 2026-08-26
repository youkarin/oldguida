import argparse
import glob
import json
import sqlite3
import sys
from pathlib import Path


PATCH_FIELDS = frozenset(("slice", "reviewed", "items", "severe"))
ITEM_FIELDS = frozenset(("id", "translation", "explanation", "note"))
SEVERE_FIELDS = frozenset(("id", "type", "detail"))


class ValidationError(Exception):
    pass


def _load_json(path, label):
    try:
        with Path(path).open(encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError("cannot read %s %s: %s" % (label, path, exc)) from exc


def _expand_patch_patterns(patterns):
    files = []
    seen = set()
    for pattern in patterns:
        matches = sorted(Path(match) for match in glob.glob(str(pattern)))
        matches = [path for path in matches if path.is_file()]
        if not matches:
            raise ValidationError("patch pattern matched no files: %s" % pattern)
        for path in matches:
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                files.append(resolved)
    if not files:
        raise ValidationError("no patch files matched")
    return files


def _require_object(value, label):
    if not isinstance(value, dict):
        raise ValidationError("%s must be a JSON object" % label)
    return value


def _reject_unknown_fields(value, allowed, label):
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise ValidationError("%s contains unsupported field(s): %s" % (label, ", ".join(unknown)))


def _require_integer(value, label):
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError("%s must be an integer" % label)
    return value


def _require_nonempty_text(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValidationError("%s must be a non-empty string" % label)
    return value


def _load_chapter_data(db_path, chapter):
    path = Path(db_path).resolve()
    if not path.is_file():
        raise ValidationError("database does not exist: %s" % path)

    connection = None
    try:
        connection = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
        question_ids = {
            row[0]
            for row in connection.execute(
                "SELECT q.id FROM quiz AS q "
                "JOIN section AS s ON s.section_id = q.section_id "
                "WHERE s.chapter_id = ?",
                (chapter,),
            )
        }
        image_section_ids = {
            row[0]
            for row in connection.execute(
                "SELECT s.section_id FROM section AS s "
                "WHERE s.chapter_id = ? "
                "AND COALESCE(TRIM(s.image_path), '') <> ''",
                (chapter,),
            )
        }
        image_question_ids = {
            row[0]
            for row in connection.execute(
                "SELECT q.id FROM quiz AS q "
                "JOIN section AS s ON s.section_id = q.section_id "
                "WHERE s.chapter_id = ? "
                "AND COALESCE(TRIM(s.image_path), '') <> ''",
                (chapter,),
            )
        }
    except sqlite3.Error as exc:
        raise ValidationError("cannot query database %s: %s" % (path, exc)) from exc
    finally:
        if connection is not None:
            connection.close()

    return question_ids, image_section_ids, image_question_ids


def _validate_patches(patch_files, chapter, chapter_question_ids, expect_reviewed):
    reviewed_total = 0
    item_total = 0
    severe_total = 0
    seen_item_ids = set()

    for patch_path in patch_files:
        patch_label = "patch %s" % patch_path
        patch = _require_object(_load_json(patch_path, "patch"), patch_label)
        _reject_unknown_fields(patch, PATCH_FIELDS, patch_label)

        if "reviewed" not in patch:
            raise ValidationError("%s is missing reviewed" % patch_label)
        reviewed = _require_integer(patch["reviewed"], "%s reviewed" % patch_label)
        if reviewed < 0:
            raise ValidationError("%s reviewed must be non-negative" % patch_label)
        reviewed_total += reviewed

        items = patch.get("items", [])
        if not isinstance(items, list):
            raise ValidationError("%s items must be an array" % patch_label)
        for index, raw_item in enumerate(items):
            item_label = "%s item %d" % (patch_label, index)
            item = _require_object(raw_item, item_label)
            _reject_unknown_fields(item, ITEM_FIELDS, item_label)
            if "id" not in item:
                raise ValidationError("%s is missing id" % item_label)
            item_id = _require_integer(item["id"], "%s id" % item_label)
            if item_id not in chapter_question_ids:
                raise ValidationError("%s id %s does not belong to chapter %s" % (item_label, item_id, chapter))
            if item_id in seen_item_ids:
                raise ValidationError("duplicate item id %s" % item_id)
            seen_item_ids.add(item_id)

            edited_fields = [field for field in ("translation", "explanation") if field in item]
            if not edited_fields:
                raise ValidationError("%s must include translation or explanation" % item_label)
            for field in edited_fields:
                _require_nonempty_text(item[field], "%s %s" % (item_label, field))
            item_total += 1

        severe_entries = patch.get("severe", [])
        if not isinstance(severe_entries, list):
            raise ValidationError("%s severe must be an array" % patch_label)
        for index, raw_severe in enumerate(severe_entries):
            severe_label = "%s severe %d" % (patch_label, index)
            severe = _require_object(raw_severe, severe_label)
            _reject_unknown_fields(severe, SEVERE_FIELDS, severe_label)
            if "id" not in severe:
                raise ValidationError("%s is missing id" % severe_label)
            severe_id = _require_integer(severe["id"], "%s id" % severe_label)
            if severe_id not in chapter_question_ids:
                raise ValidationError(
                    "%s id %s does not belong to chapter %s" % (severe_label, severe_id, chapter)
                )
            for field in ("type", "detail"):
                if field not in severe:
                    raise ValidationError("%s is missing %s" % (severe_label, field))
                _require_nonempty_text(severe[field], "%s %s" % (severe_label, field))
            severe_total += 1

    if reviewed_total != expect_reviewed:
        raise ValidationError(
            "patch reviewed total is %s, expected %s" % (reviewed_total, expect_reviewed)
        )
    return reviewed_total, item_total, severe_total


def _manifest_id_set(manifest, field):
    if field not in manifest:
        raise ValidationError("image manifest is missing %s" % field)
    values = manifest[field]
    if not isinstance(values, list):
        raise ValidationError("image manifest %s must be an array" % field)
    result = set()
    for index, value in enumerate(values):
        item_id = _require_integer(value, "image manifest %s[%d]" % (field, index))
        if item_id in result:
            raise ValidationError("image manifest %s contains duplicate id %s" % (field, item_id))
        result.add(item_id)
    return result


def _format_set_difference(actual, expected):
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    return "missing=%s, extra=%s" % (missing, extra)


def _validate_image_manifest(path, chapter, expected_sections, expected_questions):
    manifest = _require_object(_load_json(path, "image manifest"), "image manifest")
    if "chapter" not in manifest:
        raise ValidationError("image manifest is missing chapter")
    manifest_chapter = _require_integer(manifest["chapter"], "image manifest chapter")
    if manifest_chapter != chapter:
        raise ValidationError(
            "image manifest chapter is %s, expected %s" % (manifest_chapter, chapter)
        )

    section_ids = _manifest_id_set(manifest, "section_ids")
    question_ids = _manifest_id_set(manifest, "question_ids")
    if section_ids != expected_sections:
        raise ValidationError(
            "image manifest section_ids do not match database: %s"
            % _format_set_difference(section_ids, expected_sections)
        )
    if question_ids != expected_questions:
        raise ValidationError(
            "image manifest question_ids do not match database: %s"
            % _format_set_difference(question_ids, expected_questions)
        )
    return len(section_ids), len(question_ids)


def validate_chapter(db_path, chapter, patch_patterns, image_manifest_path, expect_reviewed):
    chapter = _require_integer(chapter, "chapter")
    expect_reviewed = _require_integer(expect_reviewed, "expect-reviewed")
    if expect_reviewed < 0:
        raise ValidationError("expect-reviewed must be non-negative")

    chapter_question_ids, image_sections, image_questions = _load_chapter_data(db_path, chapter)
    actual_count = len(chapter_question_ids)
    if actual_count != expect_reviewed:
        raise ValidationError(
            "database chapter %s has %s questions, expected %s"
            % (chapter, actual_count, expect_reviewed)
        )

    patch_files = _expand_patch_patterns(patch_patterns)
    reviewed, item_count, severe_count = _validate_patches(
        patch_files, chapter, chapter_question_ids, expect_reviewed
    )
    image_section_count, image_question_count = _validate_image_manifest(
        image_manifest_path, chapter, image_sections, image_questions
    )
    return {
        "chapter": chapter,
        "reviewed": reviewed,
        "items": item_count,
        "severe": severe_count,
        "image_sections": image_section_count,
        "image_questions": image_question_count,
    }


def _build_parser():
    parser = argparse.ArgumentParser(description="Validate chapter review patches without writing the database.")
    parser.add_argument("--db", required=True)
    parser.add_argument("--chapter", required=True, type=int)
    parser.add_argument("--patches", required=True, nargs="+")
    parser.add_argument("--image-manifest", required=True)
    parser.add_argument("--expect-reviewed", required=True, type=int)
    return parser


def main(argv=None):
    args = _build_parser().parse_args(argv)
    try:
        summary = validate_chapter(
            db_path=args.db,
            chapter=args.chapter,
            patch_patterns=args.patches,
            image_manifest_path=args.image_manifest,
            expect_reviewed=args.expect_reviewed,
        )
    except ValidationError as exc:
        print("validation failed: %s" % exc, file=sys.stderr)
        return 1
    print(json.dumps(summary, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
