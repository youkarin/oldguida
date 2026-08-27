import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Screen/General/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'OldGuida',
      packageName: 'italian_driving_app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('stay switch is hidden until immediate feedback is enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'immediateFeedback': false,
      'stayOnWrongAnswer': true,
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('错题自动停留'), findsNothing);

    await tester.tap(find.text('立即提示正误'));
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, '错题自动停留');
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('stay switch defaults off and persists a change', (tester) async {
    SharedPreferences.setMockInitialValues({'immediateFeedback': true});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, '错题自动停留');
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(
      (await SharedPreferences.getInstance()).getBool('stayOnWrongAnswer'),
      isTrue,
    );
  });
}
