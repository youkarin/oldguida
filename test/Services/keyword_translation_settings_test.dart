import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Screen/General/settings_screen.dart';
import 'package:italian_driving_app/Services/keyword_translation_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'OldGuida',
      packageName: 'italian_driving_app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('defaults on and persists changes with the exact preference key',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = KeywordTranslationSettings.forTest();

    await settings.load();
    expect(settings.enabled.value, isTrue);

    await settings.setEnabled(false);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(KeywordTranslationSettings.preferenceKey),
      isFalse,
    );
    expect(preferences.getBool('keywordTranslationEnabled'), isFalse);
  });

  for (final restoredValue in [true, false]) {
    test('restores persisted $restoredValue', () async {
      SharedPreferences.setMockInitialValues({
        'keywordTranslationEnabled': restoredValue,
      });
      final settings = KeywordTranslationSettings.forTest();

      await settings.load();

      expect(settings.enabled.value, restoredValue);
    });
  }

  test('notifies observers immediately when the setting changes', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = KeywordTranslationSettings.forTest();
    final observed = <bool>[];
    settings.enabled.addListener(() => observed.add(settings.enabled.value));

    final write = settings.setEnabled(false);

    expect(settings.enabled.value, isFalse);
    expect(observed, [false]);
    await write;
  });

  test('load failure falls back to enabled without throwing', () async {
    final settings = KeywordTranslationSettings.forTest(
      preferencesProvider: () => Future.error(StateError('read failed')),
    );
    settings.enabled.value = false;

    await settings.load();

    expect(settings.enabled.value, isTrue);
  });

  test('set failure restores the last valid value without throwing', () async {
    final settings = KeywordTranslationSettings.forTest(
      preferencesProvider: () => Future.error(StateError('write failed')),
    );

    await settings.setEnabled(false);

    expect(settings.enabled.value, isTrue);
  });

  testWidgets(
      'settings screen updates the keyword switch and preserves stay visibility',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'immediateFeedback': false,
      'stayOnWrongAnswer': true,
    });
    final settings = KeywordTranslationSettings.forTest();
    await settings.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(keywordTranslationSettings: settings),
      ),
    );
    await tester.pumpAndSettle();

    final keywordTile = find.widgetWithText(SwitchListTile, '题目关键词翻译');
    expect(keywordTile, findsOneWidget);
    expect(find.text('在意大利语题目中划线显示可点击词条'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(keywordTile).value, isTrue);
    expect(find.text('错题自动停留'), findsNothing);

    await tester.tap(keywordTile);
    await tester.pump();

    expect(settings.enabled.value, isFalse);
    expect(tester.widget<SwitchListTile>(keywordTile).value, isFalse);

    await tester.tap(find.text('立即提示正误'));
    await tester.pumpAndSettle();

    final stayTile = find.widgetWithText(SwitchListTile, '错题自动停留');
    expect(stayTile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(stayTile).value, isTrue);
  });
}
