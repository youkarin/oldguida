import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/database/bundled_database_installer.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'oldguida_bundled_database_installer_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('missing target installs the complete bundled quiz database', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    expect(await databaseFactoryFfi.databaseExists(databasePath), isFalse);

    final installed = await BundledDatabaseInstaller.installIfMissing(
      factory: databaseFactoryFfi,
      path: databasePath,
      loadBytes: _loadBundledQuizBytes,
    );

    expect(installed, isTrue);
    final database = await _openDatabase(databasePath);
    addTearDown(database.close);
    expect(await _count(database, 'quiz'), 7193);
    expect(await _count(database, 'chapter'), 25);
    expect(await _count(database, 'section'), 925);
    expect(await _count(database, 'keyword_dictionary'), 631);
    expect(
      await database.query(
        'dictionary_meta',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['version'],
      ),
      [
        {'value': '1'},
      ],
    );
  });

  test('existing target and its user rows are never overwritten', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    final existing = await _openDatabase(databasePath);
    await existing.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
    );
    await existing.insert('users', {'id': 7, 'name': 'keep'});
    await existing.close();

    final installed = await BundledDatabaseInstaller.installIfMissing(
      factory: databaseFactoryFfi,
      path: databasePath,
      loadBytes: _loadBundledQuizBytes,
    );

    expect(installed, isFalse);
    final reopened = await _openDatabase(databasePath);
    addTearDown(reopened.close);
    expect(await reopened.query('users'), [
      {'id': 7, 'name': 'keep'},
    ]);
    expect(await _tableExists(reopened, 'quiz'), isFalse);
    expect(await _tableExists(reopened, 'keyword_dictionary'), isFalse);
  });
}

Future<Uint8List> _loadBundledQuizBytes() async {
  final data = await rootBundle.load('assets/db/quiz.db');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Database> _openDatabase(String databasePath) =>
    databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );

Future<int> _count(Database database, String table) async =>
    Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM $table'),
    )!;

Future<bool> _tableExists(Database database, String table) async =>
    (await database.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name = ?",
      whereArgs: [table],
      limit: 1,
    ))
        .isNotEmpty;
