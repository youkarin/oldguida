import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Screen/General/dictionary_detail_screen.dart';
import 'package:italian_driving_app/Screen/General/dictionary_screen.dart';
import 'package:italian_driving_app/Screen/Homepage.dart';
import 'package:italian_driving_app/Services/keyword_repository.dart';
import 'package:italian_driving_app/models/keyword_model.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late KeywordRepository repository;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'OldGuida',
      packageName: 'italian_driving_app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await _createSchema(database);
    await _insertFixture(database);
    repository = KeywordRepository(databaseProvider: () async => database);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('shows the complete dictionary on first load', (tester) async {
    await tester.pumpWidget(_app(DictionaryScreen(repository: repository)));
    await _flushDatabaseFutures(tester);

    expect(find.text('驾考词典'), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byTooltip('搜索词典'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'precedenza'), findsOneWidget);
    expect(find.text('名词'), findsNWidgets(2));
    expect(find.text('优先权；先行权'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'semaforo'), findsOneWidget);
  });

  testWidgets('debounces Italian search and opens the complete entry',
      (tester) async {
    await tester.pumpWidget(_app(DictionaryScreen(repository: repository)));
    await _flushDatabaseFutures(tester);

    await tester.enterText(find.byType(SearchBar), 'precedenza');
    await tester.pump(const Duration(milliseconds: 199));
    expect(find.text('semaforo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await _flushDatabaseFutures(tester);

    expect(find.widgetWithText(ListTile, 'precedenza'), findsOneWidget);
    expect(find.text('semaforo'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'precedenza'));
    await tester.pump();
    await _flushDatabaseFutures(tester);
    await tester.pumpAndSettle();

    expect(find.text('词条详情'), findsOneWidget);
    expect(find.text('优先权；先行权'), findsOneWidget);
    expect(find.text('表示车辆或道路使用者享有先行的权利。'), findsOneWidget);
    expect(find.text('常见词形与搭配'), findsOneWidget);
    expect(find.text('dare precedenza'), findsOneWidget);
    expect(find.text('例句'), findsOneWidget);
    expect(find.text('La precedenza spetta al veicolo.'), findsOneWidget);
    expect(find.text('车辆享有优先权。'), findsOneWidget);
  });

  testWidgets('searches Chinese translation text', (tester) async {
    await tester.pumpWidget(_app(DictionaryScreen(repository: repository)));
    await _flushDatabaseFutures(tester);

    await tester.enterText(find.byType(SearchBar), '红绿灯');
    await tester.pump(const Duration(milliseconds: 200));
    await _flushDatabaseFutures(tester);

    expect(find.widgetWithText(ListTile, 'semaforo'), findsOneWidget);
    expect(find.text('precedenza'), findsNothing);
  });

  testWidgets('trimmed empty input and clear restore all immediately',
      (tester) async {
    await tester.pumpWidget(_app(DictionaryScreen(repository: repository)));
    await _flushDatabaseFutures(tester);

    await tester.enterText(find.byType(SearchBar), 'precedenza');
    await tester.pump(const Duration(milliseconds: 200));
    await _flushDatabaseFutures(tester);
    expect(find.text('semaforo'), findsNothing);

    await tester.enterText(find.byType(SearchBar), '   ');
    await tester.pump();
    await _flushDatabaseFutures(tester);
    expect(find.text('semaforo'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'precedenza');
    await tester.pump(const Duration(milliseconds: 200));
    await _flushDatabaseFutures(tester);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    await _flushDatabaseFutures(tester);

    expect(find.text('precedenza'), findsOneWidget);
    expect(find.text('semaforo'), findsOneWidget);
  });

  testWidgets('keyboard submit searches without waiting for debounce',
      (tester) async {
    await tester.pumpWidget(_app(DictionaryScreen(repository: repository)));
    await _flushDatabaseFutures(tester);

    await tester.enterText(find.byType(SearchBar), 'semaforo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await _flushDatabaseFutures(tester);

    expect(find.widgetWithText(ListTile, 'semaforo'), findsOneWidget);
    expect(find.text('precedenza'), findsNothing);
  });

  testWidgets('shows the no results state', (tester) async {
    await tester.pumpWidget(_app(DictionaryScreen(repository: repository)));
    await _flushDatabaseFutures(tester);

    await tester.enterText(find.byType(SearchBar), 'inesistente');
    await tester.pump(const Duration(milliseconds: 200));
    await _flushDatabaseFutures(tester);

    expect(find.text('未找到相关词条'), findsOneWidget);
  });

  testWidgets('keeps the scaffold while loading and retries list errors',
      (tester) async {
    var attempts = 0;
    final firstAttempt = Completer<List<Keyword>>();
    final fake = _StrictKeywordRepository(
      searchHandler: (_) {
        attempts++;
        if (attempts == 1) {
          return firstAttempt.future;
        }
        return Future.value([_precedenza]);
      },
    );

    await tester.pumpWidget(_app(DictionaryScreen(repository: fake)));
    await tester.pump();
    expect(find.text('驾考词典'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    firstAttempt.completeError(StateError('offline failure'));
    await tester.pumpAndSettle();

    expect(find.text('词典加载失败'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pumpAndSettle();

    expect(find.text('precedenza'), findsOneWidget);
    expect(find.text('词典加载失败'), findsNothing);
  });

  testWidgets('a late stale search cannot overwrite newer results',
      (tester) async {
    final oldResult = Completer<List<Keyword>>();
    final newResult = Completer<List<Keyword>>();
    final fake = _StrictKeywordRepository(
      searchHandler: (query) => switch (query) {
        '' => Future.value([_precedenza, _semaforo]),
        'vecchio' => oldResult.future,
        'nuovo' => newResult.future,
        _ => throw StateError('Unexpected query: $query'),
      },
    );

    await tester.pumpWidget(_app(DictionaryScreen(repository: fake)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'vecchio');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(SearchBar), 'nuovo');
    await tester.pump(const Duration(milliseconds: 200));

    newResult.complete([_semaforo]);
    await tester.pumpAndSettle();
    expect(find.text('semaforo'), findsOneWidget);
    oldResult.complete([_precedenza]);
    await tester.pumpAndSettle();

    expect(find.text('semaforo'), findsOneWidget);
    expect(find.text('precedenza'), findsNothing);
  });

  testWidgets('dispose cancels debounce and ignores a pending request',
      (tester) async {
    final pending = Completer<List<Keyword>>();
    final queries = <String>[];
    final fake = _StrictKeywordRepository(
      searchHandler: (query) {
        queries.add(query);
        if (query.isEmpty) return Future.value([_precedenza]);
        return pending.future;
      },
    );

    await tester.pumpWidget(_app(DictionaryScreen(repository: fake)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'cancelled');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));
    expect(queries, ['']);

    await tester.pumpWidget(_app(DictionaryScreen(repository: fake)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'pending');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete([_semaforo]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('detail loads all sources concurrently and sorts filtered forms',
      (tester) async {
    final entry = Completer<Keyword?>();
    final forms = Completer<List<KeywordForm>>();
    final example = Completer<KeywordExample?>();
    final started = <String>[];
    final fake = _StrictKeywordRepository(
      byIdHandler: (id) {
        started.add('entry:$id');
        return entry.future;
      },
      formsHandler: () {
        started.add('forms');
        return forms.future;
      },
      exampleHandler: (id) {
        started.add('example:$id');
        return example.future;
      },
    );

    await tester.pumpWidget(
      _app(DictionaryDetailScreen(keywordId: 1, repository: fake)),
    );
    await tester.pump();

    expect(started, ['entry:1', 'forms', 'example:1']);
    expect(find.text('词条详情'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    entry.complete(_precedenza);
    forms.complete(const [
      KeywordForm(
        id: 3,
        keywordId: 1,
        form: 'precedenza',
        normalizedForm: 'precedenza',
      ),
      KeywordForm(
        id: 9,
        keywordId: 2,
        form: 'semafori',
        normalizedForm: 'semafori',
      ),
      KeywordForm(
        id: 2,
        keywordId: 1,
        form: 'dà precedenza',
        normalizedForm: 'dà precedenza',
      ),
      KeywordForm(
        id: 1,
        keywordId: 1,
        form: 'dare precedenza',
        normalizedForm: 'dare precedenza',
      ),
    ]);
    example.complete(_precedenzaExample);
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Chip>(find.byType(Chip))
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(labels, ['dare precedenza', 'dà precedenza', 'precedenza']);
    expect(find.text('semafori'), findsNothing);
  });

  testWidgets('detail preserves its scaffold for error and retry',
      (tester) async {
    var attempts = 0;
    final fake = _StrictKeywordRepository(
      byIdHandler: (_) {
        attempts++;
        if (attempts == 1) {
          return Future<Keyword?>.error(StateError('read failed'));
        }
        return Future.value(_precedenza);
      },
      formsHandler: () => Future.value(const []),
      exampleHandler: (_) => Future.value(null),
    );

    await tester.pumpWidget(
      _app(DictionaryDetailScreen(keywordId: 1, repository: fake)),
    );
    await tester.pumpAndSettle();

    expect(find.text('词条详情'), findsOneWidget);
    expect(find.text('词条加载失败'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pumpAndSettle();

    expect(find.text('precedenza'), findsOneWidget);
    expect(find.text('暂无例句'), findsOneWidget);
  });

  testWidgets('detail handles not found and missing example states',
      (tester) async {
    await tester.pumpWidget(
      _app(
        DictionaryDetailScreen(
          key: const ValueKey('missing'),
          keywordId: 999,
          repository: repository,
        ),
      ),
    );
    await _flushDatabaseFutures(tester);
    expect(find.text('未找到该词条'), findsOneWidget);
    expect(find.text('词条详情'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        DictionaryDetailScreen(
          key: const ValueKey('without-example'),
          keywordId: 2,
          repository: repository,
        ),
      ),
    );
    await _flushDatabaseFutures(tester);
    expect(find.text('semaforo'), findsOneWidget);
    expect(find.text('暂无词形'), findsOneWidget);
    expect(find.text('暂无例句'), findsOneWidget);
  });

  testWidgets('detail remains scrollable on a small large-text viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        DictionaryDetailScreen(keywordId: 1, repository: repository),
        textScaler: const TextScaler.linear(2),
      ),
    );
    await _flushDatabaseFutures(tester);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows a balanced two-column route into the dictionary',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          dictionaryScreenBuilder: (_) =>
              DictionaryScreen(repository: repository),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OldGuida'), findsOneWidget);
    expect(find.byIcon(Icons.translate), findsOneWidget);
    expect(find.text('驾考词典'), findsOneWidget);
    final generalGrid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        generalGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisExtent, isNotNull);

    await tester.tap(find.text('驾考词典'));
    await tester.pump();
    await _flushDatabaseFutures(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DictionaryScreen), findsOneWidget);
    expect(find.text('驾考词典'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

Widget _app(Widget home, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: home,
    ),
  );
}

Future<void> _flushDatabaseFutures(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

const _precedenza = Keyword(
  id: 1,
  term: 'precedenza',
  normalizedTerm: 'precedenza',
  partOfSpeech: '名词',
  translation: '优先权；先行权',
  note: '表示车辆或道路使用者享有先行的权利。',
  frequency: 100,
  sortOrder: 1,
);

const _semaforo = Keyword(
  id: 2,
  term: 'semaforo',
  normalizedTerm: 'semaforo',
  partOfSpeech: '名词',
  translation: '红绿灯；交通信号灯',
  note: '用于控制道路交通。',
  frequency: 80,
  sortOrder: 2,
);

const _precedenzaExample = KeywordExample(
  questionId: 147,
  question: 'La precedenza spetta al veicolo.',
  translation: '车辆享有优先权。',
);

final class _StrictKeywordRepository extends KeywordRepository {
  _StrictKeywordRepository({
    this.searchHandler,
    this.byIdHandler,
    this.formsHandler,
    this.exampleHandler,
  }) : super(
          databaseProvider: () =>
              Future<Database>.error(StateError('Unexpected database use')),
        );

  final Future<List<Keyword>> Function(String query)? searchHandler;
  final Future<Keyword?> Function(int id)? byIdHandler;
  final Future<List<KeywordForm>> Function()? formsHandler;
  final Future<KeywordExample?> Function(int id)? exampleHandler;

  @override
  Future<List<Keyword>> search(String query) =>
      (searchHandler ?? _unexpectedSearch)(query);

  @override
  Future<Keyword?> byId(int id) => (byIdHandler ?? _unexpectedById)(id);

  @override
  Future<List<KeywordForm>> forms() => (formsHandler ?? _unexpectedForms)();

  @override
  Future<KeywordExample?> exampleFor(int keywordId) =>
      (exampleHandler ?? _unexpectedExample)(keywordId);

  static Future<List<Keyword>> _unexpectedSearch(String query) =>
      Future.error(StateError('Unexpected search: $query'));

  static Future<Keyword?> _unexpectedById(int id) =>
      Future.error(StateError('Unexpected byId: $id'));

  static Future<List<KeywordForm>> _unexpectedForms() =>
      Future.error(StateError('Unexpected forms call'));

  static Future<KeywordExample?> _unexpectedExample(int id) =>
      Future.error(StateError('Unexpected exampleFor: $id'));
}

Future<void> _createSchema(Database database) async {
  await database.execute('''
    CREATE TABLE quiz (
      id INTEGER PRIMARY KEY,
      question TEXT,
      translation TEXT
    )
  ''');
  await database.execute('''
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
  await database.execute('''
    CREATE TABLE keyword_forms (
      id INTEGER PRIMARY KEY,
      keyword_id INTEGER NOT NULL,
      form TEXT NOT NULL,
      normalized_form TEXT NOT NULL UNIQUE
    )
  ''');
  await database.execute('''
    CREATE TABLE keyword_examples (
      id INTEGER PRIMARY KEY,
      keyword_id INTEGER NOT NULL,
      question_id INTEGER NOT NULL,
      rank INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

Future<void> _insertFixture(Database database) async {
  for (final keyword in [_precedenza, _semaforo]) {
    await database.insert('keyword_dictionary', {
      'id': keyword.id,
      'term': keyword.term,
      'normalized_term': keyword.normalizedTerm,
      'part_of_speech': keyword.partOfSpeech,
      'translation': keyword.translation,
      'note': keyword.note,
      'frequency': keyword.frequency,
      'sort_order': keyword.sortOrder,
    });
  }
  await database.insert('keyword_forms', {
    'id': 1,
    'keyword_id': 1,
    'form': 'precedenza',
    'normalized_form': 'precedenza',
  });
  await database.insert('keyword_forms', {
    'id': 2,
    'keyword_id': 1,
    'form': 'dare precedenza',
    'normalized_form': 'dare precedenza',
  });
  await database.insert('quiz', {
    'id': _precedenzaExample.questionId,
    'question': _precedenzaExample.question,
    'translation': _precedenzaExample.translation,
  });
  await database.insert('keyword_examples', {
    'id': 1,
    'keyword_id': 1,
    'question_id': _precedenzaExample.questionId,
    'rank': 0,
  });
}
