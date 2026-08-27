import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.keywords.extract_candidates import extract_candidates


SOURCE_ROOT = Path(__file__).resolve().parents[3]


class CandidateExtractionTest(unittest.TestCase):
    def test_normalizes_case_curly_apostrophes_and_accented_italian_words(self):
        result = extract_candidates(
            [
                "L’autovettura e l'AUTOVETTURA sono già ferme.",
                "Dare precedenza all’autovettura.",
            ]
        )

        words = {item["term"]: item["frequency"] for item in result["words"]}
        phrases = {item["term"]: item["frequency"] for item in result["phrases"]}

        self.assertEqual(words["autovettura"], 3)
        self.assertEqual(words["già"], 1)
        self.assertEqual(phrases["dare precedenza"], 1)

    def test_excludes_stopwords_and_pairs_made_only_of_stopwords(self):
        result = extract_candidates(["Il veicolo e la strada", "A e o per"])

        words = {item["term"] for item in result["words"]}
        phrases = {item["term"] for item in result["phrases"]}

        self.assertEqual(words, {"strada", "veicolo"})
        self.assertIn("il veicolo", phrases)
        self.assertIn("veicolo e", phrases)
        self.assertNotIn("a e", phrases)
        self.assertNotIn("e o", phrases)
        self.assertNotIn("o per", phrases)

    def test_sorts_equal_frequency_candidates_alphabetically(self):
        result = extract_candidates(["Motore freno.", "Freno motore."])

        self.assertEqual(
            [item["term"] for item in result["words"]],
            ["freno", "motore"],
        )
        self.assertTrue(
            all(item["frequency"] > 0 for group in result.values() for item in group)
        )

    def test_cli_writes_corpus_size_and_creates_missing_output_directory(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            database_path = directory / "quiz.db"
            output_path = directory / "missing" / "candidates.json"
            self.create_quiz_database(database_path, ["Dare precedenza.", "Il veicolo frena."])

            result = subprocess.run(
                [
                    sys.executable,
                    str(SOURCE_ROOT / "tools/keywords/extract_candidates.py"),
                    "--db",
                    str(database_path),
                    "--out",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["questions"], 2)
            self.assertTrue(
                all(
                    item["frequency"] > 0
                    for group in (payload["words"], payload["phrases"])
                    for item in group
                )
            )

    def test_cli_reports_a_friendly_error_for_a_missing_database(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            missing_database = Path(temporary_directory) / "missing.db"

            result = subprocess.run(
                [
                    sys.executable,
                    str(SOURCE_ROOT / "tools/keywords/extract_candidates.py"),
                    "--db",
                    str(missing_database),
                    "--out",
                    str(Path(temporary_directory) / "candidates.json"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("ERROR:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    @staticmethod
    def create_quiz_database(database_path, questions):
        connection = sqlite3.connect(database_path)
        try:
            connection.execute("CREATE TABLE quiz (id INTEGER PRIMARY KEY, question TEXT)")
            connection.executemany(
                "INSERT INTO quiz (question) VALUES (?)",
                [(question,) for question in questions],
            )
            connection.commit()
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
