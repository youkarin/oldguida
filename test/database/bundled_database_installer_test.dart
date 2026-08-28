import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/database/bundled_database_installer.dart';
import 'package:italian_driving_app/database/keyword_database.dart';
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
      validateDatabase: _validateBundledDatabase,
      runExclusive: _runImmediately,
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
      validateDatabase: _validateBundledDatabase,
      runExclusive: _runImmediately,
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

  test('target created while bundled bytes load is not overwritten', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');

    final installed = await BundledDatabaseInstaller.installIfMissing(
      factory: databaseFactoryFfi,
      path: databasePath,
      loadBytes: () async {
        final competingDatabase = await _openDatabase(databasePath);
        await competingDatabase.execute(
          'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
        );
        await competingDatabase.insert(
          'users',
          {'id': 11, 'name': 'race-winner'},
        );
        await competingDatabase.close();
        return _loadBundledQuizBytes();
      },
      validateDatabase: _validateBundledDatabase,
      runExclusive: _runImmediately,
    );

    expect(installed, isFalse);
    final reopened = await _openDatabase(databasePath);
    addTearDown(reopened.close);
    expect(await reopened.query('users'), [
      {'id': 11, 'name': 'race-winner'},
    ]);
    expect(await _tableExists(reopened, 'quiz'), isFalse);
  });

  test('concurrent installers serialize and only one writes', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    final lock = _SerialExclusiveLock();
    final firstLoadStarted = Completer<void>();
    final releaseFirstLoad = Completer<void>();
    var loadCount = 0;

    Future<Uint8List> loadBytes() async {
      loadCount++;
      if (loadCount == 1) {
        firstLoadStarted.complete();
        await releaseFirstLoad.future;
      }
      return _loadBundledQuizBytes();
    }

    final first = BundledDatabaseInstaller.installIfMissing(
      factory: databaseFactoryFfi,
      path: databasePath,
      loadBytes: loadBytes,
      validateDatabase: _validateBundledDatabase,
      runExclusive: lock.run,
    );
    await firstLoadStarted.future;
    final second = BundledDatabaseInstaller.installIfMissing(
      factory: databaseFactoryFfi,
      path: databasePath,
      loadBytes: loadBytes,
      validateDatabase: _validateBundledDatabase,
      runExclusive: lock.run,
    );
    await Future<void>.delayed(Duration.zero);
    releaseFirstLoad.complete();

    final results = await Future.wait([first, second]);
    expect(results, [isTrue, isFalse]);
    expect(loadCount, 1);
    expect(lock.names, hasLength(2));
    expect(lock.names.toSet(), hasLength(1));
    expect(lock.names, everyElement(contains(databasePath)));
    final database = await _openDatabase(databasePath);
    addTearDown(database.close);
    expect(await _count(database, 'quiz'), 7193);
  });

  test('partial write is deleted and a later install can retry', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    final writeError = StateError('partial bundled database write');
    final factory = _PartialWriteFactory(
      delegate: databaseFactoryFfi,
      writeError: writeError,
    );

    await expectLater(
      BundledDatabaseInstaller.installIfMissing(
        factory: factory,
        path: databasePath,
        loadBytes: _loadBundledQuizBytes,
        validateDatabase: _validateBundledDatabase,
        runExclusive: _runImmediately,
      ),
      throwsA(same(writeError)),
    );
    expect(await databaseFactoryFfi.databaseExists(databasePath), isFalse);

    final installed = await BundledDatabaseInstaller.installIfMissing(
      factory: factory,
      path: databasePath,
      loadBytes: _loadBundledQuizBytes,
      validateDatabase: _validateBundledDatabase,
      runExclusive: _runImmediately,
    );

    expect(installed, isTrue);
    final database = await _openDatabase(databasePath);
    addTearDown(database.close);
    expect(await _count(database, 'quiz'), 7193);
  });

  test('cleanup failure does not replace the original write error', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    final writeError = StateError('primary write failure');
    final factory = _PartialWriteFactory(
      delegate: databaseFactoryFfi,
      writeError: writeError,
      deleteError: StateError('cleanup failure'),
    );

    await expectLater(
      BundledDatabaseInstaller.installIfMissing(
        factory: factory,
        path: databasePath,
        loadBytes: _loadBundledQuizBytes,
        validateDatabase: _validateBundledDatabase,
        runExclusive: _runImmediately,
      ),
      throwsA(same(writeError)),
    );
    expect(factory.deleteAttempts, 1);
  });

  test('asset load failure propagates without creating the target', () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    final loadError = StateError('bundled asset load failed');
    var validationCalls = 0;

    await expectLater(
      BundledDatabaseInstaller.installIfMissing(
        factory: databaseFactoryFfi,
        path: databasePath,
        loadBytes: () => Future<Uint8List>.error(loadError),
        validateDatabase: (_) async {
          validationCalls++;
        },
        runExclusive: _runImmediately,
      ),
      throwsA(same(loadError)),
    );

    expect(validationCalls, 0);
    expect(await databaseFactoryFfi.databaseExists(databasePath), isFalse);
  });

  test('validation failure propagates and deletes the installed target',
      () async {
    final databasePath = path.join(temporaryDirectory.path, 'quiz.db');
    final validationError = StateError('bundled validation failed');

    await expectLater(
      BundledDatabaseInstaller.installIfMissing(
        factory: databaseFactoryFfi,
        path: databasePath,
        loadBytes: _loadBundledQuizBytes,
        validateDatabase: (installedPath) async {
          expect(installedPath, databasePath);
          expect(
            await databaseFactoryFfi.databaseExists(installedPath),
            isTrue,
          );
          throw validationError;
        },
        runExclusive: _runImmediately,
      ),
      throwsA(same(validationError)),
    );

    expect(await databaseFactoryFfi.databaseExists(databasePath), isFalse);
  });
}

class _SerialExclusiveLock {
  final names = <String>[];
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String name, Future<T> Function() action) {
    names.add(name);
    final previous = _tails[name] ?? Future<void>.value();
    final release = Completer<void>();
    _tails[name] = release.future;

    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }
}

class _PartialWriteFactory implements DatabaseFactory {
  _PartialWriteFactory({
    required this.delegate,
    required this.writeError,
    this.deleteError,
  });

  final DatabaseFactory delegate;
  final Object writeError;
  final Object? deleteError;
  var failNextWrite = true;
  var deleteAttempts = 0;

  @override
  Future<bool> databaseExists(String path) => delegate.databaseExists(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) async {
    if (!failNextWrite) {
      await delegate.writeDatabaseBytes(path, bytes);
      return;
    }

    failNextWrite = false;
    await delegate.writeDatabaseBytes(
      path,
      Uint8List.sublistView(bytes, 0, 128),
    );
    throw writeError;
  }

  @override
  Future<void> deleteDatabase(String path) async {
    deleteAttempts++;
    final error = deleteError;
    if (error != null) throw error;
    await delegate.deleteDatabase(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<T> _runImmediately<T>(
  String name,
  Future<T> Function() action,
) =>
    action();

Future<Uint8List> _loadBundledQuizBytes() async {
  final data = await rootBundle.load('assets/db/quiz.db');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<void> _validateBundledDatabase(String databasePath) async {
  final database = await _openDatabase(databasePath);
  try {
    await KeywordDatabase.validateBundledDatabase(database);
  } finally {
    await database.close();
  }
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
