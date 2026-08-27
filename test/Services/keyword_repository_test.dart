import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Services/keyword_repository.dart';
import 'package:italian_driving_app/models/keyword_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late KeywordRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await _createExactSchema(db);
    await _insertFixture(db);
    repository = KeywordRepository(databaseProvider: () async => db);
  });

  tearDown(() async {
    await db.close();
  });

  test('all follows dictionary order, frequency, then term', () async {
    expect((await repository.all()).map((item) => item.id), [3, 2, 5, 4, 1]);
  });

  test('byId returns the requested entry and null when it is missing',
      () async {
    expect((await repository.byId(1))?.term, 'precedenza');
    expect(await repository.byId(999), isNull);
  });

  test('forms excludes orphans and is deterministic longest-first', () async {
    final forms = await repository.forms();

    expect(
      forms.map((item) => item.normalizedForm),
      [
        'percentuale 100%',
        'dare precedenza',
        'dà precedenza',
        "l'autovettura",
        r'barra\strada',
        'precedenza',
        'velocità',
        'quota_1',
      ],
    );
    expect(forms.any((item) => item.keywordId == 999), isFalse);
  });

  test('exampleFor joins the real quiz row by rank and id', () async {
    expect(
      await repository.exampleFor(1),
      const KeywordExample(
        questionId: 147,
        question: 'La precedenza spetta al veicolo.',
        translation: '车辆享有优先权。',
      ),
    );
  });

  test('exampleFor returns null for missing keyword or missing quiz row',
      () async {
    expect(await repository.exampleFor(2), isNull);
    expect(await repository.exampleFor(999), isNull);
  });

  test('dictionaryVersion parses valid values', () async {
    expect(await repository.dictionaryVersion(), 12);
  });

  test('dictionaryVersion returns zero when missing or malformed', () async {
    await db
        .delete('dictionary_meta', where: 'key = ?', whereArgs: ['version']);
    expect(await repository.dictionaryVersion(), 0);

    await db.insert('dictionary_meta', {'key': 'version', 'value': 'v12'});
    expect(await repository.dictionaryVersion(), 0);

    await db.update(
      'dictionary_meta',
      {'value': '-1'},
      where: 'key = ?',
      whereArgs: ['version'],
    );
    expect(await repository.dictionaryVersion(), 0);
  });

  test('search matches canonical term, form and Chinese translation', () async {
    expect((await repository.search('precedenza')).single.id, 1);
    expect((await repository.search('dà precedenza')).single.id, 1);
    expect((await repository.search('优先权')).single.id, 1);
  });

  test('search trims and normalizes Unicode case and curly apostrophes',
      () async {
    expect((await repository.search('  VELOCITÀ  ')).single.id, 5);
    expect((await repository.search(' L’AUTOVETTURA ')).single.id, 4);
  });

  test('search treats percent, underscore and backslash literally', () async {
    expect((await repository.search('%')).map((item) => item.id), [2]);
    expect((await repository.search('_')).map((item) => item.id), [2]);
    expect((await repository.search(r'\')).map((item) => item.id), [3]);
  });

  test('search binds quotes rather than interpreting them as SQL', () async {
    expect(await repository.search("' OR 1=1 --"), isEmpty);
    expect((await repository.search("l'autovettura")).single.id, 4);
  });

  test('empty trimmed search delegates to the complete ordered list', () async {
    expect(
      await repository.search(' \t\n '),
      await repository.all(),
    );
  });

  test('search returns distinct entries and preserves dictionary sorting',
      () async {
    expect((await repository.search('precedenza')).map((item) => item.id), [1]);
    expect(
      (await repository.search('词条')).map((item) => item.id),
      [3, 2, 5, 4, 1],
    );
  });
}

Future<void> _createExactSchema(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE quiz (
      id INTEGER,
      question TEXT,
      answer INTEGER,
      section_id INTEGER,
      translation TEXT,
      explanation TEXT,
      question_number INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE keyword_dictionary (
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
    CREATE TABLE keyword_forms (
      id INTEGER PRIMARY KEY,
      keyword_id INTEGER NOT NULL,
      form TEXT NOT NULL,
      normalized_form TEXT NOT NULL UNIQUE,
      FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE keyword_examples (
      id INTEGER PRIMARY KEY,
      keyword_id INTEGER NOT NULL,
      question_id INTEGER NOT NULL,
      rank INTEGER NOT NULL DEFAULT 0,
      UNIQUE(keyword_id, question_id),
      FOREIGN KEY (keyword_id) REFERENCES keyword_dictionary(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE dictionary_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_keyword_forms_keyword_id '
    'ON keyword_forms(keyword_id)',
  );
  await db.execute(
    'CREATE INDEX idx_keyword_examples_keyword_rank '
    'ON keyword_examples(keyword_id, rank)',
  );
  await db.execute(
    'CREATE INDEX idx_keyword_examples_question_id '
    'ON keyword_examples(question_id)',
  );
}

Future<void> _insertFixture(Database db) async {
  final keywords = [
    _keywordRow(
      id: 1,
      term: 'precedenza',
      translation: '词条：优先权',
      frequency: 100,
      sortOrder: 2,
    ),
    _keywordRow(
      id: 2,
      term: 'percentuale 100%',
      translation: '词条：100%',
      frequency: 10,
      sortOrder: 1,
    ),
    _keywordRow(
      id: 3,
      term: r'barra\strada',
      translation: '词条：反斜杠',
      frequency: 20,
      sortOrder: 1,
    ),
    _keywordRow(
      id: 4,
      term: 'autovettura',
      translation: '词条：汽车',
      frequency: 100,
      sortOrder: 2,
    ),
    _keywordRow(
      id: 5,
      term: 'velocità',
      translation: '词条：速度',
      frequency: 200,
      sortOrder: 2,
    ),
  ];
  for (final row in keywords) {
    await db.insert('keyword_dictionary', row);
  }

  final forms = [
    _formRow(1, 1, 'dare precedenza'),
    _formRow(2, 2, 'percentuale 100%'),
    _formRow(3, 1, 'dà precedenza'),
    _formRow(4, 3, r'barra\strada'),
    _formRow(5, 4, "l'autovettura"),
    _formRow(6, 1, 'precedenza'),
    _formRow(7, 5, 'velocità'),
    _formRow(8, 2, 'quota_1'),
  ];
  for (final row in forms) {
    await db.insert('keyword_forms', row);
  }

  await db.insert('quiz', {
    'id': 146,
    'question': 'Bisogna dare precedenza.',
    'translation': '必须让行。',
  });
  await db.insert('quiz', {
    'id': 147,
    'question': 'La precedenza spetta al veicolo.',
    'translation': '车辆享有优先权。',
  });
  await db.insert('keyword_examples', {
    'id': 1,
    'keyword_id': 1,
    'question_id': 146,
    'rank': 1,
  });
  await db.insert('keyword_examples', {
    'id': 2,
    'keyword_id': 1,
    'question_id': 147,
    'rank': 0,
  });
  await db.insert('keyword_examples', {
    'id': 3,
    'keyword_id': 2,
    'question_id': 999,
    'rank': 0,
  });
  await db.insert('dictionary_meta', {'key': 'version', 'value': '12'});

  await db.execute('PRAGMA foreign_keys = OFF');
  await db.insert('keyword_forms', {
    'id': 999,
    'keyword_id': 999,
    'form': 'lunghissima forma isolata',
    'normalized_form': 'lunghissima forma isolata',
  });
  await db.execute('PRAGMA foreign_keys = ON');
}

Map<String, Object?> _keywordRow({
  required int id,
  required String term,
  required String translation,
  required int frequency,
  required int sortOrder,
}) =>
    {
      'id': id,
      'term': term,
      'normalized_term': term.toLowerCase(),
      'part_of_speech': 'nome',
      'translation': translation,
      'note': 'nota $id',
      'frequency': frequency,
      'sort_order': sortOrder,
    };

Map<String, Object?> _formRow(int id, int keywordId, String form) => {
      'id': id,
      'keyword_id': keywordId,
      'form': form,
      'normalized_form': form.toLowerCase(),
    };
