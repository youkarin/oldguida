import 'dart:io' if (dart.library.html) 'io_stub.dart' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:sqflite/sqflite.dart';

abstract final class KeywordDatabase {
  static const int bundledVersion = 1;

  static Future<void> ensureSchema(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_keyword_forms_keyword_id '
      'ON keyword_forms(keyword_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_keyword_examples_keyword_rank '
      'ON keyword_examples(keyword_id, rank)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_keyword_examples_question_id '
      'ON keyword_examples(question_id)',
    );
  }

  static Future<bool> syncFrom({
    required Database target,
    required Database seed,
  }) async {
    final targetVersion = await _version(target);
    final seedVersion = await _strictSeedVersion(seed);
    if (seedVersion <= targetVersion) return false;

    final rows = await _validatedSeedRows(seed, target);
    await ensureSchema(target);
    await _requireForeignKeys(target);
    await target.transaction((txn) async {
      await txn.delete('keyword_examples');
      await txn.delete('keyword_forms');
      await txn.delete('keyword_dictionary');
      for (final row in rows.entries) {
        await txn.insert('keyword_dictionary', row);
      }
      for (final row in rows.forms) {
        await txn.insert('keyword_forms', row);
      }
      for (final row in rows.examples) {
        await txn.insert('keyword_examples', row);
      }
      await txn.insert(
        'dictionary_meta',
        {'key': 'version', 'value': '$seedVersion'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return true;
  }

  static Future<void> _requireForeignKeys(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    final foreignKeys = Sqflite.firstIntValue(
      await db.rawQuery('PRAGMA foreign_keys'),
    );
    if (foreignKeys != 1) {
      throw StateError('SQLite foreign key enforcement is unavailable');
    }
  }

  static Future<void> syncBundledIfNeeded(Database target) async {
    if (kIsWeb) return;
    if (await _version(target) >= bundledVersion) return;

    final directory = await getApplicationSupportDirectory();
    final supportDirectory = io.Directory(directory.path);
    await supportDirectory.create(recursive: true);
    io.Directory? temporaryDirectory;
    String? seedPath;
    Database? seed;
    try {
      temporaryDirectory =
          await supportDirectory.createTemp('quiz_dictionary_seed_');
      seedPath = join(temporaryDirectory.path, 'quiz.db');
      final data = await rootBundle.load('assets/db/quiz.db');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await io.File(seedPath).writeAsBytes(bytes, flush: true);
      seed = await openDatabase(seedPath, readOnly: true);
      await syncFrom(target: target, seed: seed);
    } finally {
      try {
        await seed?.close();
      } finally {
        try {
          if (seedPath != null && await databaseExists(seedPath)) {
            await deleteDatabase(seedPath);
          }
        } finally {
          if (temporaryDirectory != null && await temporaryDirectory.exists()) {
            await temporaryDirectory.delete(recursive: true);
          }
        }
      }
    }
  }

  static Future<
      ({
        List<Map<String, Object?>> entries,
        List<Map<String, Object?>> forms,
        List<Map<String, Object?>> examples,
      })> _validatedSeedRows(Database seed, Database target) async {
    await _requireColumns(seed, const {
      'keyword_dictionary': {
        'id',
        'term',
        'normalized_term',
        'part_of_speech',
        'translation',
        'note',
        'frequency',
        'sort_order',
      },
      'keyword_forms': {'id', 'keyword_id', 'form', 'normalized_form'},
      'keyword_examples': {
        'id',
        'keyword_id',
        'question_id',
        'rank',
      },
      'dictionary_meta': {'key', 'value'},
      'quiz': {'id'},
    });
    final entries = await seed.query('keyword_dictionary', orderBy: 'id');
    final forms = await seed.query('keyword_forms', orderBy: 'id');
    final examples = await seed.query('keyword_examples', orderBy: 'id');
    if (entries.isEmpty || forms.isEmpty || examples.isEmpty) {
      throw StateError('Bundled dictionary seed is empty');
    }

    final entryIds = <int>{};
    final normalizedTerms = <String>{};
    for (final row in entries) {
      final id = row['id'];
      final normalizedTerm = row['normalized_term'];
      if (!_isPositiveInt(id) ||
          !entryIds.add(id as int) ||
          !_isNonEmptyString(row['term']) ||
          !_isNonEmptyString(normalizedTerm) ||
          !normalizedTerms.add(normalizedTerm as String) ||
          !_isNonEmptyString(row['part_of_speech']) ||
          !_isNonEmptyString(row['translation']) ||
          row['note'] is! String ||
          !_isNonNegativeInt(row['frequency']) ||
          !_isNonNegativeInt(row['sort_order'])) {
        throw StateError('Bundled dictionary seed has an invalid entry');
      }
    }

    final formIds = <int>{};
    final normalizedForms = <String>{};
    final formOwners = <int>{};
    for (final row in forms) {
      final id = row['id'];
      final keywordId = row['keyword_id'];
      final normalizedForm = row['normalized_form'];
      if (!_isPositiveInt(id) ||
          !formIds.add(id as int) ||
          !_isPositiveInt(keywordId) ||
          !entryIds.contains(keywordId) ||
          !_isNonEmptyString(row['form']) ||
          !_isNonEmptyString(normalizedForm) ||
          !normalizedForms.add(normalizedForm as String)) {
        throw StateError('Bundled dictionary seed has an invalid form');
      }
      formOwners.add(keywordId as int);
    }
    if (!formOwners.containsAll(entryIds)) {
      throw StateError('Bundled dictionary seed has an entry without a form');
    }

    final seedQuestionIds = (await seed.query('quiz', columns: ['id']))
        .map((row) => row['id'])
        .whereType<int>()
        .toSet();
    final targetHasQuiz = await _tableExists(target, 'quiz');
    Set<int>? targetQuestionIds;
    if (targetHasQuiz) {
      await _requireColumns(target, const {
        'quiz': {'id'},
      });
      targetQuestionIds = (await target.query('quiz', columns: ['id']))
          .map((row) => row['id'])
          .whereType<int>()
          .toSet();
    }

    final exampleIds = <int>{};
    final examplePairs = <(int, int)>{};
    final exampleOwners = <int>{};
    for (final row in examples) {
      final id = row['id'];
      final keywordId = row['keyword_id'];
      final questionId = row['question_id'];
      final rank = row['rank'];
      if (!_isPositiveInt(id) ||
          !exampleIds.add(id as int) ||
          !_isPositiveInt(keywordId) ||
          !entryIds.contains(keywordId) ||
          !_isPositiveInt(questionId) ||
          !seedQuestionIds.contains(questionId) ||
          (targetQuestionIds != null &&
              !targetQuestionIds.contains(questionId)) ||
          !_isNonNegativeInt(rank) ||
          !examplePairs.add((keywordId as int, questionId as int))) {
        throw StateError('Bundled dictionary seed has an invalid example');
      }
      exampleOwners.add(keywordId);
    }
    if (!exampleOwners.containsAll(entryIds)) {
      throw StateError(
        'Bundled dictionary seed has an entry without an example',
      );
    }

    return (entries: entries, forms: forms, examples: examples);
  }

  static Future<int> _strictSeedVersion(Database seed) async {
    await _requireColumns(seed, const {
      'dictionary_meta': {'key', 'value'},
    });
    final rows = await seed.query(
      'dictionary_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['version'],
    );
    if (rows.length != 1 || rows.single['value'] is! String) {
      throw StateError('Bundled dictionary seed has no valid version');
    }
    final version = int.tryParse(rows.single['value']! as String);
    if (version == null || version <= 0) {
      throw StateError('Bundled dictionary seed has no valid version');
    }
    return version;
  }

  static Future<void> _requireColumns(
    Database db,
    Map<String, Set<String>> required,
  ) async {
    for (final entry in required.entries) {
      if (!await _tableExists(db, entry.key)) {
        throw StateError('Bundled dictionary seed is missing ${entry.key}');
      }
      final columns = (await db.rawQuery('PRAGMA table_info(${entry.key})'))
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      if (!columns.containsAll(entry.value)) {
        throw StateError(
          'Bundled dictionary seed has invalid ${entry.key} columns',
        );
      }
    }
  }

  static Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name = ?",
      whereArgs: [table],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static bool _isPositiveInt(Object? value) => value is int && value > 0;

  static bool _isNonNegativeInt(Object? value) => value is int && value >= 0;

  static bool _isNonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty;

  static Future<int> _version(Database db) async {
    try {
      final rows = await db.query(
        'dictionary_meta',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['version'],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      return int.tryParse(rows.single['value']?.toString() ?? '') ?? 0;
    } on DatabaseException {
      return 0;
    }
  }
}
