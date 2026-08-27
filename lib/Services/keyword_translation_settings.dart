import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SharedPreferencesProvider = Future<SharedPreferences> Function();

abstract interface class KeywordTranslationPersistence {
  Future<bool?> read();

  Future<void> write(bool value);
}

final class KeywordTranslationSettings {
  KeywordTranslationSettings._(this._persistence);

  factory KeywordTranslationSettings.forTest({
    SharedPreferencesProvider? preferencesProvider,
    KeywordTranslationPersistence? persistence,
  }) {
    assert(preferencesProvider == null || persistence == null);
    return KeywordTranslationSettings._(
      persistence ??
          _SharedPreferencesKeywordTranslationPersistence(
            preferencesProvider ?? SharedPreferences.getInstance,
          ),
    );
  }

  static const preferenceKey = 'keywordTranslationEnabled';
  static final instance = KeywordTranslationSettings._(
    _SharedPreferencesKeywordTranslationPersistence(
      SharedPreferences.getInstance,
    ),
  );

  final KeywordTranslationPersistence _persistence;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  Future<void> _operationTail = Future<void>.value();
  bool _lastPersistedValue = true;
  int _generation = 0;

  Future<void> load() {
    final generation = ++_generation;
    return _enqueue<void>(() async {
      var restoredValue = true;
      try {
        restoredValue = await _persistence.read() ?? true;
      } catch (_) {
        restoredValue = true;
      }
      _lastPersistedValue = restoredValue;
      if (generation == _generation) {
        enabled.value = restoredValue;
      }
    });
  }

  Future<void> setEnabled(bool value) {
    final generation = ++_generation;
    enabled.value = value;
    return _enqueue<void>(() async {
      try {
        await _persistence.write(value);
        _lastPersistedValue = value;
      } catch (error, stackTrace) {
        if (generation == _generation) {
          enabled.value = _lastPersistedValue;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

final class _SharedPreferencesKeywordTranslationPersistence
    implements KeywordTranslationPersistence {
  const _SharedPreferencesKeywordTranslationPersistence(this._provider);

  final SharedPreferencesProvider _provider;

  @override
  Future<bool?> read() async {
    final preferences = await _provider();
    return preferences.getBool(KeywordTranslationSettings.preferenceKey);
  }

  @override
  Future<void> write(bool value) async {
    final preferences = await _provider();
    final saved = await preferences.setBool(
      KeywordTranslationSettings.preferenceKey,
      value,
    );
    if (!saved) {
      throw StateError(
        'Failed to save ${KeywordTranslationSettings.preferenceKey}',
      );
    }
  }
}
