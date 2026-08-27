import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/database/keyword_database.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database target;
  late Database seed;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    target = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    seed = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  });

  tearDown(() async {
    await target.close();
    await seed.close();
  });

  test('syncFrom copies dictionary rows and preserves user rows', () async {
    await target.execute(
      'CREATE TABLE favorites (id INTEGER PRIMARY KEY, note TEXT)',
    );
    await target.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)',
    );
    await target.execute(
      'CREATE TABLE quiz_history (id INTEGER PRIMARY KEY, score INTEGER)',
    );
    await target.execute(
      'CREATE TABLE quiz (id INTEGER PRIMARY KEY, question TEXT)',
    );
    await target.insert('favorites', {'id': 7, 'note': 'keep'});
    await target.insert('users', {'id': 8, 'name': 'user'});
    await target.insert('quiz_history', {'id': 9, 'score': 10});
    await target.insert('quiz', {'id': 42, 'question': 'keep question'});
    await KeywordDatabase.ensureSchema(seed);
    await seed.insert('keyword_dictionary', _keywordRow(1, 'precedenza'));
    await seed.insert('keyword_forms', _formRow(1, 1, 'precedenza'));
    await seed.insert('keyword_examples', _exampleRow(1, 1, 42));
    await seed.insert('dictionary_meta', {'key': 'version', 'value': '1'});

    expect(
      await KeywordDatabase.syncFrom(target: target, seed: seed),
      isTrue,
    );
    expect(await target.query('favorites'), [
      {'id': 7, 'note': 'keep'},
    ]);
    expect(await target.query('users'), [
      {'id': 8, 'name': 'user'},
    ]);
    expect(await target.query('quiz_history'), [
      {'id': 9, 'score': 10},
    ]);
    expect(await target.query('quiz'), [
      {'id': 42, 'question': 'keep question'},
    ]);
    expect(await target.query('keyword_dictionary'), hasLength(1));
  });

  test('ensureSchema exactly matches the asset schema and is idempotent',
      () async {
    await KeywordDatabase.ensureSchema(target);
    final first = await _schemaState(target);

    await KeywordDatabase.ensureSchema(target);

    expect(await _schemaState(target), first);
    expect(await _foreignKeysEnabled(target), 1);
    expect(first, _expectedSchemaState);
  });

  test('syncFrom upgrades a target with no dictionary version', () async {
    await KeywordDatabase.ensureSchema(target);
    await _installDictionary(seed, version: 1, id: 1, term: 'nuovo');

    expect(
      await KeywordDatabase.syncFrom(target: target, seed: seed),
      isTrue,
    );
    expect(await _dictionaryVersion(target), 1);
    expect(
      await target.query('keyword_dictionary', columns: ['term']),
      [
        {'term': 'nuovo'},
      ],
    );
  });

  test('syncFrom skips equal and newer target versions', () async {
    for (final targetVersion in [2, 3]) {
      await _clearDictionary(target);
      await _clearDictionary(seed);
      await _installDictionary(
        target,
        version: targetVersion,
        id: 1,
        term: 'target-$targetVersion',
      );
      await _installDictionary(seed, version: 2, id: 2, term: 'seed');
      final before = await _completeDictionaryState(target);

      expect(
        await KeywordDatabase.syncFrom(target: target, seed: seed),
        isFalse,
      );
      expect(await _completeDictionaryState(target), before);
    }
  });

  test('syncFrom skips missing and malformed seed versions', () async {
    await _installDictionary(target, version: 1, id: 1, term: 'target');
    final targetBefore = await _completeDictionaryState(target);

    await KeywordDatabase.ensureSchema(seed);
    await seed.insert('keyword_dictionary', _keywordRow(2, 'seed'));
    await seed.insert('keyword_forms', _formRow(2, 2, 'seed'));
    await seed.insert('keyword_examples', _exampleRow(2, 2, 2));
    expect(
      await KeywordDatabase.syncFrom(target: target, seed: seed),
      isFalse,
    );
    expect(await _completeDictionaryState(target), targetBefore);

    await seed.insert(
      'dictionary_meta',
      {'key': 'version', 'value': 'not-an-integer'},
    );
    expect(
      await KeywordDatabase.syncFrom(target: target, seed: seed),
      isFalse,
    );
    expect(await _completeDictionaryState(target), targetBefore);
  });

  test('syncFrom rejects an empty newer seed before deleting target rows',
      () async {
    await _installDictionary(target, version: 1, id: 1, term: 'target');
    await KeywordDatabase.ensureSchema(seed);
    await seed.insert('dictionary_meta', {'key': 'version', 'value': '2'});
    final before = await _completeDictionaryState(target);

    await expectLater(
      KeywordDatabase.syncFrom(target: target, seed: seed),
      throwsA(isA<StateError>()),
    );
    expect(await _completeDictionaryState(target), before);
  });

  test('syncFrom rejects a newer seed missing a required table', () async {
    await _installDictionary(target, version: 1, id: 1, term: 'target');
    await seed.execute(
      'CREATE TABLE dictionary_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await seed.insert('dictionary_meta', {'key': 'version', 'value': '2'});
    final before = await _completeDictionaryState(target);

    await expectLater(
      KeywordDatabase.syncFrom(target: target, seed: seed),
      throwsA(isA<StateError>()),
    );
    expect(await _completeDictionaryState(target), before);
  });

  test('syncFrom rejects orphan form and example references', () async {
    for (final orphanTable in ['keyword_forms', 'keyword_examples']) {
      await _clearDictionary(seed);
      await _clearDictionary(target);
      await _installDictionary(target, version: 1, id: 1, term: 'target');
      await KeywordDatabase.ensureSchema(seed);
      await seed.execute('PRAGMA foreign_keys = OFF');
      await seed.insert('keyword_dictionary', _keywordRow(2, 'seed'));
      if (orphanTable == 'keyword_forms') {
        await seed.insert('keyword_forms', _formRow(2, 999, 'orphan'));
        await seed.insert('keyword_examples', _exampleRow(2, 2, 2));
      } else {
        await seed.insert('keyword_forms', _formRow(2, 2, 'seed'));
        await seed.insert('keyword_examples', _exampleRow(2, 999, 2));
      }
      await seed.insert('dictionary_meta', {'key': 'version', 'value': '2'});
      final before = await _completeDictionaryState(target);

      await expectLater(
        KeywordDatabase.syncFrom(target: target, seed: seed),
        throwsA(isA<StateError>()),
      );
      expect(await _completeDictionaryState(target), before);
    }
  });

  test('syncFrom rolls back dictionary meta and user rows on insert failure',
      () async {
    await _installDictionary(target, version: 1, id: 1, term: 'target');
    await target.insert(
      'dictionary_meta',
      {'key': 'custom', 'value': 'keep'},
    );
    await target.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)',
    );
    await target.insert('users', {'id': 7, 'name': 'keep'});
    await target.execute('''
      CREATE TRIGGER reject_seed_form
      BEFORE INSERT ON keyword_forms
      WHEN NEW.normalized_form = 'seed'
      BEGIN
        SELECT RAISE(FAIL, 'forced form failure');
      END
    ''');
    await _installDictionary(seed, version: 2, id: 2, term: 'seed');
    final targetBefore = await _completeDictionaryState(target);
    final usersBefore = await target.query('users');
    final seedBefore = await _completeDictionaryState(seed);

    await expectLater(
      KeywordDatabase.syncFrom(target: target, seed: seed),
      throwsA(isA<DatabaseException>()),
    );

    expect(await _completeDictionaryState(target), targetBefore);
    expect(await target.query('users'), usersBefore);
    expect(await _completeDictionaryState(seed), seedBefore);
  });

  test('syncFrom leaves seed maps unchanged and repeated sync is stable',
      () async {
    await _installDictionary(seed, version: 2, id: 2, term: 'seed');
    final seedBefore = await _completeDictionaryState(seed);

    expect(
      await KeywordDatabase.syncFrom(target: target, seed: seed),
      isTrue,
    );
    final targetAfterFirst = await _completeDictionaryState(target);
    expect(await _completeDictionaryState(seed), seedBefore);

    expect(
      await KeywordDatabase.syncFrom(target: target, seed: seed),
      isFalse,
    );
    expect(await _completeDictionaryState(target), targetAfterFirst);
    expect(await _completeDictionaryState(seed), seedBefore);
  });

  test('syncBundledIfNeeded copies the bundled v1 asset and cleans its seed',
      () async {
    await _withSupportDirectory((directory) async {
      await KeywordDatabase.syncBundledIfNeeded(target);

      expect(KeywordDatabase.bundledVersion, 1);
      expect(await _dictionaryVersion(target), 1);
      expect(
        Sqflite.firstIntValue(
          await target.rawQuery('SELECT COUNT(*) FROM keyword_dictionary'),
        ),
        631,
      );
      expect(_temporarySeedPaths(directory), isEmpty);
    });
  });

  test('syncBundledIfNeeded cleans its seed when target insertion fails',
      () async {
    await _installDictionary(target, version: 0, id: 9000, term: 'old');
    await target.execute('''
      CREATE TRIGGER reject_bundled_forms
      BEFORE INSERT ON keyword_forms
      BEGIN
        SELECT RAISE(FAIL, 'forced bundled failure');
      END
    ''');
    final before = await _completeDictionaryState(target);

    await _withSupportDirectory((directory) async {
      await expectLater(
        KeywordDatabase.syncBundledIfNeeded(target),
        throwsA(isA<DatabaseException>()),
      );
      expect(_temporarySeedPaths(directory), isEmpty);
    });
    expect(await _completeDictionaryState(target), before);
  });

  test('concurrent bundled syncs use distinct temporary seed paths', () async {
    final otherTarget = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(otherTarget.close);

    await _withSupportDirectory((directory) async {
      await Future.wait([
        KeywordDatabase.syncBundledIfNeeded(target),
        KeywordDatabase.syncBundledIfNeeded(otherTarget),
      ]);

      expect(await _dictionaryVersion(target), 1);
      expect(await _dictionaryVersion(otherTarget), 1);
      expect(_temporarySeedPaths(directory), isEmpty);
    });
  });

  test('DatabaseHelper initializes an existing empty database at version 4',
      () async {
    await _withSupportDirectory((directory) async {
      await DatabaseHelper.instance.close();
      await io.File(_mainDatabasePath(directory)).create();

      final db = await DatabaseHelper.instance.database;

      expect(await _userVersion(db), 4);
      expect(await _dictionaryVersion(db), 1);
      expect(await _tableExists(db, tableUsers), isTrue);
      expect(await _tableExists(db, 'keyword_dictionary'), isTrue);
      await DatabaseHelper.instance.close();
    });
  });

  test('DatabaseHelper asset-copy path opens populated v4 and user tables',
      () async {
    await _withSupportDirectory((directory) async {
      await DatabaseHelper.instance.close();

      final db = await DatabaseHelper.instance.database;

      expect(await _userVersion(db), 4);
      expect(await _dictionaryVersion(db), 1);
      expect(
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM quiz')),
        7193,
      );
      expect(await _tableExists(db, tableUsers), isTrue);
      expect(await io.File(_mainDatabasePath(directory)).exists(), isTrue);
      await DatabaseHelper.instance.close();
    });
  });

  test('DatabaseHelper upgrades v3 after repairs and preserves all user rows',
      () async {
    await _withSupportDirectory((directory) async {
      await DatabaseHelper.instance.close();
      final path = _mainDatabasePath(directory);
      final oldDb = await _openFileDatabase(path);
      await _createUserTables(oldDb);
      await oldDb.insert(tableUsers, {
        columnUserId: 1,
        columnUsername: 'keep-user',
      });
      await oldDb.insert(tableFavorites, {
        columnFavoriteId: 2,
        columnFavUserId: 1,
        columnFavSectionId: 3,
        columnFavQuestionNum: 4,
        columnFavNote: 'keep-favorite',
      });
      await oldDb.insert(tableQuizHistory, {
        columnHistoryId: 5,
        columnHistoryUserId: 1,
        columnHistoryScore: 9,
      });
      await oldDb.execute(
        'CREATE TABLE quiz (id INTEGER PRIMARY KEY, question TEXT)',
      );
      await oldDb.insert('quiz', {'id': 6, 'question': 'keep-quiz'});
      await oldDb.execute('PRAGMA user_version = 3');
      await oldDb.close();

      final db = await DatabaseHelper.instance.database;

      expect(await _userVersion(db), 4);
      expect(await _dictionaryVersion(db), 1);
      expect((await db.query(tableUsers)).single[columnUsername], 'keep-user');
      expect(
        (await db.query(tableFavorites)).single[columnFavNote],
        'keep-favorite',
      );
      expect(
        (await db.query(tableQuizHistory)).single[columnHistoryScore],
        9,
      );
      expect((await db.query('quiz')).single['question'], 'keep-quiz');
      await DatabaseHelper.instance.close();
    });
  });

  test('DatabaseHelper keeps the old v2 favorites migration semantics',
      () async {
    await _withSupportDirectory((directory) async {
      await DatabaseHelper.instance.close();
      final oldDb = await _openFileDatabase(_mainDatabasePath(directory));
      await _createUserTables(oldDb);
      await oldDb.insert(tableUsers, {
        columnUserId: 1,
        columnUsername: 'keep-user',
      });
      await oldDb.insert(tableFavorites, {
        columnFavoriteId: 2,
        columnFavUserId: 1,
        columnFavSectionId: 3,
        columnFavQuestionNum: 4,
        columnFavNote: 'legacy-favorite',
      });
      await oldDb.insert(tableQuizHistory, {
        columnHistoryId: 5,
        columnHistoryUserId: 1,
        columnHistoryScore: 9,
      });
      await oldDb.execute('PRAGMA user_version = 2');
      await oldDb.close();

      final db = await DatabaseHelper.instance.database;

      expect(await _userVersion(db), 4);
      expect(await db.query(tableFavorites), isEmpty);
      expect((await db.query(tableUsers)).single[columnUsername], 'keep-user');
      expect(
        (await db.query(tableQuizHistory)).single[columnHistoryScore],
        9,
      );
      final favoriteColumns = (await db.rawQuery(
        'PRAGMA table_info($tableFavorites)',
      ))
          .map((row) => row['name'])
          .toSet();
      expect(
        favoriteColumns,
        containsAll([columnFavIsDeleted, columnFavUpdatedAt]),
      );
      await DatabaseHelper.instance.close();
    });
  });

  test('DatabaseHelper contains bundled sync failure without leaking paths',
      () async {
    await _withSupportDirectory((directory) async {
      await DatabaseHelper.instance.close();
      final oldDb = await _openFileDatabase(_mainDatabasePath(directory));
      await _createUserTables(oldDb);
      await oldDb.insert(tableUsers, {
        columnUserId: 1,
        columnUsername: 'keep-user',
      });
      await _installDictionary(oldDb, version: 0, id: 9000, term: 'old');
      await oldDb.execute('''
        CREATE TRIGGER reject_bundled_forms
        BEFORE INSERT ON keyword_forms
        BEGIN
          SELECT RAISE(FAIL, 'forced bundled failure');
        END
      ''');
      await oldDb.execute('PRAGMA user_version = 3');
      await oldDb.close();
      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };
      try {
        final db = await DatabaseHelper.instance.database;

        expect(
            (await db.query(tableUsers)).single[columnUsername], 'keep-user');
        expect(await _dictionaryVersion(db), 0);
        expect(
          (await db.query('keyword_dictionary')).single['term'],
          'old',
        );
        expect(messages, hasLength(1));
        expect(messages.single, contains('dictionary sync failed'));
        expect(messages.single, isNot(contains(directory.path)));
        expect(messages.single, isNot(contains('quiz_dictionary_seed_')));
        expect(_temporarySeedPaths(directory), isEmpty);
      } finally {
        debugPrint = originalDebugPrint;
        await DatabaseHelper.instance.close();
      }
    });
  });
}

Future<void> _withSupportDirectory(
  Future<void> Function(io.Directory directory) body,
) async {
  final directory = await io.Directory.systemTemp.createTemp(
    'oldguida_keyword_database_test_',
  );
  final original = PathProviderPlatform.instance;
  PathProviderPlatform.instance = _FakePathProvider(directory.path);
  try {
    await body(directory);
  } finally {
    await DatabaseHelper.instance.close();
    PathProviderPlatform.instance = original;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

String _mainDatabasePath(io.Directory directory) =>
    '${directory.path}${io.Platform.pathSeparator}quiz.db';

List<String> _temporarySeedPaths(io.Directory directory) => directory
    .listSync()
    .whereType<io.File>()
    .map((file) => file.path)
    .where((path) => path.contains('quiz_dictionary_seed_'))
    .toList();

Future<Database> _openFileDatabase(String path) =>
    databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );

Future<void> _createUserTables(Database db) async {
  await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE,
      password_hash TEXT,
      created_at TEXT,
      email TEXT,
      avatar_url TEXT,
      last_login_at TEXT,
      settings TEXT,
      uuid TEXT,
      vip_days INTEGER DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE favorites (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      section_id INTEGER,
      question_number INTEGER,
      created_at TEXT,
      note TEXT,
      is_deleted INTEGER DEFAULT 0,
      updated_at TEXT,
      UNIQUE(user_id, section_id, question_number)
    )
  ''');
  await db.execute('''
    CREATE TABLE quiz_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      score INTEGER,
      total_questions INTEGER,
      completed_at TEXT,
      used_time INTEGER,
      mode TEXT,
      accuracy REAL
    )
  ''');
}

Future<int> _userVersion(Database db) async =>
    Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'))!;

Future<bool> _tableExists(Database db, String table) async => (await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name = ?",
      whereArgs: [table],
      limit: 1,
    ))
        .isNotEmpty;

final class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _installDictionary(
  Database db, {
  required int version,
  required int id,
  required String term,
}) async {
  await KeywordDatabase.ensureSchema(db);
  await db.insert('keyword_dictionary', _keywordRow(id, term));
  await db.insert('keyword_forms', _formRow(id, id, term));
  await db.insert('keyword_examples', _exampleRow(id, id, id));
  await db.insert(
    'dictionary_meta',
    {'key': 'version', 'value': '$version'},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _clearDictionary(Database db) async {
  await KeywordDatabase.ensureSchema(db);
  await db.delete('keyword_examples');
  await db.delete('keyword_forms');
  await db.delete('keyword_dictionary');
  await db.delete('dictionary_meta');
}

Future<int> _dictionaryVersion(Database db) async {
  final rows = await db.query(
    'dictionary_meta',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: ['version'],
  );
  return int.parse(rows.single['value']! as String);
}

Future<int> _foreignKeysEnabled(Database db) async =>
    Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys'))!;

Future<Map<String, Object?>> _completeDictionaryState(Database db) async => {
      'schema': await _schemaState(db),
      'keyword_dictionary': await db.query('keyword_dictionary', orderBy: 'id'),
      'keyword_forms': await db.query('keyword_forms', orderBy: 'id'),
      'keyword_examples': await db.query('keyword_examples', orderBy: 'id'),
      'dictionary_meta': await db.query('dictionary_meta', orderBy: 'key'),
    };

Future<Map<String, Object?>> _schemaState(Database db) async {
  final result = <String, Object?>{};
  for (final table in [
    'keyword_dictionary',
    'keyword_forms',
    'keyword_examples',
    'dictionary_meta',
  ]) {
    final indexes = await db.rawQuery('PRAGMA index_list($table)');
    result[table] = {
      'table_info': await db.rawQuery('PRAGMA table_info($table)'),
      'index_list': indexes,
      'index_info': {
        for (final index in indexes)
          index['name']! as String:
              await db.rawQuery('PRAGMA index_info(${index['name']})'),
      },
      'foreign_key_list': await db.rawQuery('PRAGMA foreign_key_list($table)'),
    };
  }
  return result;
}

final Map<String, Object?> _expectedSchemaState = {
  'keyword_dictionary': {
    'table_info': [
      {
        'cid': 0,
        'name': 'id',
        'type': 'INTEGER',
        'notnull': 0,
        'dflt_value': null,
        'pk': 1
      },
      {
        'cid': 1,
        'name': 'term',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 2,
        'name': 'normalized_term',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 3,
        'name': 'part_of_speech',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 4,
        'name': 'translation',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 5,
        'name': 'note',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': "''",
        'pk': 0
      },
      {
        'cid': 6,
        'name': 'frequency',
        'type': 'INTEGER',
        'notnull': 1,
        'dflt_value': '0',
        'pk': 0
      },
      {
        'cid': 7,
        'name': 'sort_order',
        'type': 'INTEGER',
        'notnull': 1,
        'dflt_value': '0',
        'pk': 0
      },
    ],
    'index_list': [
      {
        'seq': 0,
        'name': 'sqlite_autoindex_keyword_dictionary_1',
        'unique': 1,
        'origin': 'u',
        'partial': 0
      },
    ],
    'index_info': {
      'sqlite_autoindex_keyword_dictionary_1': [
        {'seqno': 0, 'cid': 2, 'name': 'normalized_term'},
      ],
    },
    'foreign_key_list': <Map<String, Object?>>[],
  },
  'keyword_forms': {
    'table_info': [
      {
        'cid': 0,
        'name': 'id',
        'type': 'INTEGER',
        'notnull': 0,
        'dflt_value': null,
        'pk': 1
      },
      {
        'cid': 1,
        'name': 'keyword_id',
        'type': 'INTEGER',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 2,
        'name': 'form',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 3,
        'name': 'normalized_form',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
    ],
    'index_list': [
      {
        'seq': 0,
        'name': 'idx_keyword_forms_keyword_id',
        'unique': 0,
        'origin': 'c',
        'partial': 0
      },
      {
        'seq': 1,
        'name': 'sqlite_autoindex_keyword_forms_1',
        'unique': 1,
        'origin': 'u',
        'partial': 0
      },
    ],
    'index_info': {
      'idx_keyword_forms_keyword_id': [
        {'seqno': 0, 'cid': 1, 'name': 'keyword_id'},
      ],
      'sqlite_autoindex_keyword_forms_1': [
        {'seqno': 0, 'cid': 3, 'name': 'normalized_form'},
      ],
    },
    'foreign_key_list': [
      {
        'id': 0,
        'seq': 0,
        'table': 'keyword_dictionary',
        'from': 'keyword_id',
        'to': 'id',
        'on_update': 'NO ACTION',
        'on_delete': 'NO ACTION',
        'match': 'NONE'
      },
    ],
  },
  'keyword_examples': {
    'table_info': [
      {
        'cid': 0,
        'name': 'id',
        'type': 'INTEGER',
        'notnull': 0,
        'dflt_value': null,
        'pk': 1
      },
      {
        'cid': 1,
        'name': 'keyword_id',
        'type': 'INTEGER',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 2,
        'name': 'question_id',
        'type': 'INTEGER',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
      {
        'cid': 3,
        'name': 'rank',
        'type': 'INTEGER',
        'notnull': 1,
        'dflt_value': '0',
        'pk': 0
      },
    ],
    'index_list': [
      {
        'seq': 0,
        'name': 'idx_keyword_examples_question_id',
        'unique': 0,
        'origin': 'c',
        'partial': 0
      },
      {
        'seq': 1,
        'name': 'idx_keyword_examples_keyword_rank',
        'unique': 0,
        'origin': 'c',
        'partial': 0
      },
      {
        'seq': 2,
        'name': 'sqlite_autoindex_keyword_examples_1',
        'unique': 1,
        'origin': 'u',
        'partial': 0
      },
    ],
    'index_info': {
      'idx_keyword_examples_question_id': [
        {'seqno': 0, 'cid': 2, 'name': 'question_id'},
      ],
      'idx_keyword_examples_keyword_rank': [
        {'seqno': 0, 'cid': 1, 'name': 'keyword_id'},
        {'seqno': 1, 'cid': 3, 'name': 'rank'},
      ],
      'sqlite_autoindex_keyword_examples_1': [
        {'seqno': 0, 'cid': 1, 'name': 'keyword_id'},
        {'seqno': 1, 'cid': 2, 'name': 'question_id'},
      ],
    },
    'foreign_key_list': [
      {
        'id': 0,
        'seq': 0,
        'table': 'keyword_dictionary',
        'from': 'keyword_id',
        'to': 'id',
        'on_update': 'NO ACTION',
        'on_delete': 'NO ACTION',
        'match': 'NONE'
      },
    ],
  },
  'dictionary_meta': {
    'table_info': [
      {
        'cid': 0,
        'name': 'key',
        'type': 'TEXT',
        'notnull': 0,
        'dflt_value': null,
        'pk': 1
      },
      {
        'cid': 1,
        'name': 'value',
        'type': 'TEXT',
        'notnull': 1,
        'dflt_value': null,
        'pk': 0
      },
    ],
    'index_list': [
      {
        'seq': 0,
        'name': 'sqlite_autoindex_dictionary_meta_1',
        'unique': 1,
        'origin': 'pk',
        'partial': 0
      },
    ],
    'index_info': {
      'sqlite_autoindex_dictionary_meta_1': [
        {'seqno': 0, 'cid': 0, 'name': 'key'},
      ],
    },
    'foreign_key_list': <Map<String, Object?>>[],
  },
};

Map<String, Object?> _keywordRow(int id, String term) => {
      'id': id,
      'term': term,
      'normalized_term': term,
      'part_of_speech': 'noun',
      'translation': 'translation $id',
      'note': 'note $id',
      'frequency': id * 10,
      'sort_order': id,
    };

Map<String, Object?> _formRow(int id, int keywordId, String form) => {
      'id': id,
      'keyword_id': keywordId,
      'form': form,
      'normalized_form': form,
    };

Map<String, Object?> _exampleRow(int id, int keywordId, int questionId) => {
      'id': id,
      'keyword_id': keywordId,
      'question_id': questionId,
      'rank': 0,
    };
