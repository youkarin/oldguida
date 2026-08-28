import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

abstract final class BundledDatabaseInstaller {
  static Future<bool> installIfMissing({
    required DatabaseFactory factory,
    required String path,
    required Future<Uint8List> Function() loadBytes,
  }) async {
    if (await factory.databaseExists(path)) return false;

    final bytes = await loadBytes();
    await factory.writeDatabaseBytes(path, bytes);
    return true;
  }
}
