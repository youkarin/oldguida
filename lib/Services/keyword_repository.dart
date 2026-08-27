import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/keyword_model.dart';

typedef DatabaseProvider = Future<Database> Function();

class KeywordRepository {
  KeywordRepository({DatabaseProvider? databaseProvider})
      : _databaseProvider =
            databaseProvider ?? KeywordRepository._defaultDatabaseProvider;

  final DatabaseProvider _databaseProvider;

  static Future<Database> _defaultDatabaseProvider() =>
      DatabaseHelper.instance.database;

  Future<List<Keyword>> all() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'keyword_dictionary',
      orderBy: 'sort_order ASC, frequency DESC, term ASC',
    );
    return rows.map(Keyword.fromMap).toList(growable: false);
  }

  Future<List<Keyword>> search(String query) async {
    final normalized = _normalizeSearchQuery(query.trim());
    if (normalized.isEmpty) {
      return all();
    }

    final db = await _databaseProvider();
    final pattern = '%${_escapeLike(normalized)}%';
    final rows = await db.rawQuery(
      r'''
        SELECT DISTINCT k.*
        FROM keyword_dictionary k
        LEFT JOIN keyword_forms f ON f.keyword_id = k.id
        WHERE k.normalized_term LIKE ? ESCAPE '\'
           OR f.normalized_form LIKE ? ESCAPE '\'
           OR k.translation LIKE ? ESCAPE '\'
        ORDER BY k.sort_order ASC, k.frequency DESC, k.term ASC
      ''',
      [pattern, pattern, pattern],
    );
    return rows.map(Keyword.fromMap).toList(growable: false);
  }

  Future<Keyword?> byId(int id) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'keyword_dictionary',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Keyword.fromMap(rows.first);
  }

  Future<List<KeywordForm>> forms() async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery('''
      SELECT f.*
      FROM keyword_forms f
      INNER JOIN keyword_dictionary k ON k.id = f.keyword_id
      ORDER BY LENGTH(f.normalized_form) DESC,
               f.normalized_form ASC,
               f.id ASC
    ''');
    return rows.map(KeywordForm.fromMap).toList(growable: false);
  }

  Future<KeywordExample?> exampleFor(int keywordId) async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery(
      '''
        SELECT q.id AS question_id, q.question, q.translation
        FROM keyword_examples e
        INNER JOIN quiz q ON q.id = e.question_id
        WHERE e.keyword_id = ?
        ORDER BY e.rank ASC, e.id ASC
        LIMIT 1
      ''',
      [keywordId],
    );
    return rows.isEmpty ? null : KeywordExample.fromMap(rows.first);
  }

  Future<int> dictionaryVersion() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'dictionary_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['version'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    final version = int.tryParse(rows.first['value']?.toString() ?? '');
    return version != null && version > 0 ? version : 0;
  }
}

String _normalizeSearchQuery(String value) =>
    value.toLowerCase().replaceAll('’', "'");

String _escapeLike(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
