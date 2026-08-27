import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SharedPreferencesProvider = Future<SharedPreferences> Function();

final class KeywordTranslationSettings {
  KeywordTranslationSettings._({SharedPreferencesProvider? preferencesProvider})
      : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance;

  factory KeywordTranslationSettings.forTest({
    SharedPreferencesProvider? preferencesProvider,
  }) =>
      KeywordTranslationSettings._(
        preferencesProvider: preferencesProvider,
      );

  static const preferenceKey = 'keywordTranslationEnabled';
  static final instance = KeywordTranslationSettings._();

  final SharedPreferencesProvider _preferencesProvider;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    var restoredValue = true;
    try {
      final preferences = await _preferencesProvider();
      restoredValue = preferences.getBool(preferenceKey) ?? true;
    } catch (_) {
      restoredValue = true;
    }
    if (generation == _generation) {
      enabled.value = restoredValue;
    }
  }

  Future<void> setEnabled(bool value) async {
    final generation = ++_generation;
    final previousValue = enabled.value;
    enabled.value = value;
    try {
      final preferences = await _preferencesProvider();
      final saved = await preferences.setBool(preferenceKey, value);
      if (!saved && generation == _generation) {
        enabled.value = previousValue;
      }
    } catch (_) {
      if (generation == _generation) {
        enabled.value = previousValue;
      }
    }
  }
}
