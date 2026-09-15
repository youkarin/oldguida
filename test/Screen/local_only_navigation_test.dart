import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:italian_driving_app/Screen/Homepage.dart';

void main() {
  testWidgets('record menu exposes only local study functions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.tap(find.text('记录'));
    await tester.pump();
    expect(find.text('学习记录'), findsWidgets);
    expect(find.text('收藏夹'), findsOneWidget);
    expect(find.text('错题复习'), findsOneWidget);
    for (final label in ['EXAM', '单词必对题', '单词必错题', '易错题', '登录', '会员']) {
      expect(find.text(label), findsNothing);
    }
    // Dispose before the unchanged delayed GitHub update check can fire.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
