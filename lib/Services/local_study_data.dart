import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:italian_driving_app/database/database_helper.dart';

/// Local ownership compatibility, not an account or authentication service.
/// Never reassigns, merges, or deletes existing study records.
class LocalStudyData {
  static final instance = LocalStudyData._(DatabaseHelper.instance);
  final DatabaseHelper _database;
  final Future<bool> Function(int)? _persistOwner;
  Future<int?>? _resolving;

  LocalStudyData._(this._database) : _persistOwner = null;

  @visibleForTesting
  LocalStudyData.forTesting(this._database,
      {Future<bool> Function(int)? persistOwner})
      : _persistOwner = persistOwner;

  static const unavailableMessage =
      '本地学习存储暂不可用，原记录已保留。请重试；当前无法保存学习记录。';
  static const legacyVisibilityMessage =
      '旧学习记录已原样保留；当前仅显示本地归属范围内的记录，其他历史归属或孤立记录不会自动合并，也不提供归属选择器。';

  // One durable marker, not a profile/dataset registry. Commit it in the same
  // transaction as allocation so preferences failures cannot create extra users.
  static const ownerStateSql = '''
    CREATE TABLE IF NOT EXISTS local_study_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      user_id INTEGER NOT NULL
    )
  ''';
  static const ownerHighWaterSql = '''
    SELECT MAX(value) AS max_id FROM (
      SELECT 0 AS value
      UNION ALL SELECT id FROM users
      UNION ALL SELECT user_id FROM favorites
      UNION ALL SELECT user_id FROM wrong_answers
      UNION ALL SELECT user_id FROM quiz_history
    )
  ''';

  Future<int?> ensureOwner() {
    return _resolving ??= _resolve().whenComplete(() => _resolving = null);
  }

  Future<int> _resolve() async {
    final db = await _database.database;
    final owner = await db.transaction<int>((txn) async {
      await txn.execute(ownerStateSql);
      final users = await txn.query(tableUsers,
          columns: [columnUserId, columnUsername]);
      final ids = users.map((row) => row[columnUserId]).toSet();
      final states = await txn.query('local_study_state', where: 'id = 1');
      final owners = await txn.rawQuery('''
        SELECT user_id FROM favorites
        UNION SELECT user_id FROM wrong_answers
        UNION SELECT user_id FROM quiz_history
      ''');
      int? chosen;
      if (states.isNotEmpty) {
        // SQLite is authoritative after initial adoption, even if old preferences
        // remain stale because their write failed. A missing marked user is NOT
        // permission to adopt another historical user's records.
        final marked = states.single['user_id'] as int;
        if (ids.contains(marked)) chosen = marked;
      } else {
        // On first adoption a read failure must propagate, not disguise a valid
        // explicit legacy choice as absent. Nothing has committed at this point.
        final prefs = await SharedPreferences.getInstance();
        final selected = prefs.getInt('local_study_owner_id');
        final legacyName = prefs.getString('username');
        if (selected != null) {
          if (ids.contains(selected)) chosen = selected;
        } else if (legacyName != null && legacyName.isNotEmpty) {
          final matches = users.where((row) => row[columnUsername] == legacyName);
          if (matches.length == 1) {
            chosen = matches.single[columnUserId] as int;
          }
        } else if (users.length == 1 &&
            owners.every((row) => ids.contains(row['user_id']))) {
          chosen = users.single[columnUserId] as int;
        }
      }
      if (chosen == null) {
        // Include orphan IDs from EVERY learning ownership table, not merely
        // sqlite_sequence/users. NULLs do not reserve an integer ID.
        final maximum = (await txn.rawQuery(ownerHighWaterSql)).single['max_id'];
        if (maximum is! int || maximum >= 9223372036854775807) {
          throw StateError('No safe local study owner ID available');
        }
        final nextId = maximum + 1;
        var name = 'local';
        var suffix = 0;
        // Ask SQLite so legacy username collation/UNIQUE constraints are honored.
        while ((await txn.query(tableUsers,
                columns: [columnUserId],
                where: '$columnUsername = ?', whereArgs: [name], limit: 1))
            .isNotEmpty) {
          name = suffix == 0 ? 'local-$nextId' : 'local-$nextId-$suffix';
          suffix++;
        }
        await txn.insert(tableUsers, {
          columnUserId: nextId,
          columnUsername: name,
          columnPasswordHash: '', // Older NOT NULL schemas.
          columnUserCreatedAt: DateTime.now().toIso8601String(),
        });
        chosen = nextId;
      }
      if (states.isEmpty) {
        await txn.insert('local_study_state', {'id': 1, 'user_id': chosen});
      } else if (states.single['user_id'] != chosen) {
        await txn.update('local_study_state', {'user_id': chosen}, where: 'id = 1');
      }
      if (users.any((row) => row[columnUserId] != chosen) ||
          owners.any((row) => row['user_id'] != chosen)) {
        debugPrint(legacyVisibilityMessage);
      }
      return chosen;
    });
    // A compatibility cache only: the database already committed the identity.
    // Both false and throwing preference writes permit saving and stable retries.
    try {
      final persistOwner = _persistOwner;
      final saved = persistOwner != null
          ? await persistOwner(owner)
          : await (await SharedPreferences.getInstance())
              .setInt('local_study_owner_id', owner);
      if (!saved) debugPrint('本地归属已存入数据库；偏好缓存写入失败，可重试。');
    } catch (e) {
      debugPrint('本地归属已存入数据库；偏好缓存暂不可用：$e');
    }
    return owner;
  }
}
