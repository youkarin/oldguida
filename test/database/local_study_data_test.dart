import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/Services/local_study_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late DatabaseHelper helper;
  late LocalStudyData local;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    helper = DatabaseHelper.forTesting(
      openDatabase: () async => db,
      syncBundled: (_) async {},
    );
    await helper.database;
    local = LocalStudyData.forTesting(helper);
  });
  tearDown(() async => helper.close());

  Future<void> owner(int id, String name) async {
    await db.insert('users', {'id': id, 'username': name});
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    return {
      for (final table in ['favorites', 'wrong_answers', 'quiz_history', 'quiz_history_questions'])
        table: await db.query(table),
    };
  }

  test('fresh install and concurrent requests share a persistent local owner', () async {
    final ids = await Future.wait(List.generate(5, (_) => local.ensureOwner()));
    expect(ids.first, isNotNull);
    expect(ids.toSet(), hasLength(1));
    expect(await db.query('users'), hasLength(1));
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), ids.first);
  });

  test('single legacy guest keeps its actual ID, not a hardcoded one', () async {
    await owner(17, 'guest');
    expect(await local.ensureOwner(), 17);
    expect(await db.query('users'), hasLength(1));
  });

  test('stored legacy username preserves all rows and current visibility', () async {
    await owner(17, 'guest');
    await owner(42, 'legacy');
    SharedPreferences.setMockInitialValues({'username': 'legacy'});
    for (final id in [17, 42]) {
      await db.insert('favorites', {'user_id': id, 'section_id': 1, 'question_number': 1, 'note': 'keep $id'});
      await db.insert('wrong_answers', {'user_id': id, 'section_id': 1, 'question_number': 1, 'wrong_count': 8});
      await db.insert('quiz_history', {'id': id, 'user_id': id, 'score': 7});
      await db.insert('quiz_history_questions', {'history_id': id, 'section_id': 1, 'question_number': 1});
    }
    final before = await snapshot();
    final users = await db.query('users');
    expect(await local.ensureOwner(), 42);
    expect((await helper.getQuizHistory(42)).single['user_id'], 42);
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 42);
    expect(await snapshot(), before);
    expect(await db.query('users'), users);
  });

  test('ambiguous historical owners get independent persistent scope', () async {
    await owner(17, 'guest');
    await owner(42, 'other');
    await db.insert('favorites', {'user_id': 17});
    final before = await snapshot();
    expect(await local.ensureOwner(), 43);
    expect(await db.query('users'), hasLength(3));
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 43);
    expect(await snapshot(), before);
  });

  test('stale username creates new scope instead of adopting old user', () async {
    await owner(17, 'guest');
    SharedPreferences.setMockInitialValues({'username': 'missing'});
    expect(await local.ensureOwner(), 18);
    expect(await db.query('users'), hasLength(2));
  });

  test('stale numeric choice does not fall back to valid legacy username', () async {
    await owner(17, 'guest');
    SharedPreferences.setMockInitialValues({'local_study_owner_id': 88, 'username': 'guest'});
    expect(await local.ensureOwner(), 18);
    expect((await db.query('users')).first['id'], 17);
  });

  test('NULL ownership creates new scope without modifying old rows', () async {
    await owner(17, 'guest');
    for (final table in ['favorites', 'wrong_answers', 'quiz_history']) {
      await db.insert(table, {'user_id': null});
    }
    final before = await snapshot();
    expect(await local.ensureOwner(), 18);
    expect(await snapshot(), before);
  });

  test('valid explicit owner preserves scope despite orphan and NULL rows', () async {
    await owner(17, 'guest');
    await owner(42, 'legacy');
    await db.insert('favorites', {'user_id': 88});
    await db.insert('wrong_answers', {'user_id': null});
    final before = await snapshot();
    final users = await db.query('users');
    SharedPreferences.setMockInitialValues({'username': 'legacy'});
    expect(await local.ensureOwner(), 42);
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 42);
    expect(await snapshot(), before);
    expect(await db.query('users'), users);
  });

  test('orphan IDs are reserved even when no users exist', () async {
    await db.insert('favorites', {'user_id': 88, 'section_id': 1, 'question_number': 1});
    expect(await local.ensureOwner(), 89);
    expect(await db.query('users'), hasLength(1));
    expect((await db.query('favorites')).single['user_id'], 88);
  });

  test('fresh install is empty and favorites wrongs history all save', () async {
    final id = (await local.ensureOwner())!;
    for (final rows in (await snapshot()).values) {
      expect(rows, isEmpty);
    }
    await db.execute('CREATE TABLE section (section_id INTEGER, chapter_id INTEGER)');
    await db.insert('section', {'section_id': 1, 'chapter_id': 2});
    expect(await helper.addFavorite(id, 1, 1), isTrue);
    expect(await helper.isFavorite(id, 1, 1), isTrue);
    final history = await helper.saveQuizAttempt(id,
        [{'section_id': 1, 'question_number': 1}], [0], [false],
        isRandom: false, usedTime: 12);
    expect((await db.query('wrong_answers')).single['user_id'], id);
    expect((await helper.getQuizHistory(id)).single['id'], history);
    expect((await db.query('quiz_history_questions')).single['history_id'], history);
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), id);
    expect(await helper.isFavorite(id, 1, 1), isTrue);
  });

  test('all learning IDs and occupied local names are avoided', () async {
    await owner(17, 'local');
    await owner(18, 'local-901');
    await db.insert('favorites', {'user_id': 300});
    await db.insert('wrong_answers', {'user_id': 900});
    await db.insert('quiz_history', {'user_id': 500});
    final before = await snapshot();
    final id = await local.ensureOwner();
    expect(id, 901);
    expect((await db.query('users', where: 'id = ?', whereArgs: [id])).single['username'], 'local-901-1');
    expect(await snapshot(), before);
  });

  test('false and throwing preference writes never allocate extra owners', () async {
    await owner(17, 'a');
    await owner(42, 'b');
    for (final throws in [false, true]) {
      final failing = LocalStudyData.forTesting(helper, persistOwner: (_) async {
        if (throws) throw StateError('preferences unavailable');
        return false;
      });
      expect(await failing.ensureOwner(), 43);
      expect(await failing.ensureOwner(), 43);
      SharedPreferences.setMockInitialValues({'local_study_owner_id': 999, 'username': 'a'});
    }
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 43);
    expect(await db.query('users'), hasLength(3));
  });

  test('valid numeric choice takes precedence over legacy username', () async {
    await owner(17, 'a');
    await owner(42, 'b');
    SharedPreferences.setMockInitialValues({'local_study_owner_id': 17, 'username': 'b'});
    expect(await local.ensureOwner(), 17);
    SharedPreferences.setMockInitialValues({});
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 17);
  });

  test('independent service instances share transaction marker', () async {
    await owner(17, 'a');
    await owner(42, 'b');
    final ids = await Future.wait(List.generate(5,
        (_) => LocalStudyData.forTesting(helper).ensureOwner()));
    expect(ids.toSet(), {43});
    expect(await db.query('users'), hasLength(3));
  });

  test('stale database marker creates independent owner only once', () async {
    await owner(17, 'a');
    expect(await local.ensureOwner(), 17);
    await db.delete('users', where: 'id = ?', whereArgs: [17]);
    await db.insert('favorites', {'user_id': 17});
    await owner(42, 'b');
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 43);
    expect(await LocalStudyData.forTesting(helper).ensureOwner(), 43);
    expect((await db.query('favorites')).single['user_id'], 17);
  });

  test('local saves keep older histories and details across owners', () async {
    await owner(17, 'guest');
    await db.execute('CREATE TABLE section (section_id INTEGER, chapter_id INTEGER)');
    for (var i = 1; i <= 60; i++) {
      await db.insert('quiz_history', {'id': i, 'user_id': i.isEven ? 17 : 42});
      await db.insert('quiz_history_questions', {'history_id': i});
    }
    final id = await helper.saveQuizAttempt(17, [], [], [], isRandom: true, usedTime: 1);
    expect(id, greaterThan(60));
    expect(await db.query('quiz_history'), hasLength(61));
    expect(await db.query('quiz_history_questions'), hasLength(60));
  });
}
