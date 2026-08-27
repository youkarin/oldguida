import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "merge_image_fragments.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("merge_image_fragments", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MergeImageFragmentsTests(unittest.TestCase):
    def test_merges_and_sorts_fragment_content(self):
        module = _load_module()
        fragments = [
            {
                "chapter": 13,
                "section_ids": [5],
                "question_ids": [50],
                "images": [{"section_id": 5, "image_path": "5.gif"}],
            },
            {
                "chapter": 13,
                "section_ids": [3],
                "question_ids": [30],
                "images": [{"section_id": 3, "image_path": "3.gif"}],
            },
        ]

        result = module.merge_fragments(13, fragments)

        self.assertEqual(result["section_ids"], [3, 5])
        self.assertEqual(result["question_ids"], [30, 50])
        self.assertEqual([image["section_id"] for image in result["images"]], [3, 5])

    def test_rejects_duplicate_question_ids(self):
        module = _load_module()
        fragments = [
            {"chapter": 13, "section_ids": [], "question_ids": [30], "images": []},
            {"chapter": 13, "section_ids": [], "question_ids": [30], "images": []},
        ]

        with self.assertRaisesRegex(ValueError, "duplicate question id 30"):
            module.merge_fragments(13, fragments)


if __name__ == "__main__":
    unittest.main()
