import argparse
import json
from pathlib import Path


def merge_fragments(chapter, fragments):
    section_ids = []
    question_ids = []
    images = []
    seen_sections = set()
    seen_questions = set()
    seen_images = set()

    for fragment in fragments:
        if fragment.get("chapter") != chapter:
            raise ValueError(
                "fragment has chapter %r, expected %r"
                % (fragment.get("chapter"), chapter)
            )

        for section_id in fragment.get("section_ids", []):
            if section_id in seen_sections:
                raise ValueError("duplicate section id %s" % section_id)
            seen_sections.add(section_id)
            section_ids.append(section_id)

        for question_id in fragment.get("question_ids", []):
            if question_id in seen_questions:
                raise ValueError("duplicate question id %s" % question_id)
            seen_questions.add(question_id)
            question_ids.append(question_id)

        for image in fragment.get("images", []):
            section_id = image.get("section_id")
            if section_id in seen_images:
                raise ValueError("duplicate image section id %s" % section_id)
            seen_images.add(section_id)
            images.append(image)

    return {
        "chapter": chapter,
        "section_ids": sorted(section_ids),
        "question_ids": sorted(question_ids),
        "images": sorted(images, key=lambda image: image["section_id"]),
    }


def main():
    parser = argparse.ArgumentParser(description="Merge chapter image-review fragments.")
    parser.add_argument("--chapter", required=True, type=int)
    parser.add_argument("--output", required=True)
    parser.add_argument("fragments", nargs="+")
    args = parser.parse_args()

    fragment_data = []
    for fragment_path in args.fragments:
        with Path(fragment_path).open(encoding="utf-8") as stream:
            fragment_data.append(json.load(stream))

    manifest = merge_fragments(args.chapter, fragment_data)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


if __name__ == "__main__":
    main()
