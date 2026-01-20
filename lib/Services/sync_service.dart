import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import '../database/database_helper.dart';

class SyncService {
  static final _client = Supabase.instance.client;

  static String? get _uuid => Supabase.instance.client.auth.currentUser?.id;

  static int _toMillis(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return 0;
    }

  static DateTime _fromMillis(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsed);
      }
      return DateTime.parse(value);
    }
    return DateTime.now();
  }

  static Future<void> syncFavoriteChange(
      int userId, int sectionId, int questionNum, bool isAdd) async {
    final uuid = _uuid;
    if (uuid == null) {
      developer.log('syncFavoriteChange skipped: no uuid');
      return;
    }
    developer.log(
        'syncFavoriteChange ${isAdd ? 'add' : 'remove'} section=$sectionId question=$questionNum');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final data = {
        'user_id': uuid,
        'section_id': sectionId,
        'question_number': questionNum,
        'created_at': now,
        'updated_at': now,
        'is_deleted': isAdd ? 0 : 1,
      };
      await _client
          .from('favorites')
          .upsert(data, onConflict: 'user_id,section_id,question_number');
      developer.log('syncFavoriteChange completed');
    } catch (e) {
      developer.log('syncFavoriteChange error', error: e);
    }
  }

  static Future<void> syncWrongAnswerRemoval(
      int userId, int sectionId, int questionNum) async {
    final uuid = _uuid;
    if (uuid == null) {
      developer.log('syncWrongAnswerRemoval skipped: no uuid');
      return;
    }
    developer.log(
        'syncWrongAnswerRemoval section=$sectionId question=$questionNum');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _client.from('wrong_answers').upsert({
        'user_id': uuid,
        'section_id': sectionId,
        'question_number': questionNum,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 1,
      }, onConflict: 'user_id,section_id,question_number');
      developer.log('syncWrongAnswerRemoval completed');
    } catch (e) {
      developer.log('syncWrongAnswerRemoval error', error: e);
    }
  }

  static Future<void> syncQuizAttempt(int historyId) async {
    final uuid = _uuid;
    if (uuid == null) {
      developer.log('syncQuizAttempt skipped: no uuid');
      return;
    }
    developer.log('syncQuizAttempt historyId=$historyId');
    try {
      final db = DatabaseHelper.instance;
      final history = await db.getQuizHistoryById(historyId);
      if (history == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _client.from('quiz_history').upsert({
        'id': history[columnHistoryId],
        'user_id': uuid,
        'score': history[columnHistoryScore],
        'total_questions': history[columnHistoryTotalQuestions],
        'completed_at':
            _toMillis(history[columnHistoryCompletedAt]),
        'used_time': history[columnHistoryUsedTime],
        'mode': history[columnHistoryMode],
        'accuracy': history[columnHistoryAccuracy],
        'is_deleted': 0,
        'updated_at': now,
      });
      final wrongs = await db.getWrongAnswersByHistory(historyId);
      if (wrongs.isNotEmpty) {
        final rows = wrongs
            .map((w) {
              final ts = _toMillis(w[columnWrongCreatedAt]);
              return {
                'id': w[columnWrongId],
                'user_id': uuid,
                'section_id': w[columnWrongSectionId],
                'question_number': w[columnWrongQuestionNum],
                'created_at': ts,
                'updated_at': ts,
                'note': w[columnWrongNote],
                'history_id': w[columnWrongHistoryId],
                'question_chapter': w[columnWrongChapterId],
                'question_subsection': w[columnWrongSubsectionId],
                'is_deleted': 0,
              };
            })
            .toList();
        await _client.from('wrong_answers').upsert(rows,
            onConflict: 'user_id,section_id,question_number');
        developer.log('syncQuizAttempt uploaded ${rows.length} wrong answers');
      }
      final questions = await db.getHistoryQuestions(historyId);
      if (questions.isNotEmpty) {
        final qRows = questions
            .map((q) => {
                  'user_id': uuid,
                  'history_id': historyId,
                  'section_id': q[columnHQSectionId],
                  'question_number': q[columnHQQuestionNum],
                  'user_answer': q[columnHQUserAnswer],
                  'created_at': now,
                  'updated_at': now,
                })
            .toList();
        await _client
            .from('quiz_history_questions')
            .upsert(qRows);
        developer.log(
            'syncQuizAttempt uploaded ${qRows.length} history questions');
      }
      await _trimRemoteHistories(uuid);
      developer.log('syncQuizAttempt completed');
    } catch (e) {
      developer.log('syncQuizAttempt error', error: e);
    }
  }

  /// Synchronizes all local data with the remote backend.
  ///
  /// Returns `true` if sync completed without throwing, otherwise `false`.
  static Future<bool> syncAll() async {
    developer.log('syncAll started');
    try {
      final userId = await AuthService().ensureLocalUser();
      final uuid = _uuid;
      if (userId == null || uuid == null) {
        developer.log('syncAll aborted: userId=$userId uuid=$uuid');
        return false;
      }
      await _syncFavorites(userId, uuid);
      await _syncWrongAnswers(userId, uuid);
      await _syncQuizHistory(userId, uuid);
      developer.log('syncAll completed');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            'last_sync_at', DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        developer.log('save last_sync_at error', error: e);
      }
      return true;
    } catch (e, st) {
      developer.log('syncAll error', error: e, stackTrace: st);
      return false;
    }
  }

  static Future<void> _syncFavorites(int userId, String uuid) async {
    developer.log('_syncFavorites started');
    final db = DatabaseHelper.instance;
    final local = await db.getFavoritesRaw(userId);
    developer.log('local favorites=${local.length}');
    try {
      final remote =
          await _client.from('favorites').select().eq('user_id', uuid);
      developer.log('remote favorites=${(remote as List).length}');
      final map = <String, Map<String, dynamic>>{};
      for (final f in local) {
        final key = '${f[columnFavSectionId]}-${f[columnFavQuestionNum]}';
        final created = _toMillis(f[columnFavCreatedAt]);
        final updated = _toMillis(f[columnFavUpdatedAt] ?? f[columnFavCreatedAt]);
        final isDel = (f[columnFavIsDeleted] as num?)?.toInt() ?? 0;
        map[key] = {
          'user_id': uuid,
          'section_id': f[columnFavSectionId],
          'question_number': f[columnFavQuestionNum],
          'created_at': created,
          'updated_at': updated,
          'note': f[columnFavNote],
          'is_deleted': isDel,
        };
      }
      for (final f in remote as List) {
        final key = '${f['section_id']}-${f['question_number']}';
        final remoteRow = Map<String, dynamic>.from(f);
        remoteRow['created_at'] = _toMillis(remoteRow['created_at']);
        remoteRow['updated_at'] = _toMillis(remoteRow['updated_at']);
        remoteRow['is_deleted'] =
            (remoteRow['is_deleted'] as num?)?.toInt() ?? 0;
        final existing = map[key];
        if (existing == null ||
            (remoteRow['updated_at'] ?? 0) > (existing['updated_at'] ?? 0)) {
          map[key] = remoteRow;
        }
      }
      await db.delete(tableFavorites,
          where: '$columnFavUserId = ?', whereArgs: [userId]);
      for (final f in map.values) {
        await db.addFavorite(userId, f['section_id'] as int,
            f['question_number'] as int,
            note: f['note'] as String?,
            createdAt: _fromMillis(f['created_at']),
            updatedAt: _fromMillis(f['updated_at']),
            isDeleted: f['is_deleted'] as int);
      }
      await _client.from('favorites').delete().eq('user_id', uuid);
      await _client.from('favorites').upsert(map.values.toList(),
          onConflict: 'user_id,section_id,question_number');
      developer.log('_syncFavorites completed: merged=${map.length}');
    } catch (e) {
      developer.log('_syncFavorites error', error: e);
    }
  }

  static Future<void> _syncWrongAnswers(int userId, String uuid) async {
    developer.log('_syncWrongAnswers started');
    final db = DatabaseHelper.instance;
    final local = await db.getWrongAnswersRaw(userId);
    developer.log('local wrong answers=${local.length}');
    try {
      final remote =
          await _client.from('wrong_answers').select().eq('user_id', uuid);
      developer.log('remote wrong answers=${(remote as List).length}');
      final map = <String, Map<String, dynamic>>{};
      for (final w in local) {
        final key = '${w[columnWrongSectionId]}-${w[columnWrongQuestionNum]}';
        final created = _toMillis(w[columnWrongCreatedAt]);
        final updated = _toMillis(w[columnWrongUpdatedAt] ?? w[columnWrongCreatedAt]);
        final isDel = (w[columnWrongIsDeleted] as num?)?.toInt() ?? 0;
        map[key] = {
          'id': w[columnWrongId],
          'user_id': uuid,
          'section_id': w[columnWrongSectionId],
          'question_number': w[columnWrongQuestionNum],
          'created_at': created,
          'updated_at': updated,
          'note': w[columnWrongNote],
          'history_id': w[columnWrongHistoryId],
          'question_chapter': w[columnWrongChapterId],
          'question_subsection': w[columnWrongSubsectionId],
          'is_deleted': isDel,
        };
      }
      for (final w in remote as List) {
        final key = '${w['section_id']}-${w['question_number']}';
        final remoteRow = Map<String, dynamic>.from(w);
        remoteRow['created_at'] = _toMillis(remoteRow['created_at']);
        remoteRow['updated_at'] = _toMillis(remoteRow['updated_at']);
        remoteRow['is_deleted'] =
            (remoteRow['is_deleted'] as num?)?.toInt() ?? 0;
        final existing = map[key];
        if (existing == null ||
            (remoteRow['updated_at'] ?? 0) > (existing['updated_at'] ?? 0)) {
          map[key] = remoteRow;
        }
      }
      await db.delete(tableWrongAnswers,
          where: '$columnWrongUserId = ?', whereArgs: [userId]);
      for (final w in map.values) {
        await db.addWrongAnswer(userId, w['section_id'] as int,
            w['question_number'] as int,
            historyId: w['history_id'] as int?,
            note: w['note'] as String?,
            createdAt: _fromMillis(w['created_at']),
            updatedAt: _fromMillis(w['updated_at']),
            isDeleted: w['is_deleted'] as int,
            id: w['id'] as int?);
      }
      await _client.from('wrong_answers').delete().eq('user_id', uuid);
      await _client.from('wrong_answers').upsert(map.values.toList(),
          onConflict: 'user_id,section_id,question_number');
      developer.log('_syncWrongAnswers completed: merged=${map.length}');
    } catch (e) {
      developer.log('_syncWrongAnswers error', error: e);
    }
  }

  static Future<void> _syncQuizHistory(int userId, String uuid) async {
    developer.log('_syncQuizHistory started');
    final db = DatabaseHelper.instance;
    final local = await db.getQuizHistory(userId);
    developer.log('local histories=${local.length}');
    try {
      final remote = await _client
          .from('quiz_history')
          .select()
          .eq('user_id', uuid)
          .eq('is_deleted', 0);
      developer.log('remote histories=${(remote as List).length}');
      final remoteQs = await _client
          .from('quiz_history_questions')
          .select()
          .eq('user_id', uuid);
      developer.log('remote history questions=${(remoteQs as List).length}');
      final remoteQMap = <int, List<Map<String, dynamic>>>{};
      for (final q in remoteQs as List) {
        final id = q['history_id'] as int?;
        if (id == null) continue;
        remoteQMap.putIfAbsent(id, () => []).add(q);
      }
      final map = <int, Map<String, dynamic>>{};
      for (final h in local) {
        final completed = _toMillis(h[columnHistoryCompletedAt]);
        map[completed] = {
          'id': h[columnHistoryId],
          'user_id': uuid,
          'score': h[columnHistoryScore],
          'total_questions': h[columnHistoryTotalQuestions],
          'completed_at': completed,
          'updated_at': completed,
          'used_time': h[columnHistoryUsedTime],
          'mode': h[columnHistoryMode],
          'accuracy': h[columnHistoryAccuracy],
          'is_deleted': 0,
        };
      }
      for (final h in remote as List) {
        final remoteRow = Map<String, dynamic>.from(h);
        remoteRow['completed_at'] = _toMillis(remoteRow['completed_at']);
        remoteRow['updated_at'] = _toMillis(remoteRow['updated_at']);
        remoteRow['is_deleted'] =
            (remoteRow['is_deleted'] as num?)?.toInt() ?? 0;
        final key = remoteRow['completed_at'] as int;
        final existing = map[key];
        if (existing == null ||
            (remoteRow['completed_at'] ?? 0) > (existing['completed_at'] ?? 0)) {
          map[key] = remoteRow;
        }
      }
      final list = map.values.toList()
        ..sort((a, b) => (b['completed_at'] as int)
            .compareTo(a['completed_at'] as int));
      final limited = list.take(100).toList();
      await db.delete(tableQuizHistory,
          where: '$columnHistoryUserId = ?', whereArgs: [userId]);
      for (final h in limited) {
        await db.addQuizHistory(userId, h['score'] as int,
            h['total_questions'] as int,
            usedTime: h['used_time'] as int?,
            mode: h['mode'] as String?,
            accuracy: (h['accuracy'] as num?)?.toDouble(),
            completedAt: _fromMillis(h['completed_at']),
            id: h['id'] as int?);
        final hid = h['id'] as int?;
        if (hid != null) {
          final existing = await db.getHistoryQuestions(hid);
          if (existing.isEmpty) {
            final rq = remoteQMap[hid] ?? const <Map<String, dynamic>>[];
            for (final q in rq) {
              await db.addHistoryQuestion(
                  hid,
                  q[columnHQSectionId] as int,
                  q[columnHQQuestionNum] as int,
                  q[columnHQUserAnswer] as int?);
            }
          }
        }
      }
      await _client.from('quiz_history').delete().eq('user_id', uuid);
      await _client.from('quiz_history').upsert(limited);
      await _client
          .from('quiz_history_questions')
          .delete()
          .eq('user_id', uuid);
      for (final h in limited) {
        final qs = await db.getHistoryQuestions(h['id'] as int);
        if (qs.isNotEmpty) {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final rows = qs
              .map((q) => {
                    'user_id': uuid,
                    'history_id': h['id'],
                    'section_id': q[columnHQSectionId],
                    'question_number': q[columnHQQuestionNum],
                    'user_answer': q[columnHQUserAnswer],
                    'created_at': ts,
                    'updated_at': ts,
                  })
              .toList();
          await _client
              .from('quiz_history_questions')
              .upsert(rows);
        }
      }
      await db.trimQuizHistory(userId, 100);
      await _trimRemoteHistories(uuid);
      developer.log('_syncQuizHistory completed: merged=${limited.length}');
    } catch (e) {
      developer.log('_syncQuizHistory error', error: e);
    }
  }

  static Future<void> _trimRemoteHistories(String uuid) async {
    developer.log('_trimRemoteHistories started');
    try {
      final list = await _client
          .from('quiz_history')
          .select('id, completed_at')
          .eq('user_id', uuid)
          .order('completed_at', ascending: false);
      developer.log('remote histories total=${list.length}');
      if (list.length > 100) {
        final ids =
            list.sublist(100).map((e) => e['id'] as int).toList();
        if (ids.isNotEmpty) {
          await _client
              .from('quiz_history')
              .delete()
              .filter('id', 'in', '(${ids.join(',')})');
          developer.log('_trimRemoteHistories removed ${ids.length}');
        }
      }
      developer.log('_trimRemoteHistories completed');
    } catch (e) {
      developer.log('_trimRemoteHistories error', error: e);
    }
  }
}

