import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Screen/General/dictionary_detail_screen.dart';
import 'package:italian_driving_app/Screen/General/final_score.dart';
import 'package:italian_driving_app/Services/keyword_repository.dart';
import 'package:italian_driving_app/Services/keyword_service.dart';
import 'package:italian_driving_app/Services/keyword_translation_settings.dart';
import 'package:italian_driving_app/models/keyword_model.dart';
import 'package:italian_driving_app/models/question_model.dart';
import 'package:italian_driving_app/widgets/keyword_question_text.dart';

void main() {
  const surfaces = <_SurfaceExpectation>[
    _SurfaceExpectation(
      path: 'lib/Screen/General/exam_general.dart',
      questionId: r'questionId:\s*question\.id\b',
      text: r'text:\s*question\.question\b',
      prefix: r"prefix:\s*'Q\$\{currentIndex \+ 1\}: '",
      styleMarker: 'fontSize: 20',
    ),
    _SurfaceExpectation(
      path: 'lib/Screen/General/question_list_screen.dart',
      questionId: r'questionId:\s*q\.id\b',
      text: r'text:\s*q\.question\b',
      styleMarker: 'fontSize: 18',
    ),
    _SurfaceExpectation(
      path: 'lib/Screen/General/favorites_screen.dart',
      questionId: r"questionId:\s*\(item\['id'\] as num\)\.toInt\(\)",
      text: r'text:\s*questionText\b',
      prefix: r"prefix:\s*'\$\{index \+ 1\}\. '",
      styleMarker: 'fontSize: 16',
    ),
    _SurfaceExpectation(
      path: 'lib/Screen/General/wrong_review_screen.dart',
      questionId: r"questionId:\s*\(item\['id'\] as num\)\.toInt\(\)",
      text: r'text:\s*questionText\b',
      styleMarker: 'height: 1.4',
    ),
    _SurfaceExpectation(
      path: 'lib/Screen/General/history_detail_screen.dart',
      questionId: r"questionId:\s*\(item\['id'\] as num\)\.toInt\(\)",
      text: r'text:\s*questionText\b',
      prefix: r"prefix:\s*'\$\{index \+ 1\}\. '",
      styleMarker: 'fontSize: 16',
    ),
    _SurfaceExpectation(
      path: 'lib/Screen/General/final_score.dart',
      questionId: r'questionId:\s*question\.id\b',
      text: r'text:\s*question\.question\b',
      prefix: r"prefix:\s*'题目 \$\{index \+ 1\}: '",
    ),
    _SurfaceExpectation(
      path: 'lib/Screen/DEBUG/quiz_actions.dart',
      questionId: r"questionId:\s*\(item\['id'\] as num\)\.toInt\(\)",
      text: r"text:\s*item\['question'\] as String",
      prefix: r'prefix:\s*"\$\{index \+ 1\}\. Q: "',
      styleMarker: 'fontWeight: FontWeight.bold',
    ),
  ];

  test('every question surface uses stable ids and navigable annotations', () {
    for (final surface in surfaces) {
      final source = File(surface.path).readAsStringSync();
      expect(
        RegExp(
          r"^import 'package:italian_driving_app/widgets/keyword_question_text.dart';$",
          multiLine: true,
        ).hasMatch(source),
        isTrue,
        reason: '${surface.path}: missing KeywordQuestionText import',
      );
      expect(
        RegExp(
          r"^import 'package:italian_driving_app/Screen/General/dictionary_detail_screen.dart';$",
          multiLine: true,
        ).hasMatch(source),
        isTrue,
        reason: '${surface.path}: missing DictionaryDetailScreen import',
      );
      expect(
        'KeywordQuestionText('.allMatches(source),
        isNotEmpty,
        reason: '${surface.path}: question text is not annotated',
      );
      expect(
        RegExp(surface.questionId).hasMatch(source),
        isTrue,
        reason: '${surface.path}: annotation does not use the stable quiz id',
      );
      expect(
        RegExp(surface.text).hasMatch(source),
        isTrue,
        reason: '${surface.path}: matcher does not receive only Italian text',
      );
      if (surface.prefix != null) {
        expect(
          RegExp(surface.prefix!).hasMatch(source),
          isTrue,
          reason: '${surface.path}: visible question prefix is not separate',
        );
      }
      if (surface.styleMarker != null) {
        expect(
          RegExp(
            'KeywordQuestionText\\([\\s\\S]*?style:\\s*const TextStyle\\([\\s\\S]*?'
            '${RegExp.escape(surface.styleMarker!)}[\\s\\S]*?onViewFullEntry:',
          ).hasMatch(source),
          isTrue,
          reason: '${surface.path}: existing question style was not retained',
        );
      }
      expect(
        RegExp(r'onViewFullEntry:\s*\(keywordId\)').hasMatch(source),
        isTrue,
        reason: '${surface.path}: missing full-entry callback',
      );
      expect(
        RegExp(r'if \(!context\.mounted\) return;').hasMatch(source),
        isTrue,
        reason: '${surface.path}: navigation is not context-safe',
      );
      expect(
        RegExp(
          r'Navigator\.(?:of\(context\)\.)?push\([\s\S]*?DictionaryDetailScreen\([\s\S]*?keywordId:\s*keywordId',
        ).hasMatch(source),
        isTrue,
        reason: '${surface.path}: callback does not push the selected entry',
      );
    }
  });

  test('map-backed surface queries retain the real quiz id', () {
    final source = File('lib/database/database_helper.dart').readAsStringSync();
    for (final method in const [
      'getQuestionsWithSectionImage',
      'getFavoriteQuestions',
      'getWrongAnswerQuestions',
      'getWrongAnswersByHistory',
      'getHistoryQuestions',
    ]) {
      final body = RegExp(
        'Future<List<Map<String, dynamic>>> $method\\b[\\s\\S]*?return db\\.rawQuery\\(\'\'\'[\\s\\S]*?SELECT q\\.\\*',
      );
      expect(
        body.hasMatch(source),
        isTrue,
        reason: '$method must project q.* so map rows contain quiz.id',
      );
    }
  });

  test('production screens contain no remaining raw Italian Text renderer', () {
    final offenders = <String>[];
    final rawQuestionText = RegExp(
      r'''Text\s*\(\s*(?:['"][^'"]*\$\{\s*)?(?:question\.question|q\.question|item\[['"]question['"]\]|questionText)''',
      multiLine: true,
    );
    for (final entity in Directory('lib/Screen').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in rawQuestionText.allMatches(source)) {
        offenders.add('${entity.path}:${_lineNumber(source, match.start)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'raw Italian question Text renderers: ${offenders.join(', ')}',
    );
  });

  testWidgets(
      'final score annotates only source text and opens detail after sheet action',
      (tester) async {
    final service = _RecordingLookup();
    final settings = KeywordTranslationSettings.forTest()..enabled.value = true;
    final repository = _DetailRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: FinalScorePage(
          duration: const Duration(seconds: 30),
          correctCount: 1,
          wrongCount: 0,
          questions: [
            Question(
              id: 91,
              sectionId: 2,
              questionNumber: 8,
              question: 'Dare precedenza.',
              translation: '必须让行。',
              explanation: '注意优先权。',
              answer: 1,
            ),
          ],
          userAnswers: const [1],
          keywordService: service,
          keywordSettings: settings,
          dictionaryRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final annotation = find.byType(KeywordQuestionText);
    expect(annotation, findsOneWidget);
    expect(service.questionIds, [91]);
    expect(service.texts, ['Dare precedenza.']);

    final text = tester.widget<Text>(
      find.descendant(of: annotation, matching: find.byType(Text)),
    );
    final root = text.textSpan! as TextSpan;
    final interactive = _flatten(root)
        .where((span) => span.recognizer is TapGestureRecognizer)
        .toList(growable: false);
    expect(_plainText(root), '题目 1: Dare precedenza.');
    expect(interactive.map((span) => span.text), ['precedenza']);

    await _tapTextRange(
      tester,
      annotation,
      '题目 1: Dare precedenza.',
      'precedenza',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DictionaryDetailScreen), findsNothing);
    expect(find.text('优先权；先行权'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '查看完整词条'));
    await tester.pumpAndSettle();

    final detail = tester.widget<DictionaryDetailScreen>(
      find.byType(DictionaryDetailScreen),
    );
    expect(detail.keywordId, 17);
    expect(find.text('词条详情'), findsOneWidget);
    expect(find.text('题库中的完整释义。'), findsOneWidget);
  });
}

final class _SurfaceExpectation {
  const _SurfaceExpectation({
    required this.path,
    required this.questionId,
    required this.text,
    this.prefix,
    this.styleMarker,
  });

  final String path;
  final String questionId;
  final String text;
  final String? prefix;
  final String? styleMarker;
}

int _lineNumber(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

Iterable<TextSpan> _flatten(TextSpan span) sync* {
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) yield* _flatten(child);
  }
}

String _plainText(TextSpan span) {
  final buffer = StringBuffer(span.text ?? '');
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) buffer.write(_plainText(child));
  }
  return buffer.toString();
}

Future<void> _tapTextRange(
  WidgetTester tester,
  Finder ancestor,
  String fullText,
  String target,
) async {
  final richText = find.descendant(
    of: ancestor,
    matching: find.byType(RichText),
  );
  final renderParagraph = tester.renderObject<RenderParagraph>(richText);
  final start = fullText.indexOf(target);
  final boxes = renderParagraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + target.length),
  );
  expect(boxes, isNotEmpty);
  await tester
      .tapAt(renderParagraph.localToGlobal(boxes.first.toRect().center));
}

final class _RecordingLookup implements KeywordLookup {
  final List<int> questionIds = [];
  final List<String> texts = [];

  @override
  Future<List<KeywordMatch>> matchQuestion({
    required int questionId,
    required String text,
  }) async {
    questionIds.add(questionId);
    texts.add(text);
    final start = text.indexOf('precedenza');
    return [
      KeywordMatch(
        keyword: _keyword,
        start: start,
        end: start + 'precedenza'.length,
        matchedText: 'precedenza',
      ),
    ];
  }

  @override
  Future<Keyword?> keywordById(int id) async =>
      id == _keyword.id ? _keyword : null;
}

final class _DetailRepository extends KeywordRepository {
  _DetailRepository() : super(databaseProvider: _unexpectedDatabase);

  static Future<Never> _unexpectedDatabase() =>
      Future.error(StateError('The integration test must stay offline'));

  @override
  Future<Keyword?> byId(int id) async => id == _keyword.id ? _keyword : null;

  @override
  Future<List<KeywordForm>> forms() async => const [
        KeywordForm(
          id: 3,
          keywordId: 17,
          form: 'precedenza',
          normalizedForm: 'precedenza',
        ),
      ];

  @override
  Future<KeywordExample?> exampleFor(int keywordId) async =>
      const KeywordExample(
        questionId: 91,
        question: 'Dare precedenza.',
        translation: '必须让行。',
      );
}

const _keyword = Keyword(
  id: 17,
  term: 'precedenza',
  normalizedTerm: 'precedenza',
  partOfSpeech: '名词',
  translation: '优先权；先行权',
  note: '题库中的完整释义。',
  frequency: 100,
  sortOrder: 1,
);
