import 'dart:async';

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

  test('set failure restores the last persisted value and returns the error',
      () async {
    final persistence = _ControlledPersistence(initialValue: true);
    final settings = KeywordTranslationSettings.forTest(
      persistence: persistence,
    );

    final write = settings.setEnabled(false);
    expect(settings.enabled.value, isFalse);
    await _flushMicrotasks();
    persistence.writes.single.fail(StateError('write failed'));

    await expectLater(write, throwsStateError);
    expect(settings.enabled.value, isTrue);
    expect(persistence.storedValue, isTrue);
  });

  test('serializes false then true writes and keeps latest UI and storage',
      () async {
    final persistence = _ControlledPersistence(initialValue: true);
    final settings = KeywordTranslationSettings.forTest(
      persistence: persistence,
    );

    final first = settings.setEnabled(false);
    final second = settings.setEnabled(true);
    expect(settings.enabled.value, isTrue);

    await _flushMicrotasks();
    expect(persistence.writes.map((request) => request.value), [false]);

    persistence.writes[0].succeed();
    await first;
    await _flushMicrotasks();
    expect(persistence.writes.map((request) => request.value), [false, true]);

    persistence.writes[1].succeed();
    await second;
    expect(settings.enabled.value, isTrue);
    expect(persistence.storedValue, isTrue);
  });

  test('a failed first write does not block a successful latest write',
      () async {
    final persistence = _ControlledPersistence(initialValue: true);
    final settings = KeywordTranslationSettings.forTest(
      persistence: persistence,
    );

    final first = settings.setEnabled(false);
    final firstError = expectLater(first, throwsStateError);
    final second = settings.setEnabled(true);
    await _flushMicrotasks();

    persistence.writes[0].fail(StateError('first failed'));
    await firstError;
    await _flushMicrotasks();
    expect(persistence.writes.map((request) => request.value), [false, true]);
    expect(settings.enabled.value, isTrue);

    persistence.writes[1].succeed();
    await second;
    expect(settings.enabled.value, isTrue);
    expect(persistence.storedValue, isTrue);
  });

  test('latest write failure rolls UI back to the last successful write',
      () async {
    final persistence = _ControlledPersistence(initialValue: true);
    final settings = KeywordTranslationSettings.forTest(
      persistence: persistence,
    );

    final first = settings.setEnabled(false);
    final second = settings.setEnabled(true);
    final secondError = expectLater(second, throwsStateError);
    await _flushMicrotasks();

    persistence.writes[0].succeed();
    await first;
    await _flushMicrotasks();
    expect(persistence.storedValue, isFalse);
    expect(settings.enabled.value, isTrue);

    persistence.writes[1].fail(StateError('latest failed'));
    await secondError;
    expect(settings.enabled.value, isFalse);
    expect(persistence.storedValue, isFalse);
  });

  test('a set queued behind load stays immediate and persists after the read',
      () async {
    final persistence = _ControlledPersistence(
      initialValue: true,
      deferRead: true,
    );
    final settings = KeywordTranslationSettings.forTest(
      persistence: persistence,
    );

    final load = settings.load();
    final write = settings.setEnabled(false);
    expect(settings.enabled.value, isFalse);
    await _flushMicrotasks();
    expect(persistence.writes, isEmpty);

    persistence.completeRead(true);
    await load;
    expect(settings.enabled.value, isFalse);
    await _flushMicrotasks();
    expect(persistence.writes.map((request) => request.value), [false]);

    persistence.writes.single.succeed();
    await write;
    expect(settings.enabled.value, isFalse);
    expect(persistence.storedValue, isFalse);
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

  testWidgets('settings screen consumes persistence errors and shows rollback',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final persistence = _ControlledPersistence(initialValue: true);
    final settings = KeywordTranslationSettings.forTest(
      persistence: persistence,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(keywordTranslationSettings: settings),
      ),
    );
    await tester.pumpAndSettle();

    final keywordTile = find.widgetWithText(SwitchListTile, '题目关键词翻译');
    await tester.tap(keywordTile);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(keywordTile).value, isFalse);
    await tester.pump();

    persistence.writes.single.fail(StateError('write failed'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.widget<SwitchListTile>(keywordTile).value, isTrue);
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

final class _ControlledPersistence implements KeywordTranslationPersistence {
  _ControlledPersistence({
    required bool initialValue,
    this.deferRead = false,
  }) : storedValue = initialValue;

  bool storedValue;
  final bool deferRead;
  final List<_WriteRequest> writes = [];
  Completer<bool?>? _readCompleter;

  @override
  Future<bool?> read() {
    if (!deferRead) return Future<bool?>.value(storedValue);
    return (_readCompleter ??= Completer<bool?>()).future;
  }

  void completeRead(bool? value) {
    (_readCompleter ??= Completer<bool?>()).complete(value);
  }

  @override
  Future<void> write(bool value) async {
    final request = _WriteRequest(value);
    writes.add(request);
    await request.completer.future;
    storedValue = value;
  }
}

final class _WriteRequest {
  _WriteRequest(this.value);

  final bool value;
  final Completer<void> completer = Completer<void>();

  void succeed() => completer.complete();

  void fail(Object error) => completer.completeError(error);
}
