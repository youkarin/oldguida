import 'dart:io' if (dart.library.html) 'io_stub.dart' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'database_factory.dart';

// ========== 基础常量 ==========
const String _dbFileName = 'quiz.db';
const int _dbVersion = 3;

// ---------- quiz 表及相关 ----------
const String tableQuiz = 'quiz';
const String quizId = 'id';
const String quizQuestion = 'question';
const String quizAnswer = 'answer';
const String quizSectionId = 'section_id';
const String quizTranslation = 'translation';
const String quizExplanation = 'explanation';
const String quizQuestionNumber = 'question_number';

// ---------- chapter 表 ----------
const String tableChapter = 'chapter';
const String chapterId = 'id';
const String chapterChapterId = 'chapter_id';
const String chapterName = 'name';
const String chapterImagePath = 'image_path';

// ---------- section 表 ----------
const String tableSection = 'section';
const String sectionId = 'id';
const String sectionSectionId = 'section_id';
const String sectionChapterId = 'chapter_id';
const String sectionName = 'name';
const String sectionImagePath = 'image_path';

// ---------- 用户表 ----------
const String tableUsers = 'users';
const String columnUserId = 'id';
const String columnUsername = 'username';
const String columnPasswordHash = 'password_hash';
const String columnUserCreatedAt = 'created_at';
const String columnUserEmail = 'email';
const String columnUserAvatarUrl = 'avatar_url';
const String columnUserLastLoginAt = 'last_login_at';
const String columnUserSettings = 'settings';
const String columnUserUuid = 'uuid';
const String columnUserVipDays = 'vip_days';

// ---------- 收藏表 ----------
const String tableFavorites = 'favorites';
const String columnFavoriteId = 'id';
const String columnFavUserId = 'user_id';
const String columnFavSectionId = 'section_id';
const String columnFavQuestionNum = 'question_number';
const String columnFavCreatedAt = 'created_at';
const String columnFavNote = 'note';
const String columnFavIsDeleted = 'is_deleted';
const String columnFavUpdatedAt = 'updated_at';

// ---------- 错题表 ----------
const String tableWrongAnswers = 'wrong_answers';
const String columnWrongId = 'id';
const String columnWrongUserId = 'user_id';
const String columnWrongSectionId = 'section_id';
const String columnWrongQuestionNum = 'question_number';
const String columnWrongCreatedAt = 'created_at';
const String columnWrongNote = 'note';
const String columnWrongHistoryId = 'history_id';
const String columnWrongChapterId = 'question_chapter';
const String columnWrongSubsectionId = 'question_subsection';
const String columnWrongIsDeleted = 'is_deleted';
const String columnWrongUpdatedAt = 'updated_at';

// ---------- 历史题目明细表 ----------
const String tableHistoryQuestions = 'quiz_history_questions';
const String columnHQId = 'id';
const String columnHQHistoryId = 'history_id';
const String columnHQSectionId = 'section_id';
const String columnHQQuestionNum = 'question_number';
const String columnHQUserAnswer = 'user_answer';

// ---------- 答题历史表 ----------
const String tableQuizHistory = 'quiz_history';
const String columnHistoryId = 'id';
const String columnHistoryUserId = 'user_id';
const String columnHistoryScore = 'score';
const String columnHistoryTotalQuestions = 'total_questions';
const String columnHistoryCompletedAt = 'completed_at';
const String columnHistoryUsedTime = 'used_time';
const String columnHistoryMode = 'mode';
const String columnHistoryAccuracy = 'accuracy';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _db;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
    await initDatabaseFactory();
    String dbPath;
    if (io.Platform.isWindows ||
        io.Platform.isLinux ||
        io.Platform.isMacOS) {
      final dir = await getApplicationSupportDirectory();
      dbPath = dir.path;
    } else {
      dbPath = await getDatabasesPath();
    }
    final path = join(dbPath, _dbFileName);

    // 如果数据库文件不存在，从 assets 复制（非 Web 环境）
    if (!kIsWeb && !await databaseExists(path)) {
      try {
        await io.Directory(dirname(path)).create(recursive: true);
        final data = await rootBundle.load('assets/db/$_dbFileName');
        final bytes = data.buffer.asUint8List(
            data.offsetInBytes, data.lengthInBytes);
        await io.File(path).writeAsBytes(bytes, flush: true);
        print("数据库已从 assets 成功复制。");
      } catch (e) {
        print("从 assets 复制数据库时出错: $e");
      }
    }

    // 打开数据库，并设置版本和升级逻辑
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onUpgrade: _onUpgrade,
      onCreate: _onCreate,
    );

    // Ensure users table exists
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $tableUsers (
        $columnUserId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnUsername TEXT UNIQUE,
        $columnPasswordHash TEXT,
        $columnUserCreatedAt TEXT,
        $columnUserEmail TEXT,
        $columnUserAvatarUrl TEXT,
        $columnUserLastLoginAt TEXT,
        $columnUserSettings TEXT,
        $columnUserUuid TEXT,
        $columnUserVipDays INTEGER DEFAULT 0
      )
    ''');

    // Ensure user table has uuid & vip_days columns
    await _ensureColumnExists(_db!, tableUsers, columnUserUuid, 'TEXT');
    await _ensureColumnExists(
        _db!, tableUsers, columnUserVipDays, 'INTEGER DEFAULT 0');

    // Ensure favorites table exists
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $tableFavorites (
        $columnFavoriteId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnFavUserId INTEGER,
        $columnFavSectionId INTEGER,
        $columnFavQuestionNum INTEGER,
        $columnFavCreatedAt TEXT,
        $columnFavNote TEXT,
        $columnFavIsDeleted INTEGER DEFAULT 0,
        $columnFavUpdatedAt TEXT,
        UNIQUE($columnFavUserId, $columnFavSectionId, $columnFavQuestionNum)
      )
    ''');
    await _ensureColumnExists(
        _db!, tableFavorites, columnFavSectionId, 'INTEGER');
    await _ensureColumnExists(
        _db!, tableFavorites, columnFavQuestionNum, 'INTEGER');
    await _ensureColumnExists(
        _db!, tableFavorites, columnFavCreatedAt, 'TEXT');
    await _ensureColumnExists(
        _db!, tableFavorites, columnFavNote, 'TEXT');
    await _ensureColumnExists(
        _db!, tableFavorites, columnFavIsDeleted, 'INTEGER DEFAULT 0');
    await _ensureColumnExists(
        _db!, tableFavorites, columnFavUpdatedAt, 'TEXT');

    // Ensure wrong_answers table and required columns
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $tableWrongAnswers (
        $columnWrongId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnWrongUserId INTEGER,
        $columnWrongSectionId INTEGER,
        $columnWrongQuestionNum INTEGER,
        $columnWrongCreatedAt TEXT,
        $columnWrongNote TEXT,
        $columnWrongHistoryId INTEGER,
        $columnWrongChapterId INTEGER,
        $columnWrongSubsectionId INTEGER,
        $columnWrongIsDeleted INTEGER DEFAULT 0,
        $columnWrongUpdatedAt TEXT
      )
    ''');
    await _ensureColumnExists(
        _db!, tableWrongAnswers, columnWrongSectionId, 'INTEGER');
    await _ensureColumnExists(
        _db!, tableWrongAnswers, columnWrongHistoryId, 'INTEGER');
    await _ensureColumnExists(
        _db!, tableWrongAnswers, columnWrongChapterId, 'INTEGER');
    await _ensureColumnExists(
        _db!, tableWrongAnswers, columnWrongSubsectionId, 'INTEGER DEFAULT 0');
    await _ensureColumnExists(
        _db!, tableWrongAnswers, columnWrongIsDeleted, 'INTEGER DEFAULT 0');
    await _ensureColumnExists(
        _db!, tableWrongAnswers, columnWrongUpdatedAt, 'TEXT');

    // History detail tables
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $tableHistoryQuestions (
        $columnHQId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnHQHistoryId INTEGER,
        $columnHQSectionId INTEGER,
        $columnHQQuestionNum INTEGER,
        $columnHQUserAnswer INTEGER
      )
    ''');
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $tableQuizHistory (
        $columnHistoryId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnHistoryUserId INTEGER,
        $columnHistoryScore INTEGER,
        $columnHistoryTotalQuestions INTEGER,
        $columnHistoryCompletedAt TEXT,
        $columnHistoryUsedTime INTEGER,
        $columnHistoryMode TEXT,
        $columnHistoryAccuracy REAL
      )
    ''');

    return _db!;
  }

  /// 确保某表存在指定列，不存在则新增
  Future<void> _ensureColumnExists(
      Database db, String table, String column, String definition) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    final exists =
        result.any((element) => element['name']?.toString() == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  // ----------- 数据库新建逻辑 -----------
  Future<void> _onCreate(Database db, int version) async {
    // 建表语句建议你用 Python/DB Browser 预建好，Dart 侧一般只做拷贝，不做建表，故此处省略
  }

  // ----------- 数据库升级逻辑 -----------
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
  }

  // ======================================
  //           章节、小节、题目
  // ======================================
  /// 获取所有章节
  Future<List<Map<String, dynamic>>> getChapters() async {
    final db = await database;
    return db.query(tableChapter, orderBy: chapterChapterId);
  }

  /// 获取某章节下所有小节
  Future<List<Map<String, dynamic>>> getSections(int chapterIdValue) async {
    final db = await database;
    return db.query(
      tableSection,
      where: '$sectionChapterId = ?',
      whereArgs: [chapterIdValue],
      orderBy: sectionSectionId,
    );
  }

  /// 获取某小节下所有题目
  Future<List<Map<String, dynamic>>> getQuestionsBySection(int sectionIdValue) async {
    final db = await database;
    return db.query(
      tableQuiz,
      where: '$quizSectionId = ?',
      whereArgs: [sectionIdValue],
      orderBy: quizQuestionNumber,
    );
  }

  /// 获取某章节下所有题目（join section）
  Future<List<Map<String, dynamic>>> getQuestionsByChapter(int chapterIdValue) async {
    final db = await database;
    return db.rawQuery('''
      SELECT q.* FROM $tableQuiz q
      INNER JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      WHERE s.$sectionChapterId = ?
      ORDER BY q.$quizSectionId, q.$quizQuestionNumber
    ''', [chapterIdValue]);
  }

  /// 根据多个章节随机获取题目，并携带节图片
  Future<List<Map<String, dynamic>>> getQuestionsByChaptersRandom(
      List<int> chapterIds, int limit) async {
    if (chapterIds.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(chapterIds.length, '?').join(',');
    return db.rawQuery('''
      SELECT q.*, s.image_path as image_url
      FROM $tableQuiz q
      INNER JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      WHERE s.$sectionChapterId IN ($placeholders)
      ORDER BY RANDOM()
      LIMIT $limit
    ''', chapterIds);
  }

  /// 根据多个章节顺序获取所有题目，并携带节图片
  Future<List<Map<String, dynamic>>> getQuestionsByChaptersSequential(
      List<int> chapterIds) async {
    if (chapterIds.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(chapterIds.length, '?').join(',');
    return db.rawQuery('''
      SELECT q.*, s.image_path as image_url
      FROM $tableQuiz q
      INNER JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      WHERE s.$sectionChapterId IN ($placeholders)
      ORDER BY s.$sectionChapterId, q.$quizSectionId, q.$quizQuestionNumber
    ''', chapterIds);
  }

  /// 随机获取所有题目
  Future<List<Map<String, dynamic>>> getAllQuestionsRandom() async {
    final db = await database;
    return db.rawQuery('SELECT * FROM $tableQuiz ORDER BY RANDOM()');
  }

  // ======================================
  //             用户管理
  // ======================================
  Future<int> addUser(String username, String passwordHash,
      {String? email,
      String? avatarUrl,
      String? settings,
      String? uuid,
      int vipDays = 0}) async {
    final db = await database;
    return db.insert(tableUsers, {
      columnUsername: username,
      columnPasswordHash: passwordHash,
      columnUserEmail: email,
      columnUserAvatarUrl: avatarUrl,
      columnUserSettings: settings,
      columnUserUuid: uuid,
      columnUserVipDays: vipDays,
    });
  }

  Future<Map<String, dynamic>?> getUser(String username) async {
    final db = await database;
    final maps = await db.query(
      tableUsers,
      where: '$columnUsername = ?',
      whereArgs: [username],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> updateUserLastLoginAt(int userId) async {
    final db = await database;
    await db.update(
      tableUsers,
      {columnUserLastLoginAt: DateTime.now().toIso8601String()},
      where: '$columnUserId = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updateUserSettings(int userId, String settings) async {
    final db = await database;
    await db.update(
      tableUsers,
      {columnUserSettings: settings},
      where: '$columnUserId = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updateVipDays(int userId, int days) async {
    final db = await database;
    await db.update(
      tableUsers,
      {columnUserVipDays: days},
      where: '$columnUserId = ?',
      whereArgs: [userId],
    );
  }

  // ======================================
  //             收藏夹
  // ======================================
  Future<bool> addFavorite(
      int userId,
      int sectionId,
      int questionNum, {
        String? note,
        DateTime? createdAt,
        DateTime? updatedAt,
        int isDeleted = 0,
      }) async {
    final db = await database;
    try {
      final id = await db.insert(
        tableFavorites,
        {
          columnFavUserId: userId,
          columnFavSectionId: sectionId,
          columnFavQuestionNum: questionNum,
          columnFavCreatedAt:
              (createdAt ?? DateTime.now()).toIso8601String(),
          columnFavNote: note,
          columnFavIsDeleted: isDeleted,
          columnFavUpdatedAt:
              (updatedAt ?? createdAt ?? DateTime.now()).toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
          'addFavorite insertId=$id userId=$userId sectionId=$sectionId question=$questionNum');
      if (id == 0) {
        final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM $tableFavorites WHERE $columnFavUserId = ? AND $columnFavSectionId = ? AND $columnFavQuestionNum = ?',
            [userId, sectionId, questionNum]));
        print('addFavorite existing count=$count');
        return count != null && count > 0;
      }
      return id > 0;
    } catch (e) {
      print('addFavorite error: $e');
      return false;
    }
  }

  Future<bool> removeFavorite(
      int userId, int sectionId, int questionNum) async {
    final db = await database;
    try {
      final count = await db.update(
        tableFavorites,
        {
          columnFavIsDeleted: 1,
          columnFavUpdatedAt: DateTime.now().toIso8601String(),
        },
        where:
            '$columnFavUserId = ? AND $columnFavSectionId = ? AND $columnFavQuestionNum = ?',
        whereArgs: [userId, sectionId, questionNum],
      );
      print(
          'removeFavorite updateCount=$count userId=$userId sectionId=$sectionId question=$questionNum');
      return count >= 0;
    } catch (e) {
      print('removeFavorite error: $e');
      return false;
    }
  }

  Future<bool> isFavorite(
      int userId, int sectionId, int questionNum) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $tableFavorites WHERE $columnFavUserId = ? AND $columnFavSectionId = ? AND $columnFavQuestionNum = ? AND $columnFavIsDeleted = 0',
        [userId, sectionId, questionNum]));
    return count != null && count > 0;
  }

  Future<List<Map<String, dynamic>>> getFavoriteQuestions(int userId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT q.*, s.$sectionImagePath as image_url, f.$columnFavCreatedAt as favorite_time, f.$columnFavNote as favorite_note
      FROM $tableQuiz q
      LEFT JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      INNER JOIN $tableFavorites f ON q.$quizSectionId = f.$columnFavSectionId
                                 AND q.$quizQuestionNumber = f.$columnFavQuestionNum
      WHERE f.$columnFavUserId = ? AND f.$columnFavIsDeleted = 0
    ''', [userId]);
  }

  // ======================================
  //             错题本
  // ======================================
  Future<void> addWrongAnswer(
      int userId,
      int sectionId,
      int questionNum, {
        int? historyId,
        String? note,
        DateTime? createdAt,
        DateTime? updatedAt,
        int isDeleted = 0,
        int? id,
      }) async {
    final db = await database;
    final chapterId = await _getChapterIdForSection(db, sectionId);
    final data = {
      columnWrongUserId: userId,
      columnWrongSectionId: sectionId,
      columnWrongQuestionNum: questionNum,
      columnWrongCreatedAt:
          (createdAt ?? DateTime.now()).toIso8601String(),
      columnWrongNote: note,
      columnWrongHistoryId: historyId,
      columnWrongChapterId: chapterId,
      columnWrongSubsectionId: sectionId,
      columnWrongIsDeleted: isDeleted,
      columnWrongUpdatedAt:
          (updatedAt ?? createdAt ?? DateTime.now()).toIso8601String(),
    };
    if (id != null) {
      data[columnWrongId] = id;
    }
    await db.insert(
      tableWrongAnswers,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _getChapterIdForSection(Database db, int sectionId) async {
    final res = await db.query(tableSection,
        columns: [sectionChapterId],
        where: '$sectionSectionId = ?',
        whereArgs: [sectionId],
        limit: 1);
    if (res.isNotEmpty && res.first[sectionChapterId] != null) {
      return res.first[sectionChapterId] as int;
    }
    return 0;
  }

  Future<void> removeWrongAnswer(
      int userId, int sectionId, int questionNum) async {
    final db = await database;
    await db.update(
      tableWrongAnswers,
      {
        columnWrongIsDeleted: 1,
        columnWrongUpdatedAt: DateTime.now().toIso8601String(),
      },
      where:
          '$columnWrongUserId = ? AND $columnWrongSectionId = ? AND $columnWrongQuestionNum = ?',
      whereArgs: [userId, sectionId, questionNum],
    );
  }

  Future<List<Map<String, dynamic>>> getWrongAnswerQuestions(int userId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT q.*, s.image_path as image_url, w.$columnWrongCreatedAt as wrong_time,
             w.$columnWrongNote as wrong_note, w.$columnWrongHistoryId as history_id
      FROM $tableWrongAnswers w
      INNER JOIN $tableQuiz q ON q.$quizSectionId = w.$columnWrongSectionId
         AND q.$quizQuestionNumber = w.$columnWrongQuestionNum
      LEFT JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      WHERE w.$columnWrongUserId = ? AND w.$columnWrongIsDeleted = 0
      ORDER BY w.$columnWrongCreatedAt DESC
    ''', [userId]);
  }

  Future<void> clearWrongAnswers(int userId) async {
    final db = await database;
    await db.update(
      tableWrongAnswers,
      {
        columnWrongIsDeleted: 1,
        columnWrongUpdatedAt: DateTime.now().toIso8601String(),
      },
      where: '$columnWrongUserId = ?',
      whereArgs: [userId],
    );
  }

  Future<List<Map<String, dynamic>>> getWrongAnswersByHistory(int historyId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT q.*, s.image_path as image_url, w.$columnWrongCreatedAt as wrong_time,
             w.$columnWrongNote as wrong_note, w.$columnWrongHistoryId as history_id
      FROM $tableWrongAnswers w
      INNER JOIN $tableQuiz q ON q.$quizSectionId = w.$columnWrongSectionId
         AND q.$quizQuestionNumber = w.$columnWrongQuestionNum
      LEFT JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      WHERE w.$columnWrongHistoryId = ? AND w.$columnWrongIsDeleted = 0
      ORDER BY w.$columnWrongCreatedAt DESC
    ''', [historyId]);
  }

  /// 保存一次完整的测验记录，包括历史记录、每题结果与错题
  Future<int> saveQuizAttempt(
    int userId,
    List<Map<String, dynamic>> questionMaps,
    List<int?> userAnswers,
    List<bool?> answerResults, {
    required bool isRandom,
    required int usedTime,
  }) async {
    final db = await database;
    return await db.transaction((txn) async {
      final historyId = await txn.insert(tableQuizHistory, {
        columnHistoryUserId: userId,
        columnHistoryScore:
            answerResults.where((r) => r == true).length,
        columnHistoryTotalQuestions: questionMaps.length,
        columnHistoryCompletedAt: DateTime.now().toIso8601String(),
        columnHistoryUsedTime: usedTime,
        columnHistoryMode: isRandom ? 'random' : 'practice',
        columnHistoryAccuracy:
            answerResults.where((r) => r == true).length /
                (questionMaps.isEmpty ? 1 : questionMaps.length),
      });
      final sectionIds = questionMaps
          .map((q) => q['section_id'] as int)
          .toSet()
          .toList();
      final sectionChapterMap = <int, int>{};
      for (final sid in sectionIds) {
        final res = await txn.query(tableSection,
            columns: [sectionChapterId],
            where: '$sectionSectionId = ?',
            whereArgs: [sid],
            limit: 1);
        sectionChapterMap[sid] =
            res.isNotEmpty && res.first[sectionChapterId] != null
                ? res.first[sectionChapterId] as int
                : 0;
      }

      final batch = txn.batch();
      for (int i = 0; i < questionMaps.length; i++) {
        final q = questionMaps[i];
        final sectionId = q['section_id'] as int;
        final questionNum = q['question_number'] as int;
        final chapterId = sectionChapterMap[sectionId] ?? 0;
        batch.insert(tableHistoryQuestions, {
          columnHQHistoryId: historyId,
          columnHQSectionId: sectionId,
          columnHQQuestionNum: questionNum,
          columnHQUserAnswer: userAnswers[i],
        });
        if (answerResults[i] == false) {
          batch.insert(
            tableWrongAnswers,
            {
              columnWrongUserId: userId,
              columnWrongSectionId: sectionId,
              columnWrongQuestionNum: questionNum,
              columnWrongCreatedAt: DateTime.now().toIso8601String(),
              columnWrongHistoryId: historyId,
              columnWrongChapterId: chapterId,
              columnWrongSubsectionId: sectionId,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
      return historyId;
    });
  }

  // ======================================
  //             做题历史
  // ======================================
  Future<int> addQuizHistory(int userId, int score, int totalQuestions,
      {int? usedTime,
      String? mode,
      double? accuracy,
      DateTime? completedAt,
      int? id}) async {
    final db = await database;
    final data = {
      columnHistoryUserId: userId,
      columnHistoryScore: score,
      columnHistoryTotalQuestions: totalQuestions,
      columnHistoryCompletedAt:
          (completedAt ?? DateTime.now()).toIso8601String(),
      columnHistoryUsedTime: usedTime,
      columnHistoryMode: mode,
      columnHistoryAccuracy: accuracy,
    };
    if (id != null) {
      data[columnHistoryId] = id;
    }
    return db.insert(tableQuizHistory, data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getQuizHistory(int userId) async {
    final db = await database;
    return db.query(
      tableQuizHistory,
      where: '$columnHistoryUserId = ?',
      whereArgs: [userId],
      orderBy: '$columnHistoryCompletedAt DESC',
    );
  }

  Future<Map<String, dynamic>?> getQuizHistoryById(int historyId) async {
    final db = await database;
    final res = await db.query(tableQuizHistory,
        where: '$columnHistoryId = ?', whereArgs: [historyId], limit: 1);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<List<Map<String, dynamic>>> getFavoritesRaw(int userId) async {
    final db = await database;
    return db.query(tableFavorites,
        where: '$columnFavUserId = ?', whereArgs: [userId]);
  }

  Future<List<Map<String, dynamic>>> getWrongAnswersRaw(int userId) async {
    final db = await database;
    return db.query(tableWrongAnswers,
        where: '$columnWrongUserId = ?', whereArgs: [userId]);
  }

  Future<void> trimQuizHistory(int userId, int limit) async {
    final db = await database;
    await db.delete(tableQuizHistory,
        where:
            '$columnHistoryId NOT IN (SELECT $columnHistoryId FROM $tableQuizHistory WHERE $columnHistoryUserId = ? ORDER BY $columnHistoryCompletedAt DESC LIMIT ?)',
        whereArgs: [userId, limit]);
  }

  Future<void> addHistoryQuestion(int historyId, int sectionId, int questionNum,
      int? userAnswer) async {
    final db = await database;
    await db.insert(tableHistoryQuestions, {
      columnHQHistoryId: historyId,
      columnHQSectionId: sectionId,
      columnHQQuestionNum: questionNum,
      columnHQUserAnswer: userAnswer,
    });
  }

  Future<List<Map<String, dynamic>>> getHistoryQuestions(int historyId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT q.*, s.image_path as image_url, h.$columnHQUserAnswer as user_answer
      FROM $tableHistoryQuestions h
      INNER JOIN $tableQuiz q ON q.$quizSectionId = h.$columnHQSectionId
         AND q.$quizQuestionNumber = h.$columnHQQuestionNum
      LEFT JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
      WHERE h.$columnHQHistoryId = ?
      ORDER BY h.$columnHQId
    ''', [historyId]);
  }

  // ======================================
  //             更换库后的新增方法
  // ======================================

  Future<List<Map<String, dynamic>>> getQuestionsWithSectionImage(int sectionId) async {
    final db = await database;
    return db.rawQuery('''
    SELECT q.*, s.image_path as section_image
    FROM $tableQuiz q
    LEFT JOIN $tableSection s ON q.section_id = s.section_id
    WHERE q.section_id = ?
    ORDER BY q.question_number
  ''', [sectionId]);
  }

  /// 随机获取所有题目，并带上 section 的图片路径
  Future<List<Map<String, dynamic>>> getAllQuestionsRandomWithSectionImage() async {
    final db = await database;
    return db.rawQuery('''
    SELECT q.*, s.image_path as image_url
    FROM $tableQuiz q
    LEFT JOIN $tableSection s ON q.$quizSectionId = s.$sectionSectionId
    ORDER BY RANDOM()
  ''');
  }


  // ======================================
  //             通用操作
  // ======================================
  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  // ======================================
  //             通用关闭
  // ======================================
  Future close() async {
    await _db?.close();
    _db = null;
  }
}
