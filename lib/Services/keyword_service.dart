import '../models/keyword_model.dart';
import 'keyword_matcher.dart';
import 'keyword_repository.dart';

abstract interface class KeywordLookup {
  Future<List<KeywordMatch>> matchQuestion({
    required int questionId,
    required String text,
  });

  Future<Keyword?> keywordById(int id);
}

final class KeywordService implements KeywordLookup {
  KeywordService({required KeywordRepository repository})
      : _repository = repository;

  static final instance = KeywordService(repository: KeywordRepository());

  final KeywordRepository _repository;
  _LoadedDictionary? _loaded;
  Future<_LoadedDictionary>? _loading;

  @override
  Future<List<KeywordMatch>> matchQuestion({
    required int questionId,
    required String text,
  }) async {
    final loaded = await _load();
    return loaded.matcher.match(
      questionId: questionId,
      text: text,
      dictionaryVersion: loaded.version,
    );
  }

  @override
  Future<Keyword?> keywordById(int id) => _repository.byId(id);

  Future<_LoadedDictionary> _load() {
    final pending = _loading;
    if (pending != null) {
      return pending;
    }

    late final Future<_LoadedDictionary> loading;
    loading = _loadStable().whenComplete(() {
      if (identical(_loading, loading)) {
        _loading = null;
      }
    });
    _loading = loading;
    return loading;
  }

  Future<_LoadedDictionary> _loadStable() async {
    while (true) {
      final requestedVersion = await _repository.dictionaryVersion();
      final current = _loaded;
      if (current != null && current.version == requestedVersion) {
        return current;
      }

      final datasets = await Future.wait<Object>([
        _repository.all(),
        _repository.forms(),
      ]);
      final confirmedVersion = await _repository.dictionaryVersion();
      if (confirmedVersion != requestedVersion) {
        continue;
      }

      final keywords = datasets[0] as List<Keyword>;
      final forms = datasets[1] as List<KeywordForm>;
      final next = _LoadedDictionary(
        version: confirmedVersion,
        matcher: KeywordMatcher(
          keywords: {for (final keyword in keywords) keyword.id: keyword},
          forms: forms,
        ),
      );
      current?.matcher.clearCache();
      _loaded = next;
      return next;
    }
  }
}

final class _LoadedDictionary {
  const _LoadedDictionary({required this.version, required this.matcher});

  final int version;
  final KeywordMatcher matcher;
}
