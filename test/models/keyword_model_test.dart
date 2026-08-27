import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/models/keyword_model.dart';
import 'package:italian_driving_app/models/question_model.dart';

void main() {
  group('Question', () {
    test('fromMap keeps the stable quiz id and toMap preserves it', () {
      final question = Question.fromMap({
        'id': 42,
        'section_id': 3,
        'question_number': 8,
        'question': 'Test',
        'translation': '测试',
        'explanation': '解析',
      });

      expect(question.id, 42);
      expect(question.toMap()['id'], 42);
    });

    test('direct construction remains compatible when no quiz id is known', () {
      final question = Question(
        sectionId: 3,
        questionNumber: 8,
        question: 'Test',
        translation: '测试',
        explanation: '解析',
      );

      expect(question.id, 0);
    });

    test('fromMap rejects rows that do not carry a real quiz id', () {
      expect(
        () => Question.fromMap({
          'section_id': 3,
          'question_number': 8,
          'question': 'Test',
          'translation': '测试',
          'explanation': '解析',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('Keyword', () {
    test('fromMap maps all fields', () {
      final keyword = Keyword.fromMap(_keywordRow(id: 7));

      expect(
        keyword,
        const Keyword(
          id: 7,
          term: 'precedenza',
          normalizedTerm: 'precedenza',
          partOfSpeech: 'nome',
          translation: '优先权',
          note: '让其他道路使用者先通过。',
          frequency: 120,
          sortOrder: 4,
        ),
      );
      expect(keyword.hashCode, Keyword.fromMap(_keywordRow(id: 7)).hashCode);
    });

    test('fromMap defaults nullable storage fields', () {
      final row = _keywordRow(id: 7)
        ..['note'] = null
        ..['frequency'] = null
        ..['sort_order'] = null;

      final keyword = Keyword.fromMap(row);

      expect(keyword.note, '');
      expect(keyword.frequency, 0);
      expect(keyword.sortOrder, 0);
    });

    test('fromMap rejects a missing required field with a TypeError', () {
      final row = _keywordRow(id: 7)..remove('term');

      expect(() => Keyword.fromMap(row), throwsA(isA<TypeError>()));
    });
  });

  group('KeywordForm', () {
    test('fromMap maps typed fields and supports value equality', () {
      final form = KeywordForm.fromMap({
        'id': 11,
        'keyword_id': 7,
        'form': 'dà precedenza',
        'normalized_form': 'dà precedenza',
      });

      expect(
        form,
        const KeywordForm(
          id: 11,
          keywordId: 7,
          form: 'dà precedenza',
          normalizedForm: 'dà precedenza',
        ),
      );
      expect(
        form.hashCode,
        const KeywordForm(
          id: 11,
          keywordId: 7,
          form: 'dà precedenza',
          normalizedForm: 'dà precedenza',
        ).hashCode,
      );
    });

    test('fromMap rejects a wrong required field type', () {
      expect(
        () => KeywordForm.fromMap({
          'id': 11,
          'keyword_id': '7',
          'form': 'precedenza',
          'normalized_form': 'precedenza',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('KeywordExample', () {
    test('fromMap maps the joined bilingual quiz row', () {
      final example = KeywordExample.fromMap({
        'question_id': 146,
        'question': 'Bisogna dare precedenza.',
        'translation': '必须让行。',
      });

      expect(
        example,
        const KeywordExample(
          questionId: 146,
          question: 'Bisogna dare precedenza.',
          translation: '必须让行。',
        ),
      );
    });

    test('fromMap rejects a missing joined question', () {
      expect(
        () => KeywordExample.fromMap({
          'question_id': 146,
          'translation': '必须让行。',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  test('KeywordMatch exposes offsets, source text, and keyword identity', () {
    final keyword = Keyword.fromMap(_keywordRow(id: 7));
    final first = KeywordMatch(
      keyword: keyword,
      start: 8,
      end: 18,
      matchedText: 'precedenza',
    );
    final second = KeywordMatch(
      keyword: Keyword.fromMap(_keywordRow(id: 7)),
      start: 8,
      end: 18,
      matchedText: 'precedenza',
    );

    expect(first.keywordId, 7);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('KeywordMatch.fromMap keeps its typed matcher payload', () {
    final keyword = Keyword.fromMap(_keywordRow(id: 7));

    expect(
      KeywordMatch.fromMap({
        'keyword': keyword,
        'start': 8,
        'end': 18,
        'matched_text': 'precedenza',
      }),
      KeywordMatch(
        keyword: keyword,
        start: 8,
        end: 18,
        matchedText: 'precedenza',
      ),
    );
  });
}

Map<String, Object?> _keywordRow({required int id}) => {
      'id': id,
      'term': 'precedenza',
      'normalized_term': 'precedenza',
      'part_of_speech': 'nome',
      'translation': '优先权',
      'note': '让其他道路使用者先通过。',
      'frequency': 120,
      'sort_order': 4,
    };
