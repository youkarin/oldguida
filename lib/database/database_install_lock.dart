import 'database_install_lock_stub.dart'
    if (dart.library.js_interop) 'database_install_lock_web.dart' as platform;

Future<T> runWithDatabaseInstallLock<T>(
  String name,
  Future<T> Function() action,
) =>
    platform.runWithDatabaseInstallLockImpl(name, action);
