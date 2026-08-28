import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

typedef ExclusiveLockRunner = Future<T> Function<T>(
  String name,
  Future<T> Function() action,
);

abstract final class BundledDatabaseInstaller {
  static String lockName(String path) =>
      'oldguida:bundled-database-install:$path';

  static Future<bool> installIfMissing({
    required DatabaseFactory factory,
    required String path,
    required Future<Uint8List> Function() loadBytes,
    required Future<void> Function(String path) validateDatabase,
    required ExclusiveLockRunner runExclusive,
  }) {
    return runExclusive<bool>(
      lockName(path),
      () async {
        if (await factory.databaseExists(path)) return false;

        final bytes = await loadBytes();
        if (await factory.databaseExists(path)) return false;

        try {
          await factory.writeDatabaseBytes(path, bytes);
          await validateDatabase(path);
        } catch (error, stackTrace) {
          try {
            await factory.deleteDatabase(path);
          } catch (_) {
            // Keep the original write failure as the actionable error.
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        return true;
      },
    );
  }
}
