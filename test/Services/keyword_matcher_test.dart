import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Services/keyword_matcher.dart';
import 'package:italian_driving_app/models/keyword_model.dart';

void main() {
  group('KeywordMatcher normalization and boundaries', () {
    test('matches case and curly apostrophes at original UTF-16 offsets', () {
      final matcher = _matcher([
        _fixture(id: 1, form: "l'autovettura"),
      ]);

      final match = matcher
          .match(
            questionId: 1,
            text: '🚗 L’AUTOVETTURA rallenta.',
            dictionaryVersion: 1,
          )
          .single;

      expect(match.start, 3);
      expect(match.end, 16);
      expect(match.matchedText, 'L’AUTOVETTURA');
      expect(match.keywordId, 1);
    });

    test('treats letters and digits as partial-word boundaries', () {
      final matcher = _matcher([_fixture(id: 1, form: 'auto')]);

      expect(
        matcher.match(
          questionId: 1,
          text: 'auto2 2auto imauto AUTO.',
          dictionaryVersion: 1,
        ),
        [
          isA<KeywordMatch>()
              .having((match) => match.start, 'start', 19)
              .having((match) => match.matchedText, 'matchedText', 'AUTO'),
        ],
      );
    });

    test('uses apostrophes and hyphens as valid Italian word boundaries', () {
      final matcher = _matcher([_fixture(id: 1, form: 'autovettura')]);

      final matches = matcher.match(
        questionId: 1,
        text: 'l’autovettura, autovettura-autovettura.',
        dictionaryVersion: 1,
      );

      expect(
        matches.map((match) => match.matchedText),
        ['autovettura', 'autovettura', 'autovettura'],
      );
      expect(matches.map((match) => match.start), [2, 15, 27]);
    });

    test('preserves Italian accents instead of folding them away', () {
      final matcher = _matcher([_fixture(id: 1, form: 'velocità')]);

      expect(
        matcher
            .match(
              questionId: 1,
              text: 'VELOCITÀ e velocita.',
              dictionaryVersion: 1,
            )
            .map((match) => match.matchedText),
        ['VELOCITÀ'],
      );
    });
  });

  group('KeywordMatcher global overlap resolution', () {
    test('longest fixed phrase wins over every nested shorter form', () {
      final matcher = _matcher([
        _fixture(id: 1, form: 'dare'),
        _fixture(id: 2, form: 'precedenza'),
        _fixture(id: 3, form: 'dare precedenza'),
      ]);

      final matches = matcher.match(
        questionId: 1,
        text: 'Deve dare precedenza, poi dare precedenza.',
        dictionaryVersion: 1,
      );

      expect(
        matches.map((match) => match.matchedText),
        ['dare precedenza', 'dare precedenza'],
      );
      expect(matches.map((match) => match.keywordId), [3, 3]);
    });

    test('a longer later-starting form wins a crossing overlap globally', () {
      final matcher = _matcher([
        _fixture(id: 1, form: 'lato sinistro'),
        _fixture(id: 2, form: 'sinistro della carreggiata'),
      ]);

      final match = matcher
          .match(
            questionId: 1,
            text: 'sul lato sinistro della carreggiata',
            dictionaryVersion: 1,
          )
          .single;

      expect(match.keywordId, 2);
      expect(match.matchedText, 'sinistro della carreggiata');
      expect(match.start, 9);
    });

    test('equal-length crossing forms follow stable repository form order', () {
      final first = _matcher([
        _fixture(id: 2, form: 'strada larga'),
        _fixture(id: 1, form: 'larga piazza'),
      ]);
      final second = _matcher([
        _fixture(id: 1, form: 'larga piazza'),
        _fixture(id: 2, form: 'strada larga'),
      ]);

      expect(
        first
            .match(
              questionId: 1,
              text: 'strada larga piazza',
              dictionaryVersion: 1,
            )
            .single
            .keywordId,
        2,
      );
      expect(
        second
            .match(
              questionId: 1,
              text: 'strada larga piazza',
              dictionaryVersion: 1,
            )
            .single
            .keywordId,
        1,
      );
    });

    test('same surface follows repository form order and skips orphans', () {
      final keywords = <int, Keyword>{
        2: _keyword(2),
        1: _keyword(1),
      };
      final matcher = KeywordMatcher(
        keywords: keywords,
        forms: const [
          KeywordForm(
            id: 30,
            keywordId: 999,
            form: 'precedenza',
            normalizedForm: 'precedenza',
          ),
          KeywordForm(
            id: 20,
            keywordId: 2,
            form: 'precedenza',
            normalizedForm: 'precedenza',
          ),
          KeywordForm(
            id: 10,
            keywordId: 1,
            form: 'precedenza',
            normalizedForm: 'precedenza',
          ),
        ],
      );

      expect(
        matcher
            .match(
              questionId: 1,
              text: 'precedenza',
              dictionaryVersion: 1,
            )
            .single
            .keywordId,
        2,
      );
    });

    test('returns accepted non-overlapping matches in source order', () {
      final matcher = _matcher([
        _fixture(id: 1, form: 'sinistro'),
        _fixture(id: 2, form: 'dare precedenza'),
      ]);

      final matches = matcher.match(
        questionId: 1,
        text: 'sinistro: dare precedenza; sinistro.',
        dictionaryVersion: 1,
      );

      expect(matches.map((match) => match.start), [0, 10, 27]);
      expect(
        matches.map((match) => match.matchedText),
        ['sinistro', 'dare precedenza', 'sinistro'],
      );
    });
  });

  group('KeywordMatcher cache', () {
    test('uses the exact question id, version, and text cache key', () {
      final matcher = _matcher([_fixture(id: 1, form: 'auto')]);

      final original = matcher.match(
        questionId: 1,
        text: 'auto',
        dictionaryVersion: 0,
      );
      final same = matcher.match(
        questionId: 1,
        text: 'auto',
        dictionaryVersion: 0,
      );
      final otherId = matcher.match(
        questionId: 2,
        text: 'auto',
        dictionaryVersion: 0,
      );
      final otherVersion = matcher.match(
        questionId: 1,
        text: 'auto',
        dictionaryVersion: 1,
      );
      final otherText = matcher.match(
        questionId: 1,
        text: 'AUTO',
        dictionaryVersion: 0,
      );

      expect(identical(original, same), isTrue);
      expect(identical(original, otherId), isFalse);
      expect(identical(original, otherVersion), isFalse);
      expect(identical(original, otherText), isFalse);
    });

    test('cached results cannot be mutated and clearCache invalidates them',
        () {
      final matcher = _matcher([_fixture(id: 1, form: 'auto')]);
      final original = matcher.match(
        questionId: 1,
        text: 'auto',
        dictionaryVersion: 1,
      );

      expect(
        () => original.add(original.single),
        throwsUnsupportedError,
      );
      expect(
        matcher.match(
          questionId: 1,
          text: 'auto',
          dictionaryVersion: 1,
        ),
        same(original),
      );

      matcher.clearCache();

      expect(
        identical(
          original,
          matcher.match(
            questionId: 1,
            text: 'auto',
            dictionaryVersion: 1,
          ),
        ),
        isFalse,
      );
    });
  });
}

KeywordMatcher _matcher(List<({int id, String form})> fixtures) {
  final keywords = <int, Keyword>{};
  final forms = <KeywordForm>[];
  for (var index = 0; index < fixtures.length; index++) {
    final fixture = fixtures[index];
    keywords.putIfAbsent(fixture.id, () => _keyword(fixture.id));
    forms.add(
      KeywordForm(
        id: index + 1,
        keywordId: fixture.id,
        form: fixture.form,
        normalizedForm: fixture.form.toLowerCase().replaceAll('’', "'"),
      ),
    );
  }
  return KeywordMatcher(keywords: keywords, forms: forms);
}

({int id, String form}) _fixture({required int id, required String form}) =>
    (id: id, form: form);

Keyword _keyword(int id) => Keyword(
      id: id,
      term: 'term-$id',
      normalizedTerm: 'term-$id',
      partOfSpeech: '名词',
      translation: '释义$id',
      note: '',
      frequency: 0,
      sortOrder: id,
    );
