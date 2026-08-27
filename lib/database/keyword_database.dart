import 'dart:io' if (dart.library.html) 'io_stub.dart' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:sqflite/sqflite.dart';

abstract final class KeywordDatabase {
  static const int bundledVersion = 1;
  static int _temporarySeedSequence = 0;

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
    await ensureSchema(target);
    await _requireForeignKeys(target);
    final targetVersion = await _version(target);
    final seedVersion = await _version(seed);
    if (seedVersion <= targetVersion) return false;

    final rows = await _validatedSeedRows(seed);
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
    await io.Directory(directory.path).create(recursive: true);
    final seedPath = join(
      directory.path,
      'quiz_dictionary_seed_${DateTime.now().microsecondsSinceEpoch}_'
      '${_temporarySeedSequence++}.db',
    );
    Database? seed;
    try {
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
        if (await databaseExists(seedPath)) {
          await deleteDatabase(seedPath);
        }
      }
    }
  }

  static Future<
      ({
        List<Map<String, Object?>> entries,
        List<Map<String, Object?>> forms,
        List<Map<String, Object?>> examples,
      })> _validatedSeedRows(Database seed) async {
    const requiredTables = {
      'keyword_dictionary',
      'keyword_forms',
      'keyword_examples',
    };
    final tableRows = await seed.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name IN (?, ?, ?)",
      whereArgs: requiredTables.toList(growable: false),
    );
    final tables = tableRows.map((row) => row['name']).toSet();
    if (!tables.containsAll(requiredTables)) {
      throw StateError('Bundled dictionary seed is missing required tables');
    }

    final entries = await seed.query('keyword_dictionary', orderBy: 'id');
    final forms = await seed.query('keyword_forms', orderBy: 'id');
    final examples = await seed.query('keyword_examples', orderBy: 'id');
    if (entries.isEmpty || forms.isEmpty || examples.isEmpty) {
      throw StateError('Bundled dictionary seed is empty');
    }

    final entryIds = entries.map((row) => row['id']).toSet();
    final entryIdsAreValid =
        entryIds.length == entries.length && entryIds.every((id) => id is int);
    final formsAreValid =
        forms.every((row) => entryIds.contains(row['keyword_id']));
    final examplesAreValid =
        examples.every((row) => entryIds.contains(row['keyword_id']));
    if (!entryIdsAreValid || !formsAreValid || !examplesAreValid) {
      throw StateError('Bundled dictionary seed has invalid references');
    }

    return (entries: entries, forms: forms, examples: examples);
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
      if (rows.isEmpty) return 0;
      return int.tryParse(rows.single['value']?.toString() ?? '') ?? 0;
    } on DatabaseException {
      return 0;
    }
  }
}
