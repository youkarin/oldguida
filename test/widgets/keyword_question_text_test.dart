import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Services/keyword_service.dart';
import 'package:italian_driving_app/Services/keyword_translation_settings.dart';
import 'package:italian_driving_app/models/keyword_model.dart';
import 'package:italian_driving_app/widgets/keyword_definition_sheet.dart';
import 'package:italian_driving_app/widgets/keyword_question_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'renders prefix separately and annotates multiple matches in order',
      (tester) async {
    final service = _FakeLookup((questionId, text) async => [
          _match(_precedenza, text, 'precedenza'),
          _match(_veicolo, text, 'veicolo'),
        ]);

    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 7,
        prefix: 'Q7: precedenza | ',
        text: 'Dare precedenza al veicolo.',
        style: const TextStyle(fontSize: 19, color: Colors.black87),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        service: service,
      ),
    ));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.byType(Text));
    final root = text.textSpan! as TextSpan;
    final annotated = _annotatedSpans(root);
    expect(_plainText(root), 'Q7: precedenza | Dare precedenza al veicolo.');
    expect(root.children!.first, isA<TextSpan>());
    expect((root.children!.first as TextSpan).text, 'Q7: precedenza | ');
    expect(annotated.map((span) => span.text), ['precedenza', 'veicolo']);
    expect(
      annotated.every(
        (span) =>
            span.style?.decoration == TextDecoration.underline &&
            span.style?.decorationStyle == TextDecorationStyle.dotted &&
            span.style?.decorationColor == Colors.teal,
      ),
      isTrue,
    );
    expect(text.style?.fontSize, 19);
    expect(text.textAlign, TextAlign.center);
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(service.matchCalls, 1);
    expect(service.requestedTexts, ['Dare precedenza al veicolo.']);
  });

  testWidgets('disabled state stays plain and never calls the service',
      (tester) async {
    final settings = KeywordTranslationSettings.forTest();
    settings.enabled.value = false;
    final service = _FakeLookup((questionId, text) async => [
          _match(_precedenza, text, 'precedenza'),
        ]);

    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 1,
        prefix: 'Q1: ',
        text: 'Dare precedenza.',
        service: service,
        settings: settings,
      ),
    ));
    await tester.pump();

    final root = _rootSpan(tester);
    expect(_plainText(root), 'Q1: Dare precedenza.');
    expect(_annotatedSpans(root), isEmpty);
    expect(service.matchCalls, 0);
  });

  testWidgets('toggle changes annotations and avoids duplicate lookup calls',
      (tester) async {
    final settings = KeywordTranslationSettings.forTest();
    final service = _FakeLookup((questionId, text) async => [
          _match(_precedenza, text, 'precedenza'),
        ]);

    Widget subject({String prefix = 'Q: ', TextStyle? style}) => _app(
          KeywordQuestionText(
            questionId: 1,
            prefix: prefix,
            text: 'Dare precedenza.',
            style: style,
            service: service,
            settings: settings,
          ),
        );

    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    expect(_annotatedSpans(_rootSpan(tester)), hasLength(1));
    expect(service.matchCalls, 1);

    await tester.pumpWidget(
      subject(prefix: '题目 1: ', style: const TextStyle(fontSize: 22)),
    );
    await tester.pump();
    expect(service.matchCalls, 1);
    expect(_plainText(_rootSpan(tester)), '题目 1: Dare precedenza.');

    final firstRecognizer =
        _annotatedSpans(_rootSpan(tester)).single.recognizer!;
    final disposed = <Object>[];
    void allocationListener(ObjectEvent event) {
      if (event is ObjectDisposed) disposed.add(event.object);
    }

    FlutterMemoryAllocations.instance.addListener(allocationListener);
    addTearDown(
      () =>
          FlutterMemoryAllocations.instance.removeListener(allocationListener),
    );

    await settings.setEnabled(false);
    await tester.pump();
    expect(_annotatedSpans(_rootSpan(tester)), isEmpty);
    expect(service.matchCalls, 1);
    expect(disposed.where((object) => identical(object, firstRecognizer)),
        hasLength(1));

    await settings.setEnabled(true);
    await tester.pumpAndSettle();
    expect(_annotatedSpans(_rootSpan(tester)), hasLength(1));
    expect(service.matchCalls, 2);

    final secondRecognizer =
        _annotatedSpans(_rootSpan(tester)).single.recognizer!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed.where((object) => identical(object, secondRecognizer)),
        hasLength(1));
  });

  testWidgets('ignores stale results after question, text, and service changes',
      (tester) async {
    final oldCompleter = Completer<List<KeywordMatch>>();
    final newCompleter = Completer<List<KeywordMatch>>();
    final oldService = _FakeLookup((questionId, text) => oldCompleter.future);
    final newService = _FakeLookup((questionId, text) => newCompleter.future);

    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 1,
        text: 'Dare precedenza.',
        service: oldService,
      ),
    ));
    await tester.pump();
    expect(_annotatedSpans(_rootSpan(tester)), isEmpty);

    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 2,
        text: 'Il veicolo rallenta.',
        service: newService,
      ),
    ));
    await tester.pump();

    newCompleter.complete([
      _match(_veicolo, 'Il veicolo rallenta.', 'veicolo'),
    ]);
    await tester.pumpAndSettle();
    expect(_annotatedSpans(_rootSpan(tester)).single.text, 'veicolo');

    oldCompleter.complete([
      _match(_precedenza, 'Dare precedenza.', 'precedenza'),
    ]);
    await tester.pumpAndSettle();
    expect(_plainText(_rootSpan(tester)), 'Il veicolo rallenta.');
    expect(_annotatedSpans(_rootSpan(tester)).single.text, 'veicolo');
    expect(oldService.matchCalls, 1);
    expect(newService.matchCalls, 1);
  });

  testWidgets('loading, empty results, and errors use the plain text fallback',
      (tester) async {
    final completer = Completer<List<KeywordMatch>>();
    final loadingService = _FakeLookup((questionId, text) => completer.future);

    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 1,
        prefix: 'Q1: ',
        text: 'Dare precedenza.',
        service: loadingService,
      ),
    ));
    await tester.pump();
    expect(_plainText(_rootSpan(tester)), 'Q1: Dare precedenza.');
    expect(_annotatedSpans(_rootSpan(tester)), isEmpty);

    completer.complete(const []);
    await tester.pump();
    expect(_annotatedSpans(_rootSpan(tester)), isEmpty);

    final errorService = _FakeLookup(
      (questionId, text) => Future.error(StateError('dictionary unavailable')),
    );
    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 2,
        prefix: 'Q2: ',
        text: 'Il veicolo rallenta.',
        service: errorService,
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_plainText(_rootSpan(tester)), 'Q2: Il veicolo rallenta.');
    expect(_annotatedSpans(_rootSpan(tester)), isEmpty);
  });

  testWidgets('tap opens the sheet and only full-entry action returns an id',
      (tester) async {
    final service = _FakeLookup((questionId, text) async => [
          _match(_precedenza, text, 'precedenza'),
        ]);
    final viewedIds = <int>[];

    await tester.pumpWidget(_app(
      KeywordQuestionText(
        questionId: 1,
        text: 'Dare precedenza.',
        service: service,
        onViewFullEntry: viewedIds.add,
      ),
    ));
    await tester.pumpAndSettle();

    final recognizer = _annotatedSpans(_rootSpan(tester)).single.recognizer!
        as TapGestureRecognizer;
    recognizer.onTap!();
    await tester.pumpAndSettle();

    expect(viewedIds, isEmpty);
    expect(find.text('precedenza'), findsWidgets);
    expect(find.text('优先权；先行权'), findsOneWidget);
    expect(find.textContaining('名词'), findsOneWidget);
    expect(find.text('在路口表示车辆享有先行权。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '查看完整词条'));
    await tester.pumpAndSettle();

    expect(viewedIds, [_precedenza.id]);
  });

  testWidgets('definition sheet returns keyword id without a callback',
      (tester) async {
    Future<int?>? result;
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => FilledButton(
          onPressed: () {
            result = showKeywordDefinitionSheet(
              context,
              _precedenza,
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '查看完整词条'));
    await tester.pumpAndSettle();

    expect(await result, _precedenza.id);
  });
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: Scaffold(body: Center(child: child)),
    );

TextSpan _rootSpan(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;

Iterable<TextSpan> _flatten(TextSpan span) sync* {
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) yield* _flatten(child);
  }
}

List<TextSpan> _annotatedSpans(TextSpan root) => _flatten(root)
    .where((span) => span.recognizer is TapGestureRecognizer)
    .toList(growable: false);

String _plainText(TextSpan span) {
  final buffer = StringBuffer(span.text ?? '');
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) buffer.write(_plainText(child));
  }
  return buffer.toString();
}

KeywordMatch _match(Keyword keyword, String text, String matchedText) {
  final start = text.indexOf(matchedText);
  return KeywordMatch(
    keyword: keyword,
    start: start,
    end: start + matchedText.length,
    matchedText: matchedText,
  );
}

final class _FakeLookup implements KeywordLookup {
  _FakeLookup(this._handler);

  final Future<List<KeywordMatch>> Function(int questionId, String text)
      _handler;
  int matchCalls = 0;
  final List<String> requestedTexts = [];

  @override
  Future<List<KeywordMatch>> matchQuestion({
    required int questionId,
    required String text,
  }) {
    matchCalls++;
    requestedTexts.add(text);
    return _handler(questionId, text);
  }

  @override
  Future<Keyword?> keywordById(int id) async =>
      id == _precedenza.id ? _precedenza : null;
}

const _precedenza = Keyword(
  id: 17,
  term: 'precedenza',
  normalizedTerm: 'precedenza',
  partOfSpeech: '名词',
  translation: '优先权；先行权',
  note: '在路口表示车辆享有先行权。',
  frequency: 100,
  sortOrder: 1,
);

const _veicolo = Keyword(
  id: 18,
  term: 'veicolo',
  normalizedTerm: 'veicolo',
  partOfSpeech: '名词',
  translation: '车辆',
  note: '',
  frequency: 90,
  sortOrder: 2,
);
