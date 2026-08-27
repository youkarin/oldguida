# Offline Keyword Dictionary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an offline, curated Italian driving-theory dictionary inside `quiz.db`, expose it from the home screen, and make matched terms tappable on every question surface.

**Architecture:** Keep the audited source data and deterministic importer under `tools/keywords/`, while the shipped runtime data lives in four new SQLite tables. A repository and longest-match service feed one reusable `KeywordQuestionText` widget, which falls back to ordinary text if the feature is disabled or dictionary loading fails.

**Tech Stack:** Flutter/Dart, SQLite through `sqflite`, `shared_preferences`, Python 3 standard library for corpus analysis and database import, Flutter unit/widget tests, Python `unittest`.

**Spec:** `docs/superpowers/specs/2026-08-27-keyword-translation-and-branding-design.md`

## Global Constraints

- Runtime lookup is fully offline; do not add an online translation service.
- Store 500 to 800 curated high-frequency driving-theory words and fixed phrases in `assets/db/quiz.db`.
- Do not modify any existing `quiz`, `chapter`, or `section` value.
- Preserve Android `applicationId`, iOS bundle identifier, and all user-owned tables during database upgrades.
- Fixed phrases and longer forms win over shorter overlapping terms.
- `keywordTranslationEnabled` defaults to `true`; disabling it affects question annotations only, never the standalone dictionary.
- Do not stage the pre-existing generated plugin file changes under `linux/`, `macos/Flutter/`, or `windows/flutter/`.

---

## File Map

- Create `tools/keywords/extract_candidates.py`: derive auditable word and phrase frequencies from the existing questions.
- Create `tools/keywords/build_dictionary.py`: validate structured source data and replace only the four dictionary tables.
- Create `tools/keywords/verify_protected_tables.py`: hash protected table content before and after import.
- Create `tools/keywords/data/keyword_dictionary.json`: curated source of truth for 500 to 800 entries.
- Create `tools/keywords/tests/`: Python tests for extraction, validation, import, and protected-table verification.
- Modify `assets/db/quiz.db`: add the populated dictionary tables and set `PRAGMA user_version=4`.
- Create `lib/database/keyword_database.dart`: schema creation and bundled-dictionary synchronization for existing installs.
- Modify `lib/database/database_helper.dart`: upgrade to database version 4 and expose dictionary queries.
- Modify `lib/models/question_model.dart`: retain stable `quiz.id` for matching cache and examples.
- Create `lib/models/keyword_model.dart`: dictionary, form, example, and match value objects.
- Create `lib/Services/keyword_repository.dart`: SQLite-backed list, search, detail, form, and example access.
- Create `lib/Services/keyword_matcher.dart`: normalization, boundary checks, longest match, and cache.
- Create `lib/Services/keyword_service.dart`: lazy-loading facade shared by question widgets and tests.
- Create `lib/Services/keyword_translation_settings.dart`: persisted, observable feature toggle.
- Modify `lib/main.dart`: load the persisted keyword toggle before rendering the app.
- Create `lib/widgets/keyword_question_text.dart`: tappable underlined question text.
- Create `lib/widgets/keyword_definition_sheet.dart`: compact definition bottom sheet.
- Create `lib/Screen/General/dictionary_screen.dart`: searchable dictionary list.
- Create `lib/Screen/General/dictionary_detail_screen.dart`: full entry with forms and a bilingual example.
- Modify `lib/Screen/Homepage.dart`: add the dictionary home entry and route.
- Modify all existing question-display files listed in Task 10 to use `KeywordQuestionText`.
- Create `test/`: Dart tests for schema sync, models, repository, matcher, settings, widgets, and screens.

### Task 1: Protect the Existing Quiz Database

**Files:**
- Create: `tools/keywords/verify_protected_tables.py`
- Create: `tools/keywords/tests/test_verify_protected_tables.py`
- Create during execution, do not stage: `../oldguida_new_backup/quiz-before-keywords-20260827.db`
- Create during execution, do not stage: `tools/keywords/work/protected-baseline.json`

**Interfaces:**
- Produces: `snapshot(database_path: Path) -> dict[str, object]`
- Produces: baseline counts and SHA-256 digests for `quiz`, `chapter`, and `section`.

- [ ] **Step 1: Write the failing protected-table test**

```python
class ProtectedTableSnapshotTest(unittest.TestCase):
    def test_snapshot_changes_when_a_question_changes(self):
        before = snapshot(self.db_path)
        with sqlite3.connect(self.db_path) as con:
            con.execute("UPDATE quiz SET question='changed' WHERE id=1")
        after = snapshot(self.db_path)
        self.assertEqual(before["quiz"]["rows"], after["quiz"]["rows"])
        self.assertNotEqual(before["quiz"]["sha256"], after["quiz"]["sha256"])
```

- [ ] **Step 2: Run the test and observe the missing module failure**

Run: `python -m unittest tools.keywords.tests.test_verify_protected_tables -v`

Expected: FAIL because `tools.keywords.verify_protected_tables` does not exist.

- [ ] **Step 3: Implement deterministic protected-table snapshots**

```python
PROTECTED_QUERIES = {
    "quiz": "SELECT id,question,answer,section_id,translation,explanation,question_number FROM quiz ORDER BY id",
    "chapter": "SELECT id,chapter_id,name,image_path FROM chapter ORDER BY id",
    "section": "SELECT id,section_id,chapter_id,name,image_path FROM section ORDER BY id",
}


def snapshot(database_path: Path) -> dict[str, object]:
    result = {}
    with sqlite3.connect(database_path) as con:
        for table, query in PROTECTED_QUERIES.items():
            rows = con.execute(query).fetchall()
            payload = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
            result[table] = {
                "rows": len(rows),
                "sha256": hashlib.sha256(payload.encode("utf-8")).hexdigest(),
            }
    return result
```

Add a CLI that writes sorted, UTF-8 JSON when `--out` is supplied and prints it otherwise.

- [ ] **Step 4: Run the Python test**

Run: `python -m unittest tools.keywords.tests.test_verify_protected_tables -v`

Expected: PASS.

- [ ] **Step 5: Validate and back up the real database**

```powershell
sqlite3 assets\db\quiz.db "PRAGMA quick_check;"
New-Item -ItemType Directory -Force -Path ..\oldguida_new_backup,tools\keywords\work | Out-Null
Copy-Item -LiteralPath assets\db\quiz.db -Destination ..\oldguida_new_backup\quiz-before-keywords-20260827.db
python tools\keywords\verify_protected_tables.py assets\db\quiz.db --out tools\keywords\work\protected-baseline.json
Get-FileHash assets\db\quiz.db,..\oldguida_new_backup\quiz-before-keywords-20260827.db -Algorithm SHA256
```

Expected: `quick_check` prints `ok`; both file hashes match; baseline row counts are `quiz=7193`, `chapter=25`, and the observed section count is recorded without guessing it.

- [ ] **Step 6: Commit only the reusable guard**

```powershell
git add -- tools/keywords/verify_protected_tables.py tools/keywords/tests/test_verify_protected_tables.py
git commit -m "test: guard protected quiz database tables"
```

### Task 2: Extract High-Frequency Candidate Terms

**Files:**
- Create: `tools/keywords/extract_candidates.py`
- Create: `tools/keywords/tests/test_extract_candidates.py`
- Create during execution, do not stage: `tools/keywords/work/candidates.json`

**Interfaces:**
- Consumes: Italian `quiz.question` text.
- Produces: `extract_candidates(questions: Iterable[str]) -> dict[str, list[dict[str, object]]]` with `words` and `phrases` arrays sorted by descending frequency and then alphabetically.

- [ ] **Step 1: Write tokenizer and frequency tests**

```python
class CandidateExtractionTest(unittest.TestCase):
    def test_counts_apostrophes_case_and_bigrams(self):
        result = extract_candidates([
            "L'autovettura deve dare precedenza.",
            "Dare precedenza all'autovettura.",
        ])
        words = {item["term"]: item["frequency"] for item in result["words"]}
        phrases = {item["term"]: item["frequency"] for item in result["phrases"]}
        self.assertEqual(words["autovettura"], 2)
        self.assertEqual(phrases["dare precedenza"], 2)
```

- [ ] **Step 2: Run the test and observe failure**

Run: `python -m unittest tools.keywords.tests.test_extract_candidates -v`

Expected: FAIL because the extractor is missing.

- [ ] **Step 3: Implement Unicode-aware extraction**

```python
TOKEN_RE = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)?")
STOPWORDS = {"a", "ad", "al", "alla", "che", "con", "da", "dal", "di", "e", "il", "in", "la", "le", "lo", "o", "per", "si", "un", "una"}


def normalize(value: str) -> str:
    return value.lower().replace("’", "'")


def extract_candidates(questions: Iterable[str]) -> dict[str, list[dict[str, object]]]:
    words = Counter()
    phrases = Counter()
    for question in questions:
        tokens = [normalize(token) for token in TOKEN_RE.findall(question)]
        words.update(token for token in tokens if token not in STOPWORDS)
        phrases.update(
            " ".join(pair)
            for pair in zip(tokens, tokens[1:])
            if pair[0] not in STOPWORDS or pair[1] not in STOPWORDS
        )
    pack = lambda counts: [
        {"term": term, "frequency": count}
        for term, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]
    return {"words": pack(words), "phrases": pack(phrases)}
```

The CLI reads all questions from SQLite and writes UTF-8 JSON with the corpus size and both arrays.

- [ ] **Step 4: Run tests and extract the real report**

```powershell
python -m unittest tools.keywords.tests.test_extract_candidates -v
python tools\keywords\extract_candidates.py --db assets\db\quiz.db --out tools\keywords\work\candidates.json
```

Expected: tests PASS; report states `questions=7193`; every candidate frequency is positive.

- [ ] **Step 5: Commit the extractor**

```powershell
git add -- tools/keywords/extract_candidates.py tools/keywords/tests/test_extract_candidates.py
git commit -m "feat: extract Italian keyword candidates"
```

### Task 3: Validate and Curate the Dictionary Source

**Files:**
- Create: `tools/keywords/validate_source.py`
- Create: `tools/keywords/tests/test_validate_source.py`
- Create: `tools/keywords/data/keyword_dictionary.json`

**Interfaces:**
- Consumes: JSON records with `term`, `partOfSpeech`, `translation`, `note`, `forms`, and `exampleQuestionId`.
- Produces: `validate_source(source, quiz_rows) -> list[dict[str, object]]`, sorted by normalized term.

- [ ] **Step 1: Write source validation tests**

```python
VALID_ENTRY = {
    "term": "dare precedenza",
    "partOfSpeech": "固定短语",
    "translation": "让行；给予先行权",
    "note": "表示必须让其他道路使用者先通过。",
    "forms": ["dare precedenza", "dà precedenza"],
    "exampleQuestionId": 1,
}


class SourceValidationTest(unittest.TestCase):
    def test_rejects_duplicate_normalized_form(self):
        other = {**VALID_ENTRY, "term": "precedenza", "forms": ["Dare precedenza"]}
        with self.assertRaisesRegex(ValidationError, "duplicate normalized form"):
            validate_source([VALID_ENTRY, other], {1: "Dare precedenza"}, enforce_size=False)

    def test_rejects_example_that_does_not_contain_a_form(self):
        with self.assertRaisesRegex(ValidationError, "example does not contain"):
            validate_source([VALID_ENTRY], {1: "Il veicolo rallenta"}, enforce_size=False)
```

- [ ] **Step 2: Run the test and observe failure**

Run: `python -m unittest tools.keywords.tests.test_validate_source -v`

Expected: FAIL because the validator is missing.

- [ ] **Step 3: Implement strict validation**

```python
REQUIRED_FIELDS = {"term", "partOfSpeech", "translation", "note", "forms", "exampleQuestionId"}


def validate_source(source, quiz_rows, enforce_size=True):
    if enforce_size and not 500 <= len(source) <= 800:
        raise ValidationError(f"entry count {len(source)} is outside 500..800")
    seen_terms = set()
    seen_forms = set()
    validated = []
    for entry in source:
        if set(entry) != REQUIRED_FIELDS:
            raise ValidationError(f"invalid fields for {entry.get('term')}")
        term = normalize_text(entry["term"])
        forms = [normalize_text(value) for value in entry["forms"]]
        if not term or not entry["translation"].strip() or not entry["partOfSpeech"].strip():
            raise ValidationError("term, partOfSpeech and translation are required")
        if term in seen_terms:
            raise ValidationError(f"duplicate normalized term: {term}")
        if term not in forms:
            raise ValidationError(f"canonical term missing from forms: {term}")
        for form in forms:
            if form in seen_forms:
                raise ValidationError(f"duplicate normalized form: {form}")
            seen_forms.add(form)
        question = quiz_rows.get(entry["exampleQuestionId"])
        if question is None:
            raise ValidationError(f"unknown example question: {entry['exampleQuestionId']}")
        if not any(has_italian_boundaries(question, form) for form in forms):
            raise ValidationError(f"example does not contain a form: {term}")
        seen_terms.add(term)
        validated.append(entry)
    return sorted(validated, key=lambda item: normalize_text(item["term"]))
```

- [ ] **Step 4: Run validator tests**

Run: `python -m unittest tools.keywords.tests.test_validate_source -v`

Expected: PASS.

- [ ] **Step 5: Curate road, sign, and right-of-way entries**

Using `tools/keywords/work/candidates.json` and the existing bilingual questions, add roughly 100 high-frequency entries covering road parts, intersections, traffic signs, signals, priority, and right-of-way. Each record must follow this exact structure:

```json
{
  "term": "precedenza",
  "partOfSpeech": "名词",
  "translation": "优先权；先行权",
  "note": "在通行规则中表示某一方有先行权，或另一方负有让行义务。",
  "forms": ["precedenza"],
  "exampleQuestionId": 146
}
```

Select an actual question id containing the term, then confirm its existing Chinese translation demonstrates the same meaning.

- [ ] **Step 6: Curate vehicle, component, and document entries**

Add roughly 100 entries covering vehicle classes, vehicle components, loads, trailers, lights, tyres, licences, registration, insurance, and mandatory documents. Keep `autocaravan`, `caravan`, `rimorchio`, and `semirimorchio` as distinct terms.

- [ ] **Step 7: Curate manoeuvre, speed, and stopping entries**

Add roughly 100 entries covering starting, stopping, parking, overtaking, turning, reversing, lane changes, speed, braking distance, following distance, and visibility.

- [ ] **Step 8: Curate safety, people, emergency, and impairment entries**

Add roughly 100 entries covering pedestrians, cyclists, children, vulnerable road users, protective equipment, collisions, first aid, alcohol, drugs, fatigue, and emergency conduct.

- [ ] **Step 9: Curate environment, maintenance, offences, and fixed phrases**

Add enough verified entries to bring the total into the 500 to 800 range, prioritizing recurring legal verbs and fixed phrases such as obligations, prohibitions, permissions, danger, pollution, maintenance, penalties, and responsibility.

- [ ] **Step 10: Validate the complete source against the real corpus**

Run:

```powershell
python tools\keywords\validate_source.py --db assets\db\quiz.db --source tools\keywords\data\keyword_dictionary.json
```

Expected: exit code 0; output reports an entry count from 500 through 800, zero duplicate terms, zero duplicate forms, zero empty definitions, and zero invalid example ids.

- [ ] **Step 11: Commit the validated source and validator**

```powershell
git add -- tools/keywords/data/keyword_dictionary.json tools/keywords/validate_source.py tools/keywords/tests/test_validate_source.py
git commit -m "feat: curate offline driving dictionary"
```

### Task 4: Import the Curated Source into `quiz.db`

**Files:**
- Create: `tools/keywords/build_dictionary.py`
- Create: `tools/keywords/tests/test_build_dictionary.py`
- Modify: `assets/db/quiz.db`

**Interfaces:**
- Consumes: validated `keyword_dictionary.json` and existing quiz rows.
- Produces: `build_dictionary(db_path: Path, source_path: Path, version: int) -> dict[str, int]`.
- Produces SQLite tables: `keyword_dictionary`, `keyword_forms`, `keyword_examples`, and `dictionary_meta`.

- [ ] **Step 1: Write an importer transaction test**

```python
class DictionaryBuildTest(unittest.TestCase):
    def test_build_replaces_only_dictionary_tables(self):
        protected_before = snapshot(self.db_path)
        result = build_dictionary(self.db_path, self.source_path, version=1, enforce_size=False)
        protected_after = snapshot(self.db_path)
        self.assertEqual(protected_before, protected_after)
        self.assertEqual(result, {"entries": 1, "forms": 2, "examples": 1})
        with sqlite3.connect(self.db_path) as con:
            self.assertEqual(con.execute("PRAGMA user_version").fetchone()[0], 4)
            self.assertEqual(con.execute("SELECT value FROM dictionary_meta WHERE key='version'").fetchone()[0], "1")
```

- [ ] **Step 2: Run the test and observe failure**

Run: `python -m unittest tools.keywords.tests.test_build_dictionary -v`

Expected: FAIL because the importer is missing.

- [ ] **Step 3: Implement schema replacement inside one transaction**

```python
SCHEMA = """
CREATE TABLE IF NOT EXISTS keyword_dictionary (
  id INTEGER PRIMARY KEY,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL UNIQUE,
  part_of_speech TEXT NOT NULL,
  translation TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  frequency INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS keyword_forms (
  id INTEGER PRIMARY KEY,
  keyword_id INTEGER NOT NULL,
  form TEXT NOT NULL,
  normalized_form TEXT NOT NULL UNIQUE,
  FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
);
CREATE TABLE IF NOT EXISTS keyword_examples (
  id INTEGER PRIMARY KEY,
  keyword_id INTEGER NOT NULL,
  question_id INTEGER NOT NULL,
  rank INTEGER NOT NULL DEFAULT 0,
  UNIQUE(keyword_id, question_id),
  FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
);
CREATE TABLE IF NOT EXISTS dictionary_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS idx_keyword_forms_keyword_id ON keyword_forms(keyword_id);
CREATE INDEX IF NOT EXISTS idx_keyword_examples_keyword_rank ON keyword_examples(keyword_id, rank);
CREATE INDEX IF NOT EXISTS idx_keyword_examples_question_id ON keyword_examples(question_id);
"""


def build_dictionary(db_path, source_path, version, enforce_size=True):
    with sqlite3.connect(db_path) as con:
        questions = dict(con.execute("SELECT id, question FROM quiz"))
        entries = validate_source(read_json(source_path), questions, enforce_size=enforce_size)
        con.executescript(SCHEMA)
        con.execute("BEGIN IMMEDIATE")
        try:
            con.execute("DELETE FROM keyword_examples")
            con.execute("DELETE FROM keyword_forms")
            con.execute("DELETE FROM keyword_dictionary")
            con.execute("DELETE FROM dictionary_meta")
            dictionary_rows = []
            form_rows = []
            example_rows = []
            next_form_id = 1
            for keyword_id, entry in enumerate(entries, start=1):
                normalized_forms = [normalize_text(value) for value in entry["forms"]]
                frequency = sum(
                    1
                    for question in questions.values()
                    if any(has_italian_boundaries(question, form) for form in normalized_forms)
                )
                dictionary_rows.append((
                    keyword_id,
                    entry["term"],
                    normalize_text(entry["term"]),
                    entry["partOfSpeech"],
                    entry["translation"],
                    entry["note"],
                    frequency,
                    keyword_id,
                ))
                for form, normalized_form in zip(entry["forms"], normalized_forms):
                    form_rows.append((next_form_id, keyword_id, form, normalized_form))
                    next_form_id += 1
                example_rows.append((keyword_id, keyword_id, entry["exampleQuestionId"], 0))
            con.executemany(
                "INSERT INTO keyword_dictionary VALUES(?,?,?,?,?,?,?,?)",
                dictionary_rows,
            )
            con.executemany(
                "INSERT INTO keyword_forms VALUES(?,?,?,?)",
                form_rows,
            )
            con.executemany(
                "INSERT INTO keyword_examples VALUES(?,?,?,?)",
                example_rows,
            )
            con.execute("INSERT INTO dictionary_meta(key,value) VALUES('version',?)", (str(version),))
            con.execute("PRAGMA user_version=4")
            con.commit()
        except Exception:
            con.rollback()
            raise
    return {
        "entries": len(dictionary_rows),
        "forms": len(form_rows),
        "examples": len(example_rows),
    }
```

- [ ] **Step 4: Run importer tests**

Run: `python -m unittest tools.keywords.tests.test_build_dictionary -v`

Expected: PASS.

- [ ] **Step 5: Build the real asset database and prove protected data is unchanged**

```powershell
python tools\keywords\build_dictionary.py --db assets\db\quiz.db --source tools\keywords\data\keyword_dictionary.json --dictionary-version 1
python tools\keywords\verify_protected_tables.py assets\db\quiz.db --compare tools\keywords\work\protected-baseline.json
sqlite3 assets\db\quiz.db "PRAGMA integrity_check; PRAGMA user_version; SELECT key,value FROM dictionary_meta; SELECT COUNT(*) FROM keyword_dictionary; SELECT COUNT(*) FROM keyword_forms; SELECT COUNT(*) FROM keyword_examples;"
```

Expected: protected comparison passes; integrity is `ok`; user version is `4`; dictionary version is `1`; entry count is from 500 through 800; forms are at least the entry count; examples equal the entry count or exceed it.

- [ ] **Step 6: Commit importer and populated database**

```powershell
git add -- tools/keywords/build_dictionary.py tools/keywords/tests/test_build_dictionary.py assets/db/quiz.db
git commit -m "feat: embed offline dictionary in quiz database"
```

### Task 5: Add Safe Dictionary Schema Sync for Existing Installs

**Files:**
- Create: `lib/database/keyword_database.dart`
- Modify: `lib/database/database_helper.dart`
- Create: `test/database/keyword_database_test.dart`

**Interfaces:**
- Produces: `KeywordDatabase.ensureSchema(Database db) -> Future<void>`.
- Produces: `KeywordDatabase.syncFrom({required Database target, required Database seed}) -> Future<bool>`.
- Produces: `KeywordDatabase.syncBundledIfNeeded(Database target) -> Future<void>`.
- `DatabaseHelper.database` calls bundled sync after opening and ensuring user tables.

- [ ] **Step 1: Write failing migration tests with two in-memory databases**

```dart
test('syncFrom copies dictionary rows and preserves user rows', () async {
  final target = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  final seed = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await target.execute('CREATE TABLE favorites (id INTEGER PRIMARY KEY, note TEXT)');
  await target.insert('favorites', {'id': 7, 'note': 'keep'});
  await KeywordDatabase.ensureSchema(seed);
  await seed.insert('keyword_dictionary', keywordRow(id: 1));
  await seed.insert('keyword_forms', formRow(id: 1, keywordId: 1));
  await seed.insert('dictionary_meta', {'key': 'version', 'value': '1'});

  expect(await KeywordDatabase.syncFrom(target: target, seed: seed), isTrue);
  expect(await target.query('favorites'), [{'id': 7, 'note': 'keep'}]);
  expect(await target.query('keyword_dictionary'), hasLength(1));
});

test('syncFrom skips an equal dictionary version', () async {
  await KeywordDatabase.ensureSchema(target);
  await KeywordDatabase.ensureSchema(seed);
  await target.insert('dictionary_meta', {'key': 'version', 'value': '1'});
  await seed.insert('dictionary_meta', {'key': 'version', 'value': '1'});
  expect(await KeywordDatabase.syncFrom(target: target, seed: seed), isFalse);
});
```

- [ ] **Step 2: Run migration tests and observe failure**

Run: `flutter test test/database/keyword_database_test.dart`

Expected: FAIL because `KeywordDatabase` is missing.

- [ ] **Step 3: Implement schema and transactional copying**

```dart
abstract final class KeywordDatabase {
  static const bundledVersion = 1;

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS keyword_dictionary (
        id INTEGER PRIMARY KEY,
        term TEXT NOT NULL,
        normalized_term TEXT NOT NULL UNIQUE,
        part_of_speech TEXT NOT NULL,
        translation TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        frequency INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS keyword_forms (
        id INTEGER PRIMARY KEY,
        keyword_id INTEGER NOT NULL,
        form TEXT NOT NULL,
        normalized_form TEXT NOT NULL UNIQUE,
        FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS keyword_examples (
        id INTEGER PRIMARY KEY,
        keyword_id INTEGER NOT NULL,
        question_id INTEGER NOT NULL,
        rank INTEGER NOT NULL DEFAULT 0,
        UNIQUE(keyword_id, question_id),
        FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dictionary_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_keyword_forms_keyword_id ON keyword_forms(keyword_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_keyword_examples_keyword_rank ON keyword_examples(keyword_id, rank)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_keyword_examples_question_id ON keyword_examples(question_id)');
  }

  static Future<int> _version(Database db) async {
    try {
      final rows = await db.query(
        'dictionary_meta',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['version'],
        limit: 1,
      );
      return rows.isEmpty ? 0 : int.tryParse(rows.single['value'] as String) ?? 0;
    } on DatabaseException {
      return 0;
    }
  }

  static Future<bool> syncFrom({required Database target, required Database seed}) async {
    await ensureSchema(target);
    final targetVersion = await _version(target);
    final seedVersion = await _version(seed);
    if (seedVersion <= targetVersion) return false;
    final entries = await seed.query('keyword_dictionary', orderBy: 'id');
    final forms = await seed.query('keyword_forms', orderBy: 'id');
    final examples = await seed.query('keyword_examples', orderBy: 'id');
    await target.transaction((txn) async {
      await txn.delete('keyword_examples');
      await txn.delete('keyword_forms');
      await txn.delete('keyword_dictionary');
      for (final row in entries) { await txn.insert('keyword_dictionary', row); }
      for (final row in forms) { await txn.insert('keyword_forms', row); }
      for (final row in examples) { await txn.insert('keyword_examples', row); }
      await txn.insert('dictionary_meta', {'key': 'version', 'value': '$seedVersion'}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return true;
  }

  static Future<void> syncBundledIfNeeded(Database target) async {
    if (kIsWeb || await _version(target) >= bundledVersion) return;
    final directory = await getApplicationSupportDirectory();
    final seedPath = join(
      directory.path,
      'quiz_dictionary_seed_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    Database? seed;
    try {
      final data = await rootBundle.load('assets/db/quiz.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await io.File(seedPath).writeAsBytes(bytes, flush: true);
      seed = await openDatabase(seedPath, readOnly: true);
      await syncFrom(target: target, seed: seed);
    } finally {
      await seed?.close();
      if (await databaseExists(seedPath)) await deleteDatabase(seedPath);
    }
  }
}
```

Import `dart:io` through the repository's existing conditional `io_stub.dart` pattern, plus `foundation`, `services`, `path`, and `path_provider`. The web branch returns before accessing the stubbed file API.

- [ ] **Step 4: Wire database version 4 and startup sync**

In `database_helper.dart`:

```dart
const int _dbVersion = 4;

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 3) {
    await db.execute('DROP TABLE IF EXISTS $tableFavorites');
    await db.execute('''
      CREATE TABLE $tableFavorites (
        $columnFavoriteId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnFavUserId INTEGER,
        $columnFavSectionId INTEGER,
        $columnFavQuestionNum INTEGER,
        $columnFavCreatedAt TEXT,
        $columnFavNote TEXT,
        UNIQUE($columnFavUserId, $columnFavSectionId, $columnFavQuestionNum)
      )
    ''');
  }
  if (oldVersion < 4) {
    await KeywordDatabase.ensureSchema(db);
  }
}
```

After all existing user-table `CREATE TABLE IF NOT EXISTS` and column checks complete, call:

```dart
await KeywordDatabase.syncBundledIfNeeded(_db!);
```

Catch and log dictionary sync errors at this boundary so the normal quiz database remains available.

- [ ] **Step 5: Run migration tests and static analysis**

```powershell
flutter test test\database\keyword_database_test.dart
flutter analyze lib\database\keyword_database.dart lib\database\database_helper.dart
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the migration layer**

```powershell
git add -- lib/database/keyword_database.dart lib/database/database_helper.dart test/database/keyword_database_test.dart
git commit -m "feat: sync bundled dictionary on database upgrade"
```

### Task 6: Add Keyword Models and SQLite Repository

**Files:**
- Create: `lib/models/keyword_model.dart`
- Modify: `lib/models/question_model.dart`
- Create: `lib/Services/keyword_repository.dart`
- Modify: `lib/database/database_helper.dart`
- Create: `test/models/keyword_model_test.dart`
- Create: `test/Services/keyword_repository_test.dart`

**Interfaces:**
- Produces: `Question.id: int`.
- Produces: immutable `Keyword`, `KeywordForm`, `KeywordExample`, and `KeywordMatch` classes.
- Produces: `KeywordRepository.all()`, `search(String)`, `byId(int)`, `forms()`, `exampleFor(int)`, and `dictionaryVersion()`.

- [ ] **Step 1: Write model mapping tests**

```dart
test('Question.fromMap keeps quiz id', () {
  final question = Question.fromMap({
    'id': 42,
    'section_id': 3,
    'question_number': 8,
    'question': 'Test',
    'translation': '测试',
    'explanation': '解析',
  });
  expect(question.id, 42);
  expect(question.toMap()['id'], 42);
});

test('Keyword.fromMap maps required fields', () {
  final keyword = Keyword.fromMap(keywordRow(id: 7));
  expect(keyword.id, 7);
  expect(keyword.term, 'precedenza');
});
```

- [ ] **Step 2: Run model tests and observe failure**

Run: `flutter test test/models/keyword_model_test.dart`

Expected: FAIL because the new model and `Question.id` are missing.

- [ ] **Step 3: Implement immutable models**

```dart
class Keyword {
  const Keyword({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.partOfSpeech,
    required this.translation,
    required this.note,
    required this.frequency,
    required this.sortOrder,
  });

  final int id;
  final String term;
  final String normalizedTerm;
  final String partOfSpeech;
  final String translation;
  final String note;
  final int frequency;
  final int sortOrder;

  factory Keyword.fromMap(Map<String, Object?> row) => Keyword(
    id: row['id'] as int,
    term: row['term'] as String,
    normalizedTerm: row['normalized_term'] as String,
    partOfSpeech: row['part_of_speech'] as String,
    translation: row['translation'] as String,
    note: row['note'] as String? ?? '',
    frequency: row['frequency'] as int? ?? 0,
    sortOrder: row['sort_order'] as int? ?? 0,
  );
}
```

Add the other three value objects with typed fields and `fromMap` factories. Add required `id` handling to `Question` without renaming existing fields.

- [ ] **Step 4: Write repository tests against an in-memory database**

```dart
test('search matches canonical term, form and Chinese translation', () async {
  final repository = KeywordRepository(databaseProvider: () async => db);
  expect((await repository.search('precedenza')).single.id, 1);
  expect((await repository.search('dà precedenza')).single.id, 1);
  expect((await repository.search('优先权')).single.id, 1);
});
```

- [ ] **Step 5: Implement query methods and repository**

Use bound parameters for every user query. The search query must join forms only for matching and return distinct dictionary rows:

```sql
SELECT DISTINCT k.*
FROM keyword_dictionary k
LEFT JOIN keyword_forms f ON f.keyword_id = k.id
WHERE k.normalized_term LIKE ?
   OR f.normalized_form LIKE ?
   OR k.translation LIKE ?
ORDER BY k.sort_order, k.frequency DESC, k.term
```

Escape `%` and `_` in user input and add `ESCAPE '\'`; an empty trimmed query delegates to `all()`.

The default constructor uses `DatabaseHelper.instance.database`; a named `databaseProvider` parameter permits in-memory tests. `dictionaryVersion()` reads `dictionary_meta.value` for key `version` and returns `0` when absent.

`exampleFor` must reuse the existing bilingual question text:

```sql
SELECT q.id AS question_id, q.question, q.translation
FROM keyword_examples e
INNER JOIN quiz q ON q.id = e.question_id
WHERE e.keyword_id = ?
ORDER BY e.rank, e.id
LIMIT 1
```

- [ ] **Step 6: Run tests and analysis**

```powershell
flutter test test\models\keyword_model_test.dart test\Services\keyword_repository_test.dart
flutter analyze lib\models\question_model.dart lib\models\keyword_model.dart lib\Services\keyword_repository.dart
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit models and repository**

```powershell
git add -- lib/models/question_model.dart lib/models/keyword_model.dart lib/Services/keyword_repository.dart lib/database/database_helper.dart test/models/keyword_model_test.dart test/Services/keyword_repository_test.dart
git commit -m "feat: query offline dictionary entries"
```

### Task 7: Implement Longest Italian Keyword Matching

**Files:**
- Create: `lib/Services/keyword_matcher.dart`
- Create: `lib/Services/keyword_service.dart`
- Create: `test/Services/keyword_matcher_test.dart`
- Create: `test/Services/keyword_service_test.dart`

**Interfaces:**
- Consumes: `List<KeywordForm>` plus a `Map<int, Keyword>`.
- Produces: `List<KeywordMatch> match({required int questionId, required String text, required int dictionaryVersion})`.
- Produces: `void clearCache()`.
- Produces: `KeywordLookup.matchQuestion({required int questionId, required String text})` and `KeywordLookup.keywordById(int id)`.
- Produces singleton `KeywordService.instance`, backed by `KeywordRepository` and `KeywordMatcher`.

- [ ] **Step 1: Write matcher behavior tests**

```dart
test('longest fixed phrase wins and partial words do not match', () {
  final matcher = matcherWithForms(['dare', 'precedenza', 'dare precedenza']);
  final matches = matcher.match(questionId: 1, text: 'Deve dare precedenza.', dictionaryVersion: 1);
  expect(matches.map((item) => item.matchedText), ['dare precedenza']);
  expect(matcher.match(questionId: 2, text: 'imprecedenza', dictionaryVersion: 1), isEmpty);
});

test('matching ignores case and normalizes curly apostrophes', () {
  final matcher = matcherWithForms(["l'autovettura"]);
  final match = matcher.match(questionId: 3, text: 'L’AUTOVETTURA rallenta.', dictionaryVersion: 1).single;
  expect(match.matchedText, 'L’AUTOVETTURA');
});
```

- [ ] **Step 2: Run matcher tests and observe failure**

Run: `flutter test test/Services/keyword_matcher_test.dart`

Expected: FAIL because `KeywordMatcher` is missing.

- [ ] **Step 3: Implement length-preserving normalization and boundary checks**

```dart
String normalizeForMatch(String value) => value.toLowerCase().replaceAll('’', "'");

bool isItalianLetter(String value, int index) {
  if (index < 0 || index >= value.length) return false;
  return RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(value[index]);
}

bool hasBoundaries(String text, int start, int end) =>
    !isItalianLetter(text, start - 1) && !isItalianLetter(text, end);
```

Sort forms by descending normalized length, then dictionary order. Find all occurrences, reject invalid boundaries and overlaps, restore ascending source offsets, and cache by `(questionId, dictionaryVersion, text)`.

- [ ] **Step 4: Run matcher tests**

Run: `flutter test test/Services/keyword_matcher_test.dart`

Expected: PASS for fixed phrases, overlaps, accents, apostrophes, punctuation, case, and cache invalidation.

- [ ] **Step 5: Add and test the lazy-loading service facade**

```dart
abstract interface class KeywordLookup {
  Future<List<KeywordMatch>> matchQuestion({
    required int questionId,
    required String text,
  });

  Future<Keyword?> keywordById(int id);
}

class KeywordService implements KeywordLookup {
  KeywordService({required KeywordRepository repository}) : _repository = repository;

  static final instance = KeywordService(repository: KeywordRepository());

  final KeywordRepository _repository;
  KeywordMatcher? _matcher;
  int _dictionaryVersion = 0;

  Future<void> _load() async {
    final version = await _repository.dictionaryVersion();
    if (_matcher != null && version == _dictionaryVersion) return;
    final keywords = await _repository.all();
    final forms = await _repository.forms();
    _matcher = KeywordMatcher(
      keywords: {for (final keyword in keywords) keyword.id: keyword},
      forms: forms,
    );
    _dictionaryVersion = version;
  }

  @override
  Future<List<KeywordMatch>> matchQuestion({required int questionId, required String text}) async {
    await _load();
    return _matcher!.match(
      questionId: questionId,
      text: text,
      dictionaryVersion: _dictionaryVersion,
    );
  }

  @override
  Future<Keyword?> keywordById(int id) => _repository.byId(id);
}
```

Test that two matches at the same dictionary version call repository `all()` and `forms()` once, and that increasing the fake repository version reloads both datasets and invalidates old matcher results.

- [ ] **Step 6: Run service and matcher tests**

Run: `flutter test test/Services/keyword_matcher_test.dart test/Services/keyword_service_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit the matcher and facade**

```powershell
git add -- lib/Services/keyword_matcher.dart lib/Services/keyword_service.dart test/Services/keyword_matcher_test.dart test/Services/keyword_service_test.dart
git commit -m "feat: match Italian driving keywords"
```

### Task 8: Add the Observable Toggle and Tappable Question Text

**Files:**
- Create: `lib/Services/keyword_translation_settings.dart`
- Create: `lib/widgets/keyword_question_text.dart`
- Create: `lib/widgets/keyword_definition_sheet.dart`
- Modify: `lib/main.dart`
- Modify: `lib/Screen/General/settings_screen.dart`
- Create: `test/Services/keyword_translation_settings_test.dart`
- Create: `test/widgets/keyword_question_text_test.dart`

**Interfaces:**
- Produces singleton `KeywordTranslationSettings.instance` with `ValueNotifier<bool> enabled`, `load()`, and `setEnabled(bool)`.
- Produces `KeywordQuestionText(questionId, text, style, prefix, KeywordLookup? service)`; production defaults to `KeywordService.instance`.
- Produces `showKeywordDefinitionSheet(BuildContext, Keyword)`.

- [ ] **Step 1: Write preference default and persistence tests**

```dart
test('keyword translation defaults on and persists changes', () async {
  SharedPreferences.setMockInitialValues({});
  final settings = KeywordTranslationSettings.forTest();
  await settings.load();
  expect(settings.enabled.value, isTrue);
  await settings.setEnabled(false);
  expect((await SharedPreferences.getInstance()).getBool('keywordTranslationEnabled'), isFalse);
});
```

- [ ] **Step 2: Implement observable settings and add the Settings switch**

```dart
static const preferenceKey = 'keywordTranslationEnabled';

Future<void> load() async {
  final prefs = await SharedPreferences.getInstance();
  enabled.value = prefs.getBool(preferenceKey) ?? true;
}

Future<void> setEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(preferenceKey, value);
  enabled.value = value;
}
```

Place a `SwitchListTile` titled `题目关键词翻译` near the existing translation and explanation settings. Its subtitle is `在意大利语题目中划线显示可点击词条`.

Before `runApp` in `main.dart`, restore the persisted setting once:

```dart
await KeywordTranslationSettings.instance.load();
runApp(const MyApp());
```

- [ ] **Step 3: Write widget tests for enabled, disabled, and tap states**

```dart
testWidgets('underlines matches and opens the definition sheet', (tester) async {
  await tester.pumpWidget(testApp(
    KeywordQuestionText(questionId: 1, text: 'Dare precedenza', service: fakeService),
  ));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('keyword-precedenza')), findsOneWidget);
  await tester.tap(find.byKey(const Key('keyword-precedenza')));
  await tester.pumpAndSettle();
  expect(find.text('优先权；先行权'), findsOneWidget);
});
```

Add a second test that disables the notifier and expects no keyword keys and no gesture recognizers.

- [ ] **Step 4: Implement annotated text and the definition sheet**

Build a `Text.rich` from non-overlapping `TextSpan` ranges. Keyword spans use the inherited text style plus `decoration: TextDecoration.underline`, `decorationStyle: TextDecorationStyle.dotted`, and teal decoration color. Attach a `TapGestureRecognizer` and dispose every recognizer when spans change or the widget is removed.

The bottom sheet shows the matched form, canonical term, part of speech, short translation, and a `查看完整词条` button. It must not change navigation state until that button is pressed.

- [ ] **Step 5: Run settings and widget tests**

```powershell
flutter test test\Services\keyword_translation_settings_test.dart test\widgets\keyword_question_text_test.dart
flutter analyze lib\main.dart lib\Services\keyword_translation_settings.dart lib\widgets\keyword_question_text.dart lib\widgets\keyword_definition_sheet.dart lib\Screen\General\settings_screen.dart
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit toggle and shared widgets**

```powershell
git add -- lib/main.dart lib/Services/keyword_translation_settings.dart lib/widgets/keyword_question_text.dart lib/widgets/keyword_definition_sheet.dart lib/Screen/General/settings_screen.dart test/Services/keyword_translation_settings_test.dart test/widgets/keyword_question_text_test.dart
git commit -m "feat: add tappable keyword annotations"
```

### Task 9: Build the Standalone Dictionary Experience

**Files:**
- Create: `lib/Screen/General/dictionary_screen.dart`
- Create: `lib/Screen/General/dictionary_detail_screen.dart`
- Modify: `lib/Screen/Homepage.dart`
- Create: `test/Screen/General/dictionary_screen_test.dart`

**Interfaces:**
- Consumes: `KeywordRepository.search`, `byId`, `forms`, and `exampleFor`.
- Produces: `DictionaryScreen(repository)` and `DictionaryDetailScreen(keywordId, repository)`.

- [ ] **Step 1: Write list/search/detail widget tests**

```dart
testWidgets('searches in Italian and opens a complete entry', (tester) async {
  await tester.pumpWidget(testApp(DictionaryScreen(repository: fakeRepository)));
  await tester.enterText(find.byType(SearchBar), 'precedenza');
  await tester.pumpAndSettle();
  expect(find.text('precedenza'), findsOneWidget);
  await tester.tap(find.text('precedenza'));
  await tester.pumpAndSettle();
  expect(find.text('常见词形与搭配'), findsOneWidget);
  expect(find.textContaining('例句'), findsOneWidget);
});
```

Add tests for Chinese search and the `未找到相关词条` state.

- [ ] **Step 2: Implement the dictionary list**

Use an app bar titled `驾考词典`, one fixed search control, and an unframed list. Debounce input by 200 ms, cancel the timer in `dispose`, and ignore stale async results with a monotonically increasing request id. Each row shows term, part of speech, and a one-line Chinese translation.

- [ ] **Step 3: Implement the detail screen**

Load entry, forms, and example together with `Future.wait`. Show the canonical term, part of speech, full translation, note, chips for forms, and the linked question plus its existing translation. The loading, error, and missing-example states must preserve the page scaffold.

- [ ] **Step 4: Add the home entry and route**

Add a fourth `generalItems` entry in `Homepage.dart`:

```dart
MenuItem(
  icon: const Icon(Icons.translate),
  label: '驾考词典',
  color: Colors.blue,
),
```

Map `驾考词典` to `DictionaryScreen()` in `_getScreenByName` and change the general grid to a responsive two-column layout so four items remain balanced without narrow text.

- [ ] **Step 5: Run UI tests and analysis**

```powershell
flutter test test\Screen\General\dictionary_screen_test.dart
flutter analyze lib\Screen\General\dictionary_screen.dart lib\Screen\General\dictionary_detail_screen.dart lib\Screen\Homepage.dart
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit dictionary UI**

```powershell
git add -- lib/Screen/General/dictionary_screen.dart lib/Screen/General/dictionary_detail_screen.dart lib/Screen/Homepage.dart test/Screen/General/dictionary_screen_test.dart
git commit -m "feat: add offline driving dictionary screens"
```

### Task 10: Cover Every Existing Question Surface

**Files:**
- Modify: `lib/Screen/General/exam_general.dart`
- Modify: `lib/Screen/General/question_list_screen.dart`
- Modify: `lib/Screen/General/favorites_screen.dart`
- Modify: `lib/Screen/General/wrong_review_screen.dart`
- Modify: `lib/Screen/General/history_detail_screen.dart`
- Modify: `lib/Screen/General/final_score.dart`
- Modify: `lib/Screen/DEBUG/quiz_actions.dart`
- Create: `test/widgets/question_surface_coverage_test.dart`

**Interfaces:**
- Consumes: `KeywordQuestionText` and stable `quiz.id`.
- Produces: one consistent annotation behavior everywhere Italian question text appears.

- [ ] **Step 1: Add a source-coverage test**

```dart
test('every production question surface imports KeywordQuestionText', () {
  const files = [
    'lib/Screen/General/exam_general.dart',
    'lib/Screen/General/question_list_screen.dart',
    'lib/Screen/General/favorites_screen.dart',
    'lib/Screen/General/wrong_review_screen.dart',
    'lib/Screen/General/history_detail_screen.dart',
    'lib/Screen/General/final_score.dart',
    'lib/Screen/DEBUG/quiz_actions.dart',
  ];
  for (final path in files) {
    expect(File(path).readAsStringSync(), contains('KeywordQuestionText('), reason: path);
  }
});
```

- [ ] **Step 2: Replace raw question `Text` widgets**

For typed questions, pass `question.id` and `question.question`. For map-backed rows, pass `(item['id'] as num).toInt()` and `item['question'] as String`. Preserve the existing prefix (`Qn:` or `题目 n:`) using the widget's separate `prefix` parameter so only Italian source text is matched.

Do not wrap translations, explanations, answer labels, section names, or question numbers in the keyword component.

- [ ] **Step 3: Make all database queries retain `q.id`**

Inspect every query feeding the seven files. Existing `q.*` and `SELECT *` queries already retain id; add `q.id AS id` only to explicit projections that omit it. Extend tests for `Question.fromMap` and map-backed pages to fail clearly if id is absent.

- [ ] **Step 4: Run coverage and focused widget tests**

```powershell
flutter test test\widgets\question_surface_coverage_test.dart test\widgets\keyword_question_text_test.dart
flutter analyze lib\Screen\General lib\Screen\DEBUG\quiz_actions.dart
```

Expected: both commands exit 0; source scan finds no remaining raw Italian question rendering in those files.

- [ ] **Step 5: Commit all surface integrations**

```powershell
git add -- lib/Screen/General/exam_general.dart lib/Screen/General/question_list_screen.dart lib/Screen/General/favorites_screen.dart lib/Screen/General/wrong_review_screen.dart lib/Screen/General/history_detail_screen.dart lib/Screen/General/final_score.dart lib/Screen/DEBUG/quiz_actions.dart test/widgets/question_surface_coverage_test.dart
git commit -m "feat: annotate keywords on every question screen"
```

### Task 11: End-to-End Dictionary Verification

**Files:**
- Modify only if verification finds a defect: files owned by Tasks 1 through 10.
- Create during execution, do not stage: `tools/keywords/work/final-protected.json`

**Interfaces:**
- Consumes all dictionary work.
- Produces verification evidence for data integrity, behavior, and layout.

- [ ] **Step 1: Run all automated checks**

```powershell
python -m unittest discover tools\keywords\tests -v
python tools\keywords\verify_protected_tables.py assets\db\quiz.db --compare tools\keywords\work\protected-baseline.json
sqlite3 assets\db\quiz.db "PRAGMA integrity_check; SELECT COUNT(*) FROM keyword_dictionary; SELECT COUNT(*) FROM keyword_forms; SELECT COUNT(*) FROM keyword_examples;"
flutter test
flutter analyze
```

Expected: every command exits 0; SQLite integrity is `ok`; protected tables match; dictionary count remains within 500 to 800.

- [ ] **Step 2: Start the web app for visual testing**

Run: `flutter run -d web-server --web-port 64112`

Expected: the server reports `http://localhost:64112/`. Keep the process running only while visual checks are active.

- [ ] **Step 3: Verify desktop and mobile layouts in the browser**

At 1280x800 and 390x844, inspect and capture:

- Home screen with the balanced four-item general grid.
- Dictionary default list, Italian search, Chinese search, detail, and empty result.
- A long no-image question with multiple keyword underlines.
- A picture question with underlines, image, translation, explanation, and answer controls visible without overlap.
- The same question after disabling `题目关键词翻译`, with ordinary text and no tap response.

Expected: no overflow, overlap, layout jump, clipped text, or inaccessible tap target.

- [ ] **Step 4: Confirm the final diff is scoped**

```powershell
git status --short
git diff --stat HEAD~10..HEAD
git diff --check HEAD~10..HEAD
```

Expected: only dictionary-owned source, tests, tools, and `assets/db/quiz.db` are part of these commits; unrelated generated plugin files remain unstaged.
