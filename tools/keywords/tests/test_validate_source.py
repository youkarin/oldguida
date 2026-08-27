import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from tools.keywords.validate_source import (
    ValidationError,
    has_italian_boundaries,
    normalize_text,
    validation_summary,
    validate_source,
)


SOURCE_ROOT = Path(__file__).resolve().parents[3]
VALIDATOR_PATH = SOURCE_ROOT / "tools/keywords/validate_source.py"
DICTIONARY_PATH = SOURCE_ROOT / "tools/keywords/data/keyword_dictionary.json"
DATABASE_PATH = SOURCE_ROOT / "assets/db/quiz.db"

VALID_ENTRY = {
    "term": "dare precedenza",
    "partOfSpeech": "固定短语",
    "translation": "让行；给予先行权",
    "note": "表示必须让其他道路使用者先通过。",
    "forms": ["dare precedenza", "dà precedenza"],
    "exampleQuestionId": 1,
}


class SourceValidationTest(unittest.TestCase):
    def setUp(self):
        self.quiz_rows = {
            1: "Il conducente deve dare precedenza all’autovettura.",
            2: "L’AUTOVETTURA è già ferma.",
        }

    def test_accepts_valid_entries_without_mutating_them_and_sorts_stably(self):
        autovettura = {
            "term": "autovettura",
            "partOfSpeech": "名词",
            "translation": "小客车",
            "note": "指主要用于载人的普通汽车。",
            "forms": ["autovettura", "autovetture"],
            "exampleQuestionId": 2,
        }
        source = [deepcopy(VALID_ENTRY), autovettura]
        before = deepcopy(source)

        validated = validate_source(source, self.quiz_rows, enforce_size=False)

        self.assertEqual([entry["term"] for entry in validated], ["autovettura", "dare precedenza"])
        self.assertEqual(source, before)

    def test_normalizes_unicode_case_apostrophes_and_whitespace(self):
        self.assertEqual(normalize_text("  L’AUTOVETTURA\tGIÀ  "), "l'autovettura già")
        self.assertTrue(has_italian_boundaries("L’AUTOVETTURA è già ferma.", "l'autovettura"))
        self.assertTrue(has_italian_boundaries("Deve   dare\tprecedenza, ora.", "dare precedenza"))

    def test_boundaries_reject_partial_accented_and_apostrophe_words(self):
        self.assertFalse(has_italian_boundaries("Una semiautovettura.", "autovettura"))
        self.assertFalse(has_italian_boundaries("È giàx tardi.", "già"))
        self.assertFalse(has_italian_boundaries("È stragià detto.", "già"))
        self.assertFalse(has_italian_boundaries("L'autoveicolo parte.", "auto"))
        self.assertTrue(has_italian_boundaries("L'auto parte.", "auto"))

    def test_boundaries_treat_digits_as_word_characters(self):
        self.assertFalse(has_italian_boundaries("Il codice auto2 non e una parola.", "auto"))
        self.assertFalse(has_italian_boundaries("Il codice 2auto non e una parola.", "auto"))
        self.assertTrue(has_italian_boundaries("Ci sono 2 auto ferme.", "auto"))

    def test_rejects_source_and_entry_container_types(self):
        with self.assertRaisesRegex(ValidationError, "source must be a list"):
            validate_source({}, self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "entry 1 must be an object"):
            validate_source(["not an entry"], self.quiz_rows, enforce_size=False)

    def test_rejects_missing_or_extra_fields(self):
        missing = deepcopy(VALID_ENTRY)
        del missing["note"]
        extra = {**VALID_ENTRY, "frequency": 10}

        with self.assertRaisesRegex(ValidationError, "invalid fields"):
            validate_source([missing], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "invalid fields"):
            validate_source([extra], self.quiz_rows, enforce_size=False)

    def test_rejects_wrong_scalar_field_types(self):
        cases = {
            "term": 1,
            "partOfSpeech": None,
            "translation": ["让行"],
            "note": {"text": "解释"},
            "exampleQuestionId": "1",
        }
        for field, value in cases.items():
            with self.subTest(field=field):
                entry = {**VALID_ENTRY, field: value}
                with self.assertRaisesRegex(ValidationError, field):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

        boolean_id = {**VALID_ENTRY, "exampleQuestionId": True}
        with self.assertRaisesRegex(ValidationError, "exampleQuestionId"):
            validate_source([boolean_id], self.quiz_rows, enforce_size=False)

    def test_rejects_invalid_forms_types_and_empty_forms(self):
        for forms in ("dare precedenza", [], ["dare precedenza", 3], ["dare precedenza", " "]):
            with self.subTest(forms=forms):
                entry = {**VALID_ENTRY, "forms": forms}
                with self.assertRaisesRegex(ValidationError, "forms"):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_non_italian_grammar_and_unlisted_short_terms(self):
        invalid_values = ["x🚗", "abc123", "ø", "道路", "ab"]
        for invalid_value in invalid_values:
            with self.subTest(term=invalid_value):
                entry = {
                    **VALID_ENTRY,
                    "term": invalid_value,
                    "forms": [invalid_value],
                }
                with self.assertRaisesRegex(ValidationError, "Italian term grammar"):
                    validate_source(
                        [entry],
                        {1: f"Il termine {invalid_value} compare qui."},
                        enforce_size=False,
                    )
        for invalid_value in invalid_values:
            with self.subTest(form=invalid_value):
                entry = {
                    **VALID_ENTRY,
                    "forms": ["dare precedenza", invalid_value],
                }
                with self.assertRaisesRegex(ValidationError, "Italian term grammar"):
                    validate_source(
                        [entry],
                        {1: f"Deve dare precedenza; {invalid_value}."},
                        enforce_size=False,
                    )

    def test_accepts_naturally_cased_whitelisted_short_unit(self):
        entry = {
            **VALID_ENTRY,
            "term": "kW",
            "partOfSpeech": "名词",
            "translation": "千瓦",
            "note": "表示机动车发动机功率的法定计量单位。",
            "forms": ["kW"],
        }

        validated = validate_source(
            [entry],
            {1: "La potenza massima e di 15 kW."},
            enforce_size=False,
        )

        self.assertEqual(validated[0]["term"], "kW")

    def test_requires_normalized_spacing_and_apostrophes_without_forcing_case(self):
        upper_term = {**VALID_ENTRY, "term": "Dare precedenza", "forms": ["Dare precedenza"]}
        curly_form = {**VALID_ENTRY, "forms": ["dare precedenza", "dà  precedenza"]}

        validated = validate_source([upper_term], self.quiz_rows, enforce_size=False)
        self.assertEqual(validated[0]["term"], "Dare precedenza")
        with self.assertRaisesRegex(ValidationError, "form must be normalized"):
            validate_source([curly_form], self.quiz_rows, enforce_size=False)

    def test_rejects_form_unrelated_to_canonical_term(self):
        entry = {
            **VALID_ENTRY,
            "term": "auto",
            "partOfSpeech": "名词",
            "translation": "汽车",
            "note": "泛指道路上的机动车。",
            "forms": ["auto", "freno"],
        }

        with self.assertRaisesRegex(ValidationError, "unrelated form"):
            validate_source(
                [entry],
                {1: "L'auto ha un freno di servizio."},
                enforce_size=False,
            )

    def test_rejects_short_false_stems_that_resemble_inflections(self):
        cases = [
            ("casco", "casa", "Il casco resta nella casa."),
            ("corsia", "corsa", "La corsia non serve per una corsa."),
        ]
        for term, unrelated_form, question in cases:
            with self.subTest(term=term, form=unrelated_form):
                entry = {
                    **VALID_ENTRY,
                    "term": term,
                    "partOfSpeech": "名词",
                    "translation": "驾驶相关名词",
                    "note": "用于证明相似前缀不能替代真实屈折关系。",
                    "forms": [term, unrelated_form],
                }
                with self.assertRaisesRegex(ValidationError, "unrelated form"):
                    validate_source([entry], {1: question}, enforce_size=False)

    def test_requires_nonempty_chinese_translation_and_note(self):
        cases = {
            "translation": "yield",
            "note": "driving context",
            "partOfSpeech": "noun",
        }
        for field, value in cases.items():
            with self.subTest(field=field):
                entry = {**VALID_ENTRY, field: value}
                with self.assertRaisesRegex(ValidationError, field):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

        for field in ("translation", "note", "partOfSpeech"):
            with self.subTest(blank=field):
                entry = {**VALID_ENTRY, field: "  "}
                with self.assertRaisesRegex(ValidationError, field):
                    validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_unknown_part_of_speech_and_placeholder_copy(self):
        bad_part = {**VALID_ENTRY, "partOfSpeech": "术语"}
        placeholder_translation = {**VALID_ENTRY, "translation": "相关术语"}
        placeholder_note = {**VALID_ENTRY, "note": "这是驾考中的常见相关术语。"}

        with self.assertRaisesRegex(ValidationError, "partOfSpeech"):
            validate_source([bad_part], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "placeholder"):
            validate_source([placeholder_translation], self.quiz_rows, enforce_size=False)
        with self.assertRaisesRegex(ValidationError, "placeholder"):
            validate_source([placeholder_note], self.quiz_rows, enforce_size=False)

    def test_rejects_duplicate_normalized_term(self):
        other = {
            **VALID_ENTRY,
            "forms": ["dà precedenza"],
        }
        with self.assertRaisesRegex(ValidationError, "duplicate normalized term"):
            validate_source([VALID_ENTRY, other], self.quiz_rows, enforce_size=False)

    def test_rejects_duplicate_normalized_form_within_one_entry(self):
        entry = {**VALID_ENTRY, "forms": ["dare precedenza", "dare precedenza"]}
        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_duplicate_normalized_form_across_entries(self):
        other = {
            "term": "precedenza",
            "partOfSpeech": "名词",
            "translation": "优先权",
            "note": "表示道路使用者依法享有的先行权。",
            "forms": ["precedenza", "dà precedenza"],
            "exampleQuestionId": 1,
        }
        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([VALID_ENTRY, other], self.quiz_rows, enforce_size=False)

    def test_reports_normalized_duplicate_before_noncanonical_spelling(self):
        other = {
            "term": "precedenza",
            "partOfSpeech": "名词",
            "translation": "优先权",
            "note": "表示道路使用者依法享有的先行权。",
            "forms": ["Dare precedenza"],
            "exampleQuestionId": 1,
        }

        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([VALID_ENTRY, other], self.quiz_rows, enforce_size=False)

    def test_rejects_missing_canonical_form(self):
        entry = {**VALID_ENTRY, "forms": ["dà precedenza"]}
        with self.assertRaisesRegex(ValidationError, "canonical term missing from forms"):
            validate_source([entry], self.quiz_rows, enforce_size=False)

    def test_rejects_unknown_or_nonmatching_example(self):
        unknown = {**VALID_ENTRY, "exampleQuestionId": 999}
        with self.assertRaisesRegex(ValidationError, "unknown example question"):
            validate_source([unknown], self.quiz_rows, enforce_size=False)

        with self.assertRaisesRegex(ValidationError, "example does not contain"):
            validate_source([VALID_ENTRY], {1: "Il veicolo rallenta"}, enforce_size=False)

    def test_enforces_dictionary_size_by_default(self):
        with self.assertRaisesRegex(ValidationError, "outside 500..800"):
            validate_source([], {}, enforce_size=True)
        with self.assertRaisesRegex(ValidationError, "outside 500..800"):
            validate_source([{}] * 801, {}, enforce_size=True)

    def test_validation_summary_computes_failures_from_input(self):
        first = deepcopy(VALID_ENTRY)
        second = {
            **deepcopy(VALID_ENTRY),
            "translation": " ",
            "exampleQuestionId": 999,
        }

        summary = validation_summary([first, second], self.quiz_rows)

        self.assertEqual(summary["duplicateTerms"], 1)
        self.assertEqual(summary["duplicateForms"], 2)
        self.assertEqual(summary["emptyDefinitions"], 1)
        self.assertEqual(summary["invalidExampleIds"], 1)


class SourceValidatorCliTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)
        self.database_path = self.directory / "quiz.db"
        connection = sqlite3.connect(self.database_path)
        try:
            connection.execute("CREATE TABLE quiz (id INTEGER PRIMARY KEY, question TEXT)")
            connection.execute("INSERT INTO quiz VALUES (1, 'Deve dare precedenza.')")
            connection.commit()
        finally:
            connection.close()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_cli_reports_json_io_and_sqlite_errors_without_tracebacks(self):
        malformed_json = self.directory / "malformed.json"
        malformed_json.write_text("{", encoding="utf-8")
        invalid_database = self.directory / "invalid.db"
        invalid_database.write_bytes(b"not sqlite")
        valid_source = self.directory / "source.json"
        valid_source.write_text("[]", encoding="utf-8")

        commands = [
            ["--db", str(self.database_path), "--source", str(malformed_json)],
            ["--db", str(self.database_path), "--source", str(self.directory / "missing.json")],
            ["--db", str(invalid_database), "--source", str(valid_source)],
        ]
        for arguments in commands:
            with self.subTest(arguments=arguments):
                result = self.run_cli(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_cli_reports_validation_errors_without_tracebacks(self):
        source_path = self.directory / "source.json"
        source_path.write_text(json.dumps({"entries": []}), encoding="utf-8")

        result = self.run_cli("--db", str(self.database_path), "--source", str(source_path))

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("ERROR:", result.stderr)
        self.assertIn("source must be a list", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def run_cli(self, *arguments):
        return subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )


class CuratedDictionaryRegressionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.entries = json.loads(DICTIONARY_PATH.read_text(encoding="utf-8"))
        cls.by_term = {entry["term"]: entry for entry in cls.entries}
        connection = sqlite3.connect(DATABASE_PATH)
        try:
            cls.quiz_rows = dict(connection.execute("SELECT id, question FROM quiz ORDER BY id"))
        finally:
            connection.close()

    def test_every_curated_form_occurs_in_real_question_corpus(self):
        questions = list(self.quiz_rows.values())
        missing = [
            (entry["term"], form)
            for entry in self.entries
            for form in entry["forms"]
            if not any(has_italian_boundaries(question, form) for question in questions)
        ]

        self.assertEqual(missing, [])

    def test_reviewed_polysemy_and_longest_match_phrases(self):
        sinistro = self.by_term["sinistro"]
        self.assertIn("事故", sinistro["translation"])
        self.assertIn("左", sinistro["translation"])

        scarico = self.by_term["scarico"]
        for meaning in ("排气", "装卸", "空载", "失效"):
            self.assertIn(meaning, scarico["translation"])

        expected_phrases = {
            "lato sinistro": "左侧",
            "a bordo": "车上",
            "carico e scarico": "装卸",
            "veicoli scarichi": "空载",
            "ammortizzatori scarichi": "失效",
            "scarico dei residui": "排放",
            "pieno carico": "满载",
            "a carico del": "承担",
            "fermata di autobus": "公交",
            "punto di arresto": "停车点",
            "mettere a punto": "调校",
            "marcia bassa": "低挡",
            "prima marcia": "一挡",
            "arresto preventivo": "羁押",
            "a portata di braccio": "伸手可及",
            "ruote motrici": "驱动轮",
            "camera d'aria": "内胎",
            "cambio d'olio": "更换机油",
            "asse della carreggiata": "中轴线",
            "aria condizionata": "空调",
        }
        for term, meaning in expected_phrases.items():
            with self.subTest(term=term):
                self.assertIn(term, self.by_term)
                self.assertIn(meaning, self.by_term[term]["translation"])

        self.assertIn("a pieno carico", self.by_term["pieno carico"]["forms"])

        freccia = self.by_term["freccia direzionale"]
        freccia_definition = freccia["translation"] + freccia["note"]
        self.assertIn("路面", freccia_definition)
        self.assertNotIn("转向灯", freccia_definition)

    def test_reviewed_parts_of_speech_and_contextual_meanings(self):
        expected = {
            "circolare": ("动词/形容词", ("通行", "圆形")),
            "regolare": ("动词/形容词", ("调节", "正常")),
            "permesso": ("名词/形容词", ("许可", "允许")),
            "guasto": ("名词/形容词", ("故障", "损坏")),
            "rettilineo": ("名词/形容词", ("直线路段", "直线的")),
            "sinistra": ("名词/形容词", ("左侧", "左边的")),
        }
        for term, (part_of_speech, meanings) in expected.items():
            with self.subTest(term=term):
                entry = self.by_term[term]
                self.assertEqual(entry["partOfSpeech"], part_of_speech)
                for meaning in meanings:
                    self.assertIn(meaning, entry["translation"])

        self.assertNotIn("motrici", self.by_term["motrice"]["forms"])
        self.assertIn("ruote motrici", self.by_term["ruote motrici"]["forms"])

    def test_reviewed_canonical_terms_merges_and_superamento(self):
        removed_terms = {
            "farmaci",
            "inefficienti",
            "inquinanti",
            "massimali",
            "rifiuti",
            "riflessi",
            "scolari",
            "usurati",
            "essere",
            "cellulare",
            "dare precedenza",
            "a pieno carico",
            "non possono",
        }
        self.assertTrue(removed_terms.isdisjoint(self.by_term))

        expected_corpus_real_terms = {
            "farmaci sedativi",
            "sospensioni inefficienti",
            "gas inquinanti",
            "rifiuti urbani",
            "riflessi pronti",
            "trasporto scolari",
            "pneumatici sono usurati",
            "massimale",
        }
        self.assertTrue(expected_corpus_real_terms.issubset(self.by_term))
        self.assertEqual(self.by_term["kW"]["forms"], ["kW"])
        self.assertEqual(self.by_term["bisogna"]["partOfSpeech"], "无人称动词")
        self.assertEqual(self.by_term["occorre"]["partOfSpeech"], "无人称动词")

        self.assertIn("cellulare", self.by_term["telefono cellulare"]["forms"])
        self.assertIn("cellulari", self.by_term["telefono cellulare"]["forms"])
        self.assertIn("dare precedenza", self.by_term["dare la precedenza"]["forms"])
        self.assertIn("non possono", self.by_term["non può"]["forms"])

        superamento = self.by_term["superamento"]
        self.assertIn("通过", superamento["translation"])
        self.assertIn("超过", superamento["translation"])

    def test_vehicle_entities_with_different_legal_meanings_stay_separate(self):
        expected_meanings = {
            "autocaravan": "自行式房车",
            "caravan": "拖挂式旅居挂车",
            "rimorchio": "挂车",
            "semirimorchio": "半挂车",
        }
        forms_by_entity = []
        for term, meaning in expected_meanings.items():
            with self.subTest(term=term):
                entry = self.by_term[term]
                self.assertIn(meaning, entry["translation"])
                forms_by_entity.append(set(map(normalize_text, entry["forms"])))
        for index, forms in enumerate(forms_by_entity):
            for other_forms in forms_by_entity[index + 1 :]:
                self.assertTrue(forms.isdisjoint(other_forms))

    def test_reviewed_corpus_variants_are_retained(self):
        expected_variants = {
            "accelerazione": ["accelerazioni"],
            "altezza": ["altezze"],
            "assicurato": ["assicurata"],
            "batteria": ["batterie"],
            "caduta": ["cadute"],
            "casello": ["caselli"],
            "telefono cellulare": ["cellulari"],
            "colonna": ["colonne"],
            "confluenza": ["confluenze"],
            "danneggiato": ["danneggiata", "danneggiate"],
            "fermata": ["fermate"],
            "frenante": ["frenanti"],
            "giubbotto": ["giubbotti"],
            "immissione": ["immissioni"],
            "ingresso": ["ingressi"],
            "liquido": ["liquidi"],
            "manutenzione": ["manutenzioni"],
            "margine": ["margini"],
            "massimale": ["massimale"],
            "officina": ["officine"],
            "ospedale": ["ospedali"],
            "partenza": ["partenze"],
            "pendenza": ["pendenze"],
            "piazzola": ["piazzole"],
            "polizza": ["polizze"],
            "ponte": ["ponti"],
            "precedenza": ["precedenze"],
            "reazione": ["reazioni"],
            "rettilineo": ["rettilinei"],
            "riparazione": ["riparazioni"],
            "salita": ["salite"],
            "soccorso": ["soccorsi"],
            "sorpasso": ["sorpassi"],
            "sosta": ["soste"],
            "sostituzione": ["sostituzioni"],
            "strettoia": ["strettoie"],
            "tergicristallo": ["tergicristalli"],
            "titolare": ["titolari"],
            "transito": ["transiti"],
            "triangolo": ["triangoli"],
            "fine": ["fini"],
            "olio": ["olii"],
            "svolta": ["svolte"],
        }
        self.assertEqual(sum(map(len, expected_variants.values())), 44)
        for term, variants in expected_variants.items():
            with self.subTest(term=term):
                self.assertIn(term, self.by_term)
                for variant in variants:
                    self.assertIn(variant, self.by_term[term]["forms"])


if __name__ == "__main__":
    unittest.main()
