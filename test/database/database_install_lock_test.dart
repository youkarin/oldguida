import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/database/database_install_lock.dart';

void main() {
  test('non-web adapter fails closed without running the action', () async {
    var actionRan = false;

    await expectLater(
      runWithDatabaseInstallLock('oldguida:test', () async {
        actionRan = true;
        return 1;
      }),
      throwsA(isA<UnsupportedError>()),
    );

    expect(actionRan, isFalse);
  });
}
