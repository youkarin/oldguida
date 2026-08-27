import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Services/keyword_repository.dart';
import 'package:italian_driving_app/Services/keyword_service.dart';
import 'package:italian_driving_app/models/keyword_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('version zero loads lazily and reuses one keyword/form snapshot',
      () async {
    final repository = _FakeKeywordRepository(
      version: 0,
      keywords: [_keyword(1, 'auto')],
      forms: [_form(1, 1, 'auto')],
    );
    final service = KeywordService(repository: repository);

    expect(repository.versionCalls, 0);
    expect(repository.allCalls, 0);
    expect(repository.formsCalls, 0);

    expect(
      (await service.matchQuestion(questionId: 1, text: 'auto'))
          .single
          .keywordId,
      1,
    );
    expect(
      (await service.matchQuestion(questionId: 2, text: 'AUTO'))
          .single
          .keywordId,
      1,
    );

    expect(repository.versionCalls, greaterThanOrEqualTo(2));
    expect(repository.allCalls, 1);
    expect(repository.formsCalls, 1);
  });

  test('a dictionary version change atomically replaces matcher data',
      () async {
    final repository = _FakeKeywordRepository(
      version: 1,
      keywords: [_keyword(1, 'auto')],
      forms: [_form(1, 1, 'auto')],
    );
    final service = KeywordService(repository: repository);

    expect(
      (await service.matchQuestion(
        questionId: 7,
        text: 'auto strada',
      ))
          .map((match) => match.keywordId),
      [1],
    );

    repository
      ..version = 2
      ..keywordData = [_keyword(2, 'strada')]
      ..formData = [_form(2, 2, 'strada')];

    expect(
      (await service.matchQuestion(
        questionId: 7,
        text: 'auto strada',
      ))
          .map((match) => match.keywordId),
      [2],
    );
    expect(repository.allCalls, 2);
    expect(repository.formsCalls, 2);
  });

  test('concurrent first matches share one repository load', () async {
    final gate = Completer<void>();
    final repository = _FakeKeywordRepository(
      version: 3,
      keywords: [_keyword(1, 'auto')],
      forms: [_form(1, 1, 'auto')],
      loadGate: gate,
    );
    final service = KeywordService(repository: repository);

    final pending = <Future<List<KeywordMatch>>>[
      service.matchQuestion(questionId: 1, text: 'auto'),
      service.matchQuestion(questionId: 2, text: 'auto'),
      service.matchQuestion(questionId: 3, text: 'auto'),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(repository.versionCalls, 1);
    expect(repository.allCalls, 1);
    expect(repository.formsCalls, 1);

    gate.complete();
    final results = await Future.wait(pending);

    expect(results.every((matches) => matches.single.keywordId == 1), isTrue);
    expect(repository.allCalls, 1);
    expect(repository.formsCalls, 1);
  });

  test('failed reload publishes no partial matcher and can be retried',
      () async {
    final repository = _FakeKeywordRepository(
      version: 1,
      keywords: [_keyword(1, 'auto')],
      forms: [_form(1, 1, 'auto')],
    );
    final service = KeywordService(repository: repository);
    await service.matchQuestion(questionId: 1, text: 'auto strada');

    repository
      ..version = 2
      ..keywordData = [_keyword(2, 'strada')]
      ..formData = [_form(2, 2, 'strada')]
      ..failNextForms = true;

    await expectLater(
      service.matchQuestion(questionId: 1, text: 'auto strada'),
      throwsA(isA<StateError>()),
    );

    expect(
      (await service.matchQuestion(
        questionId: 1,
        text: 'auto strada',
      ))
          .map((match) => match.keywordId),
      [2],
    );
    expect(repository.allCalls, 3);
    expect(repository.formsCalls, 3);
  });

  test('keywordById keeps repository found and missing semantics', () async {
    final repository = _FakeKeywordRepository(
      version: 1,
      keywords: [_keyword(1, 'auto')],
      forms: [_form(1, 1, 'auto')],
    );
    final service = KeywordService(repository: repository);

    expect((await service.keywordById(1))?.term, 'auto');
    expect(await service.keywordById(999), isNull);
    expect(repository.byIdCalls, 2);
    expect(repository.versionCalls, 0);
    expect(repository.allCalls, 0);
    expect(repository.formsCalls, 0);
  });

  test('real read-only asset matches curated phrase and side keyword',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      File('assets/db/quiz.db').absolute.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    addTearDown(db.close);
    final repository = KeywordRepository(databaseProvider: () async => db);
    final service = KeywordService(repository: repository);
    final precedenceRow = (await db.query(
      'quiz',
      columns: ['id', 'question'],
      where: 'id = ?',
      whereArgs: [2140],
      limit: 1,
    ))
        .single;
    final sinistroRow = (await db.query(
      'quiz',
      columns: ['id', 'question'],
      where: 'id = ?',
      whereArgs: [4387],
      limit: 1,
    ))
        .single;

    final precedenceMatches = await service.matchQuestion(
      questionId: precedenceRow['id'] as int,
      text: precedenceRow['question'] as String,
    );
    final sinistroMatches = await service.matchQuestion(
      questionId: sinistroRow['id'] as int,
      text: sinistroRow['question'] as String,
    );

    expect(
      precedenceMatches.map((match) => match.matchedText),
      contains('dare precedenza'),
    );
    expect(
      precedenceMatches.map((match) => match.keyword.term),
      contains('dare la precedenza'),
    );
    expect(
      sinistroMatches.map((match) => match.matchedText),
      contains('sinistro'),
    );
    expect(
      sinistroMatches.map((match) => match.keyword.term),
      contains('sinistro'),
    );
  });
}

final class _FakeKeywordRepository extends KeywordRepository {
  _FakeKeywordRepository({
    required this.version,
    required List<Keyword> keywords,
    required List<KeywordForm> forms,
    this.loadGate,
  })  : keywordData = keywords,
        formData = forms,
        super(databaseProvider: _unusedDatabaseProvider);

  int version;
  List<Keyword> keywordData;
  List<KeywordForm> formData;
  final Completer<void>? loadGate;
  bool failNextForms = false;
  int versionCalls = 0;
  int allCalls = 0;
  int formsCalls = 0;
  int byIdCalls = 0;

  @override
  Future<int> dictionaryVersion() async {
    versionCalls++;
    return version;
  }

  @override
  Future<List<Keyword>> all() async {
    allCalls++;
    await loadGate?.future;
    return List.unmodifiable(keywordData);
  }

  @override
  Future<List<KeywordForm>> forms() async {
    formsCalls++;
    await loadGate?.future;
    if (failNextForms) {
      failNextForms = false;
      throw StateError('forms load failed');
    }
    return List.unmodifiable(formData);
  }

  @override
  Future<Keyword?> byId(int id) async {
    byIdCalls++;
    for (final keyword in keywordData) {
      if (keyword.id == id) {
        return keyword;
      }
    }
    return null;
  }
}

Future<Database> _unusedDatabaseProvider() =>
    throw StateError('fake repository database provider must not be used');

Keyword _keyword(int id, String term) => Keyword(
      id: id,
      term: term,
      normalizedTerm: term,
      partOfSpeech: '名词',
      translation: '释义$id',
      note: '',
      frequency: 0,
      sortOrder: id,
    );

KeywordForm _form(int id, int keywordId, String form) => KeywordForm(
      id: id,
      keywordId: keywordId,
      form: form,
      normalizedForm: form,
    );
