final class Keyword {
  const Keyword({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.partOfSpeech,
    required this.translation,
    required this.note,
    required this.frequency,
    required this.sortOrder,
  });

  final int id;
  final String term;
  final String normalizedTerm;
  final String partOfSpeech;
  final String translation;
  final String note;
  final int frequency;
  final int sortOrder;

  factory Keyword.fromMap(Map<String, Object?> row) => Keyword(
        id: row['id'] as int,
        term: row['term'] as String,
        normalizedTerm: row['normalized_term'] as String,
        partOfSpeech: row['part_of_speech'] as String,
        translation: row['translation'] as String,
        note: row['note'] as String? ?? '',
        frequency: row['frequency'] as int? ?? 0,
        sortOrder: row['sort_order'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Keyword &&
          id == other.id &&
          term == other.term &&
          normalizedTerm == other.normalizedTerm &&
          partOfSpeech == other.partOfSpeech &&
          translation == other.translation &&
          note == other.note &&
          frequency == other.frequency &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(
        id,
        term,
        normalizedTerm,
        partOfSpeech,
        translation,
        note,
        frequency,
        sortOrder,
      );
}

final class KeywordForm {
  const KeywordForm({
    required this.id,
    required this.keywordId,
    required this.form,
    required this.normalizedForm,
  });

  final int id;
  final int keywordId;
  final String form;
  final String normalizedForm;

  factory KeywordForm.fromMap(Map<String, Object?> row) => KeywordForm(
        id: row['id'] as int,
        keywordId: row['keyword_id'] as int,
        form: row['form'] as String,
        normalizedForm: row['normalized_form'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeywordForm &&
          id == other.id &&
          keywordId == other.keywordId &&
          form == other.form &&
          normalizedForm == other.normalizedForm;

  @override
  int get hashCode => Object.hash(id, keywordId, form, normalizedForm);
}

final class KeywordExample {
  const KeywordExample({
    required this.questionId,
    required this.question,
    required this.translation,
  });

  final int questionId;
  final String question;
  final String translation;

  factory KeywordExample.fromMap(Map<String, Object?> row) => KeywordExample(
        questionId: row['question_id'] as int,
        question: row['question'] as String,
        translation: row['translation'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeywordExample &&
          questionId == other.questionId &&
          question == other.question &&
          translation == other.translation;

  @override
  int get hashCode => Object.hash(questionId, question, translation);
}

final class KeywordMatch {
  const KeywordMatch({
    required this.keyword,
    required this.start,
    required this.end,
    required this.matchedText,
  });

  final Keyword keyword;
  final int start;
  final int end;
  final String matchedText;

  int get keywordId => keyword.id;

  factory KeywordMatch.fromMap(Map<String, Object?> row) => KeywordMatch(
        keyword: row['keyword'] as Keyword,
        start: row['start'] as int,
        end: row['end'] as int,
        matchedText: row['matched_text'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeywordMatch &&
          keyword == other.keyword &&
          start == other.start &&
          end == other.end &&
          matchedText == other.matchedText;

  @override
  int get hashCode => Object.hash(keyword, start, end, matchedText);
}
