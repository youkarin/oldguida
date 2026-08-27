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
      expect(
        _queryProjectsQuizId(_dartMethodBody(source, method)),
        isTrue,
        reason: '$method must project q.* or q.id AS id',
      );
    }
  });

  test('query audit cannot borrow an id projection from a later method', () {
    const mutatedSource = r"""
class DatabaseHelper {
  Future<List<Map<String, dynamic>>> getFavoriteQuestions(int userId) async {
    // A brace in a comment must not end the method: }
    final decoration = "a string containing } and {";
    return db.rawQuery('''
      SELECT q.question
      FROM quiz q
    ''');
  }

  Future<List<Map<String, dynamic>>> getWrongAnswerQuestions(int userId) async {
    return db.rawQuery('''
      SELECT q.*
      FROM quiz q
    ''');
  }

  Future<List<Map<String, dynamic>>> getHistoryQuestions(int historyId) async {
    return db.rawQuery('''
      SELECT q.id AS id, q.question
      FROM quiz q
    ''');
  }
}
""";

    final favoriteBody = _dartMethodBody(mutatedSource, 'getFavoriteQuestions');
    expect(favoriteBody, contains('SELECT q.question'));
    expect(favoriteBody, isNot(contains('SELECT q.*')));
    expect(_queryProjectsQuizId(favoriteBody), isFalse);
    expect(
      _queryProjectsQuizId(
        _dartMethodBody(mutatedSource, 'getWrongAnswerQuestions'),
      ),
      isTrue,
    );
    expect(
      _queryProjectsQuizId(
        _dartMethodBody(mutatedSource, 'getHistoryQuestions'),
      ),
      isTrue,
    );
  });

  test('production screens contain no remaining raw Italian Text renderer', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/Screen').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final offset in _rawQuestionTextOffsets(source)) {
        offenders.add('${entity.path}:${_lineNumber(source, offset)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'raw Italian question Text renderers: ${offenders.join(', ')}',
    );
  });

  test('raw Text audit catches direct, map, and later interpolation forms', () {
    const mutatedSource = r'''
Widget buildQuestion(int index, Map<String, Object?> item) {
  return Column(children: [
    Text('${index + 1}. $questionText'),
    Text(") ${index + 1}. Q: ${item['question']}"),
    Text(question.question),
    Text(q.question),
    Text(item["question"]),
  ]);
}
''';

    expect(_rawQuestionTextOffsets(mutatedSource), hasLength(5));
  });

  test('raw Text audit ignores prefixes, translations, and non-Text widgets',
      () {
    const compliantSource = r'''
Widget buildQuestion(int index, Map<String, Object?> item) {
  // Text(question.question) inside a comment is not a renderer.
  const example = "Text(item['question'])";
  return Column(children: [
    Text('${index + 1}. '),
    Text('翻译: ${question.translation}'),
    Text(question.translation),
    Text(item['translation']),
    Text(prefix),
    KeywordQuestionText(text: question.question),
  ]);
}
''';

    expect(_rawQuestionTextOffsets(compliantSource), isEmpty);
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

String _dartMethodBody(String source, String methodName) {
  final signature = RegExp(
    'Future\\s*<\\s*List\\s*<\\s*Map\\s*<\\s*String\\s*,\\s*dynamic\\s*>\\s*>\\s*>\\s*'
    '${RegExp.escape(methodName)}\\s*\\(',
  ).firstMatch(source);
  if (signature == null) {
    throw StateError('Method signature not found: $methodName');
  }

  final parametersOpen = signature.end - 1;
  final parametersClose = _matchingDelimiter(
    source,
    parametersOpen,
    '('.codeUnitAt(0),
    ')'.codeUnitAt(0),
  );
  final bodyOpen = _nextCodeUnit(
    source,
    parametersClose + 1,
    '{'.codeUnitAt(0),
  );
  if (bodyOpen < 0) {
    throw StateError('Method body not found: $methodName');
  }
  final bodyClose = _matchingDelimiter(
    source,
    bodyOpen,
    '{'.codeUnitAt(0),
    '}'.codeUnitAt(0),
  );
  return source.substring(bodyOpen + 1, bodyClose);
}

bool _queryProjectsQuizId(String methodBody) {
  final selectProjection = RegExp(
    r'\bSELECT\b([\s\S]*?)\bFROM\b',
    caseSensitive: false,
  );
  final wildcard = RegExp(r'\bq\s*\.\s*\*', caseSensitive: false);
  final explicitId = RegExp(
    r'\bq\s*\.\s*id\s+AS\s+id\b',
    caseSensitive: false,
  );
  return selectProjection.allMatches(methodBody).any((match) {
    final projection = match.group(1)!;
    return wildcard.hasMatch(projection) || explicitId.hasMatch(projection);
  });
}

List<int> _rawQuestionTextOffsets(String source) {
  final offsets = <int>[];
  var index = 0;
  while (index < source.length) {
    final skipped = _skipCommentOrString(source, index);
    if (skipped != null) {
      index = skipped;
      continue;
    }

    if (_isIdentifierStart(source.codeUnitAt(index))) {
      final tokenStart = index;
      index++;
      while (index < source.length &&
          _isIdentifierPart(source.codeUnitAt(index))) {
        index++;
      }
      if (source.substring(tokenStart, index) != 'Text') continue;

      final invocationOpen = _nextNonTrivia(source, index);
      if (invocationOpen < 0 ||
          source.codeUnitAt(invocationOpen) != '('.codeUnitAt(0)) {
        continue;
      }
      final invocationClose = _matchingDelimiter(
        source,
        invocationOpen,
        '('.codeUnitAt(0),
        ')'.codeUnitAt(0),
      );
      final invocation = source.substring(tokenStart, invocationClose + 1);
      if (_containsQuestionExpression(_questionAuditCode(invocation))) {
        offsets.add(tokenStart);
      }
      index = invocationClose + 1;
      continue;
    }
    index++;
  }
  return offsets;
}

bool _containsQuestionExpression(String code) =>
    RegExp(r'\b(?:question|q)\s*\.\s*question\b').hasMatch(code) ||
    RegExp(r'\bquestionText\b').hasMatch(code) ||
    RegExp(r'''\bitem\s*\[\s*['"]question['"]\s*\]''').hasMatch(code);

String _questionAuditCode(String source) {
  final result = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (_startsLineComment(source, index)) {
      index = _skipLineComment(source, index);
      result.write(' ');
      continue;
    }
    if (_startsBlockComment(source, index)) {
      index = _skipBlockComment(source, index);
      result.write(' ');
      continue;
    }
    if (_isQuote(source.codeUnitAt(index))) {
      final string = _scanDartString(source, index);
      final previous = _previousNonWhitespace(source, index);
      if (previous == '['.codeUnitAt(0)) {
        result.write(source.substring(index, string.end));
      }
      for (final expression in string.interpolations) {
        result.write(' ${_questionAuditCode(expression)} ');
      }
      index = string.end;
      continue;
    }
    result.writeCharCode(source.codeUnitAt(index));
    index++;
  }
  return result.toString();
}

int _matchingDelimiter(
  String source,
  int openIndex,
  int open,
  int close,
) {
  if (source.codeUnitAt(openIndex) != open) {
    throw StateError('Expected delimiter at offset $openIndex');
  }
  var depth = 1;
  var index = openIndex + 1;
  while (index < source.length) {
    final skipped = _skipCommentOrString(source, index);
    if (skipped != null) {
      index = skipped;
      continue;
    }
    final codeUnit = source.codeUnitAt(index);
    if (codeUnit == open) depth++;
    if (codeUnit == close && --depth == 0) return index;
    index++;
  }
  throw StateError('Unclosed delimiter at offset $openIndex');
}

int _nextCodeUnit(String source, int start, int wanted) {
  var index = start;
  while (index < source.length) {
    final skipped = _skipCommentOrString(source, index);
    if (skipped != null) {
      index = skipped;
      continue;
    }
    if (source.codeUnitAt(index) == wanted) return index;
    index++;
  }
  return -1;
}

int _nextNonTrivia(String source, int start) {
  var index = start;
  while (index < source.length) {
    if (_isWhitespace(source.codeUnitAt(index))) {
      index++;
      continue;
    }
    if (_startsLineComment(source, index)) {
      index = _skipLineComment(source, index);
      continue;
    }
    if (_startsBlockComment(source, index)) {
      index = _skipBlockComment(source, index);
      continue;
    }
    return index;
  }
  return -1;
}

int? _skipCommentOrString(String source, int index) {
  if (_startsLineComment(source, index)) {
    return _skipLineComment(source, index);
  }
  if (_startsBlockComment(source, index)) {
    return _skipBlockComment(source, index);
  }
  if (_isQuote(source.codeUnitAt(index))) {
    return _scanDartString(source, index).end;
  }
  return null;
}

bool _startsLineComment(String source, int index) =>
    index + 1 < source.length && source.startsWith('//', index);

bool _startsBlockComment(String source, int index) =>
    index + 1 < source.length && source.startsWith('/*', index);

int _skipLineComment(String source, int index) {
  final newline = source.indexOf('\n', index + 2);
  return newline < 0 ? source.length : newline + 1;
}

int _skipBlockComment(String source, int index) {
  var depth = 1;
  index += 2;
  while (index < source.length) {
    if (source.startsWith('/*', index)) {
      depth++;
      index += 2;
      continue;
    }
    if (source.startsWith('*/', index)) {
      depth--;
      index += 2;
      if (depth == 0) return index;
      continue;
    }
    index++;
  }
  throw StateError('Unclosed block comment');
}

_DartStringScan _scanDartString(String source, int quoteIndex) {
  final quote = source.codeUnitAt(quoteIndex);
  final delimiterLength = quoteIndex + 2 < source.length &&
          source.codeUnitAt(quoteIndex + 1) == quote &&
          source.codeUnitAt(quoteIndex + 2) == quote
      ? 3
      : 1;
  final raw = quoteIndex > 0 &&
      (source.codeUnitAt(quoteIndex - 1) == 'r'.codeUnitAt(0) ||
          source.codeUnitAt(quoteIndex - 1) == 'R'.codeUnitAt(0)) &&
      (quoteIndex < 2 || !_isIdentifierPart(source.codeUnitAt(quoteIndex - 2)));
  final interpolations = <String>[];
  var index = quoteIndex + delimiterLength;
  while (index < source.length) {
    if (!raw && source.codeUnitAt(index) == '\\'.codeUnitAt(0)) {
      index += 2;
      continue;
    }
    if (!raw && source.codeUnitAt(index) == r'$'.codeUnitAt(0)) {
      if (index + 1 < source.length &&
          source.codeUnitAt(index + 1) == '{'.codeUnitAt(0)) {
        final close = _matchingDelimiter(
          source,
          index + 1,
          '{'.codeUnitAt(0),
          '}'.codeUnitAt(0),
        );
        interpolations.add(source.substring(index + 2, close));
        index = close + 1;
        continue;
      }
      if (index + 1 < source.length &&
          _isIdentifierStart(source.codeUnitAt(index + 1))) {
        final start = ++index;
        while (index < source.length &&
            _isIdentifierPart(source.codeUnitAt(index))) {
          index++;
        }
        interpolations.add(source.substring(start, index));
        continue;
      }
    }
    if (_startsDelimiter(source, index, quote, delimiterLength)) {
      return _DartStringScan(
        index + delimiterLength,
        interpolations,
      );
    }
    index++;
  }
  throw StateError('Unclosed string at offset $quoteIndex');
}

bool _startsDelimiter(String source, int index, int quote, int length) {
  if (index + length > source.length) return false;
  for (var offset = 0; offset < length; offset++) {
    if (source.codeUnitAt(index + offset) != quote) return false;
  }
  return true;
}

int? _previousNonWhitespace(String source, int index) {
  index--;
  while (index >= 0 && _isWhitespace(source.codeUnitAt(index))) {
    index--;
  }
  return index < 0 ? null : source.codeUnitAt(index);
}

bool _isQuote(int codeUnit) =>
    codeUnit == "'".codeUnitAt(0) || codeUnit == '"'.codeUnitAt(0);

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

bool _isIdentifierStart(int codeUnit) =>
    codeUnit == 0x5F ||
    codeUnit == 0x24 ||
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

bool _isIdentifierPart(int codeUnit) =>
    _isIdentifierStart(codeUnit) || (codeUnit >= 0x30 && codeUnit <= 0x39);

final class _DartStringScan {
  const _DartStringScan(this.end, this.interpolations);

  final int end;
  final List<String> interpolations;
}

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
