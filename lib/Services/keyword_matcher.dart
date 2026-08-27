import '../models/keyword_model.dart';

typedef _CacheKey = ({int questionId, int dictionaryVersion, String text});

final class KeywordMatcher {
  KeywordMatcher({
    required Map<int, Keyword> keywords,
    required List<KeywordForm> forms,
  }) : _forms = _prepareForms(keywords, forms);

  final List<_PreparedForm> _forms;
  final Map<_CacheKey, List<KeywordMatch>> _cache = {};

  List<KeywordMatch> match({
    required int questionId,
    required String text,
    required int dictionaryVersion,
  }) {
    final key = (
      questionId: questionId,
      dictionaryVersion: dictionaryVersion,
      text: text,
    );
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final normalizedText = normalizeForMatch(text);
    final candidates = <_Candidate>[];
    for (final form in _forms) {
      var start = normalizedText.indexOf(form.normalizedForm);
      while (start >= 0) {
        final end = start + form.normalizedForm.length;
        if (_hasItalianBoundaries(normalizedText, start, end)) {
          candidates.add(_Candidate(form: form, start: start, end: end));
        }
        start = normalizedText.indexOf(form.normalizedForm, start + 1);
      }
    }

    candidates.sort(_compareCandidates);
    final occupied = List<bool>.filled(text.length, false);
    final accepted = <_Candidate>[];
    for (final candidate in candidates) {
      if (_overlapsOccupied(occupied, candidate.start, candidate.end)) {
        continue;
      }
      for (var index = candidate.start; index < candidate.end; index++) {
        occupied[index] = true;
      }
      accepted.add(candidate);
    }
    accepted.sort((left, right) => left.start.compareTo(right.start));

    final result = List<KeywordMatch>.unmodifiable(
      accepted.map(
        (candidate) => KeywordMatch(
          keyword: candidate.form.keyword,
          start: candidate.start,
          end: candidate.end,
          matchedText: text.substring(candidate.start, candidate.end),
        ),
      ),
    );
    _cache[key] = result;
    return result;
  }

  void clearCache() => _cache.clear();
}

String normalizeForMatch(String value) {
  final normalized = StringBuffer();
  for (final codeUnit in value.codeUnits) {
    final character = String.fromCharCode(codeUnit);
    if (const {'’', '‘', '`', '´'}.contains(character)) {
      normalized.write("'");
      continue;
    }
    final lowercase = character.toLowerCase();
    normalized.write(lowercase.length == 1 ? lowercase : character);
  }
  return normalized.toString();
}

List<_PreparedForm> _prepareForms(
  Map<int, Keyword> keywords,
  List<KeywordForm> forms,
) {
  final keywordOrder = <int, int>{};
  var nextKeywordOrder = 0;
  for (final keywordId in keywords.keys) {
    keywordOrder[keywordId] = nextKeywordOrder++;
  }

  final prepared = <_PreparedForm>[];
  for (var formOrder = 0; formOrder < forms.length; formOrder++) {
    final form = forms[formOrder];
    final keyword = keywords[form.keywordId];
    final normalizedForm = normalizeForMatch(form.normalizedForm);
    if (keyword == null || normalizedForm.isEmpty) {
      continue;
    }
    prepared.add(
      _PreparedForm(
        keyword: keyword,
        normalizedForm: normalizedForm,
        formOrder: formOrder,
        keywordOrder: keywordOrder[form.keywordId]!,
      ),
    );
  }
  prepared.sort((left, right) {
    final byLength = right.normalizedForm.length.compareTo(
      left.normalizedForm.length,
    );
    if (byLength != 0) {
      return byLength;
    }
    final byFormOrder = left.formOrder.compareTo(right.formOrder);
    if (byFormOrder != 0) {
      return byFormOrder;
    }
    return left.keywordOrder.compareTo(right.keywordOrder);
  });
  return List.unmodifiable(prepared);
}

int _compareCandidates(_Candidate left, _Candidate right) {
  final byLength = right.length.compareTo(left.length);
  if (byLength != 0) {
    return byLength;
  }
  final byFormOrder = left.form.formOrder.compareTo(right.form.formOrder);
  if (byFormOrder != 0) {
    return byFormOrder;
  }
  final byKeywordOrder = left.form.keywordOrder.compareTo(
    right.form.keywordOrder,
  );
  if (byKeywordOrder != 0) {
    return byKeywordOrder;
  }
  return left.start.compareTo(right.start);
}

bool _overlapsOccupied(List<bool> occupied, int start, int end) {
  for (var index = start; index < end; index++) {
    if (occupied[index]) {
      return true;
    }
  }
  return false;
}

bool _hasItalianBoundaries(String text, int start, int end) =>
    !_isItalianWordCharacter(text, start - 1) &&
    !_isItalianWordCharacter(text, end);

bool _isItalianWordCharacter(String value, int index) {
  if (index < 0 || index >= value.length) {
    return false;
  }
  return RegExp(
    r'[0-9A-Za-zÀÈÉÌÒÓÙàèéìòóù]',
  ).hasMatch(value[index]);
}

final class _PreparedForm {
  const _PreparedForm({
    required this.keyword,
    required this.normalizedForm,
    required this.formOrder,
    required this.keywordOrder,
  });

  final Keyword keyword;
  final String normalizedForm;
  final int formOrder;
  final int keywordOrder;
}

final class _Candidate {
  const _Candidate({
    required this.form,
    required this.start,
    required this.end,
  });

  final _PreparedForm form;
  final int start;
  final int end;

  int get length => end - start;
}
