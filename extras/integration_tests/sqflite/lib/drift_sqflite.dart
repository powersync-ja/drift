import 'dart:io';

import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:test/test.dart';
import 'package:tests/tests.dart';

class SqfliteExecutor extends TestExecutor {
  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection.fromExecutor(
      SqfliteQueryExecutor.inDatabaseFolder(
        path: 'app.db',
        singleInstance: false,
      ),
    );
  }

  @override
  Future deleteData() async {
    final folder = await getDatabasesPath();
    final file = File(join(folder, 'app.db'));

    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runAllTests(SqfliteExecutor());

  // Additional integration test for flutter: Test loading a database from asset
  test('can load a database from asset', () async {
    final databasesPath = await getDatabasesPath();
    final dbFile = File(join(databasesPath, 'app_from_asset.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    var didCallCreator = false;
    final executor = SqfliteQueryExecutor(
      path: dbFile.path,
      singleInstance: true,
      creator: (file) async {
        final content = await rootBundle.load('test_asset.db');
        await file.writeAsBytes(content.buffer.asUint8List());
        didCallCreator = true;
      },
    );
    final database = Database.executor(executor);
    await database.executor.ensureOpen(database);
    addTearDown(database.close);

    expect(didCallCreator, isTrue);
  });

  test('can rollback transactions', () async {
    final executor = SqfliteQueryExecutor(path: ':memory:');
    final database = EmptyDb(executor);
    addTearDown(database.close);

    final expectedException = Exception('oops');

    try {
      await database
          .customSelect('select 1')
          .getSingle(); // ensure database is open/created

      await database.transaction(() async {
        await database.customSelect('select 1').watchSingle().first;
        throw expectedException;
      });
    } catch (e) {
      expect(e, expectedException);
    } finally {
      await database.customSelect('select 1').getSingle().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () => fail('deadlock?'),
          );
    }
  }, timeout: const Timeout.factor(100));
}

class EmptyDb extends GeneratedDatabase {
  EmptyDb(QueryExecutor q) : super(SqlTypeSystem.defaultInstance, q);
  @override
  final List<TableInfo> allTables = const [];
  @override
  final schemaVersion = 1;
}