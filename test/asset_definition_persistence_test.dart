import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/assets/data/repositories/local_asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pilgrim-asset-definition-test-',
    );

    databasePath = p.join(temporaryDirectory.path, 'pilgrim_tracker_test.db');
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('native store persists and restores an asset definition', () async {
    final store = LocalStore(databasePath: databasePath);

    await store.initialize();

    addTearDown(store.close);

    final definition = _stockDefinition();

    await store.upsertAssetDefinition(definition.toRecord());

    final records = await store.getAssetDefinitions();

    expect(records, hasLength(1));

    final restored = AssetDefinition.fromRecord(records.single);

    expect(restored.id, definition.id);
    expect(restored.displayName, 'Bank Central Asia');
    expect(restored.kind, AssetKind.stock);
    expect(restored.symbol, 'BBCA');
    expect(restored.providerSymbol, 'BBCA.JK');
    expect(restored.exchangeCode, 'IDX');
    expect(restored.currencyCode, 'IDR');
    expect(restored.unit, 'share');
    expect(restored.lotSize, 100);
  });

  test('soft-deleted definitions are excluded by default', () async {
    final store = LocalStore(databasePath: databasePath);

    await store.initialize();

    addTearDown(store.close);

    final definition = _stockDefinition();

    await store.upsertAssetDefinition(definition.toRecord());

    await store.softDeleteAssetDefinition(
      definition.id,
      DateTime.utc(2026, 7, 22).millisecondsSinceEpoch,
    );

    expect(await store.getAssetDefinitions(), isEmpty);

    final includingDeleted = await store.getAssetDefinitions(
      includeDeleted: true,
    );

    expect(includingDeleted, hasLength(1));
    expect(includingDeleted.single['deleted_at'], isNotNull);
    expect(includingDeleted.single['version'], 2);
    expect(includingDeleted.single['sync_status'], 'pending');
  });

  test('asset definition seeds are idempotent', () async {
    final store = LocalStore(databasePath: databasePath);

    await store.initialize();

    addTearDown(store.close);

    final records = [
      _stockDefinition().toRecord(),
      _goldDefinition().toRecord(),
    ];

    await store.ensureAssetDefinitionSeeds(records);
    await store.ensureAssetDefinitionSeeds(records);

    final stored = await store.getAssetDefinitions();

    expect(stored, hasLength(2));
  });

  test(
    'version 5 database upgrades to latest schema without losing records',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final oldDatabase = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY,
              project_id TEXT
            )
          ''');

            await database.insert('transactions', {
              'id': 'existing-transaction',
              'project_id': 'existing-project',
            });
          },
        ),
      );

      await oldDatabase.close();

      final store = LocalStore(databasePath: databasePath);

      // Opening through LocalStore performs all migrations to the latest schema.
      await store.initialize();
      await store.close();

      // Inspect the upgraded database directly instead of exposing the
      // native-only LocalStore.db getter through the shared store API.
      final upgradedDatabase = await databaseFactory.openDatabase(databasePath);

      addTearDown(upgradedDatabase.close);

      final existingTransactions = await upgradedDatabase.query('transactions');

      expect(existingTransactions, hasLength(1));
      expect(existingTransactions.single['id'], 'existing-transaction');
      expect(existingTransactions.single['project_id'], 'existing-project');

      final assetDefinitionTables = await upgradedDatabase.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = 'asset_definitions'
      ''');

      expect(assetDefinitionTables, isNotEmpty);

      final projectIndexes = await upgradedDatabase.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
        AND name = 'idx_transactions_project'
      ''');

      expect(projectIndexes, isNotEmpty);
      final transactionColumns = await upgradedDatabase.rawQuery(
        'PRAGMA table_info(transactions)',
      );

      expect(
        transactionColumns.any(
          (column) => column['name'] == 'asset_definition_id',
        ),
        isTrue,
      );

      final assetDefinitionIndexes = await upgradedDatabase.rawQuery('''
SELECT name
FROM sqlite_master
WHERE type = 'index'
  AND name = 'idx_transactions_asset_definition'
''');

      expect(assetDefinitionIndexes, isNotEmpty);
    },
  );

  test(
    'version 6 database upgrades to version 7 with nullable asset link',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final oldDatabase = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (database, version) async {
            await database.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            asset_name TEXT,
            asset_symbol TEXT
          )
        ''');

            await database.insert('transactions', {
              'id': 'legacy-stock-transaction',
              'asset_name': 'Stock Portfolio',
              'asset_symbol': 'BBCA',
            });
          },
        ),
      );

      await oldDatabase.close();

      final store = LocalStore(databasePath: databasePath);

      await store.initialize();
      await store.close();

      final upgradedDatabase = await databaseFactory.openDatabase(databasePath);

      addTearDown(upgradedDatabase.close);

      final transactions = await upgradedDatabase.query('transactions');

      expect(transactions, hasLength(1));
      expect(transactions.single['id'], 'legacy-stock-transaction');
      expect(transactions.single['asset_name'], 'Stock Portfolio');
      expect(transactions.single['asset_symbol'], 'BBCA');
      expect(transactions.single['asset_definition_id'], isNull);

      final columns = await upgradedDatabase.rawQuery(
        'PRAGMA table_info(transactions)',
      );

      expect(
        columns.any((column) => column['name'] == 'asset_definition_id'),
        isTrue,
      );

      final indexes = await upgradedDatabase.rawQuery('''
SELECT name
FROM sqlite_master
WHERE type = 'index'
  AND name = 'idx_transactions_asset_definition'
''');

      expect(indexes, isNotEmpty);
    },
  );

  test('repository maps definitions through LocalStore', () async {
    final store = LocalStore(databasePath: databasePath);

    await store.initialize();

    addTearDown(store.close);

    final repository = LocalAssetDefinitionRepository(store);
    final definition = _stockDefinition();

    await repository.upsert(definition);

    final restored = await repository.getById(definition.id);

    expect(restored, isNotNull);
    expect(restored!.symbol, 'BBCA');
    expect(restored.providerSymbol, 'BBCA.JK');

    final all = await repository.getAll();

    expect(all, hasLength(1));
  });

  test('repository rejects invalid definitions', () async {
    final store = LocalStore(databasePath: databasePath);

    await store.initialize();

    addTearDown(store.close);

    final repository = LocalAssetDefinitionRepository(store);

    final invalid = _stockDefinition().copyWith(symbol: null, lotSize: 0);

    expect(() => repository.upsert(invalid), throwsArgumentError);

    expect(await repository.getAll(), isEmpty);
  });
}

AssetDefinition _stockDefinition() {
  return AssetDefinition(
    id: 'asset-bbca',
    displayName: 'Bank Central Asia',
    kind: AssetKind.stock,
    symbol: 'BBCA',
    providerCode: 'alpha_vantage',
    providerSymbol: 'BBCA.JK',
    exchangeCode: 'IDX',
    currencyCode: 'IDR',
    unit: 'share',
    lotSize: 100,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21, 10),
    updatedAt: DateTime.utc(2026, 7, 21, 10),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

AssetDefinition _goldDefinition() {
  return AssetDefinition(
    id: 'asset-gold',
    displayName: 'Gold Holdings',
    kind: AssetKind.gold,
    symbol: null,
    providerCode: 'alpha_vantage',
    providerSymbol: 'XAU',
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: 'gram',
    lotSize: 1,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21, 10),
    updatedAt: DateTime.utc(2026, 7, 21, 10),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}
