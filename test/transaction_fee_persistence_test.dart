import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pilgrim-transaction-fee-test-',
    );
    databasePath = p.join(temporaryDirectory.path, 'pilgrim_tracker_test.db');
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('fee fields survive a native SQLite round trip', () async {
    final store = LocalStore(databasePath: databasePath);
    await store.initialize();
    addTearDown(store.close);
    final repository = LocalTransactionRepository(store);
    final transaction = _feeTransaction();

    await repository.save(transaction);
    final restored = (await repository.getAll()).single;

    expect(restored.id, transaction.id);
    expect(restored.feeAmount, 100000);
    expect(restored.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(restored.assetDefinitionId, 'asset-usd');
    expect(restored.assetName, 'US Dollar Cash');
    expect(restored.assetSymbol, 'USD');
    expect(restored.assetAction, AssetAction.buy);
    expect(restored.quantity, 1000);
    expect(restored.unit, 'usd');
    expect(restored.unitPrice, 16200);
    expect(restored.amount, 16200000);
  });

  test(
    'version 7 upgrades to latest schema without losing asset data',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final oldDatabase = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY,
              project_id TEXT,
              title TEXT NOT NULL,
              category TEXT NOT NULL,
              account TEXT NOT NULL,
              transaction_date INTEGER NOT NULL,
              amount INTEGER NOT NULL,
              transaction_type TEXT NOT NULL,
              quantity REAL,
              unit TEXT,
              unit_price INTEGER,
              asset_definition_id TEXT,
              asset_name TEXT,
              asset_symbol TEXT,
              asset_action TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              version INTEGER NOT NULL DEFAULT 1,
              device_id TEXT NOT NULL,
              sync_status TEXT NOT NULL DEFAULT 'local_only'
            )
          ''');
            await database.execute('''
            CREATE TABLE asset_definitions (
              id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE asset_market_prices (
              asset_key TEXT PRIMARY KEY,
              price_minor INTEGER NOT NULL
            )
          ''');
            final timestamp = DateTime.utc(2026, 7, 24).millisecondsSinceEpoch;
            await database.insert('transactions', {
              'id': 'legacy-usd-buy',
              'project_id': 'investment',
              'title': 'USD acquisition',
              'category': 'Asset conversion',
              'account': 'Cash -> US Dollar Cash',
              'transaction_date': timestamp,
              'amount': 16200000,
              'transaction_type': 'assetConversion',
              'quantity': 1000.0,
              'unit': 'usd',
              'unit_price': 16200,
              'asset_definition_id': 'asset-usd',
              'asset_name': 'US Dollar Cash',
              'asset_symbol': 'USD',
              'asset_action': 'buy',
              'created_at': timestamp,
              'updated_at': timestamp,
              'version': 3,
              'device_id': 'legacy-device',
              'sync_status': 'synced',
            });
            await database.insert('asset_definitions', {
              'id': 'asset-usd',
              'display_name': 'US Dollar Cash',
            });
            await database.insert('asset_market_prices', {
              'asset_key': 'USD',
              'price_minor': 16450,
            });
          },
        ),
      );
      await oldDatabase.close();

      final store = LocalStore(databasePath: databasePath);
      await store.initialize();
      await store.close();

      final upgraded = await databaseFactory.openDatabase(databasePath);
      addTearDown(upgraded.close);
      final transaction = (await upgraded.query('transactions')).single;

      expect(transaction['fee_amount'], 0);
      expect(transaction['fee_treatment'], 'none');
      expect(transaction['related_transaction_id'], isNull);
      expect(transaction['relation_type'], 'none');
      expect(transaction['asset_definition_id'], 'asset-usd');
      expect(transaction['asset_name'], 'US Dollar Cash');
      expect(transaction['asset_symbol'], 'USD');
      expect(transaction['asset_action'], 'buy');
      expect(transaction['quantity'], 1000.0);
      expect(transaction['unit'], 'usd');
      expect(transaction['unit_price'], 16200);
      expect(transaction['amount'], 16200000);
      expect(transaction['deleted_at'], isNull);
      expect(transaction['version'], 3);
      expect(transaction['device_id'], 'legacy-device');
      expect(transaction['sync_status'], 'synced');
      expect(transaction['market_reference_unit_price'], isNull);
      expect(await upgraded.query('asset_definitions'), hasLength(1));
      expect(
        (await upgraded.query('asset_market_prices')).single['price_minor'],
        16450,
      );

      final version = await upgraded.rawQuery('PRAGMA user_version');
      expect(version.single['user_version'], 10);
    },
  );
}

Transaction _feeTransaction() {
  final timestamp = DateTime.utc(2026, 7, 24, 10);
  return Transaction(
    id: 'usd-buy-with-fee',
    projectId: 'investment',
    title: 'USD acquisition',
    category: 'Asset conversion',
    account: 'Cash -> US Dollar Cash',
    date: timestamp,
    amount: 16200000,
    type: TransactionType.assetConversion,
    quantity: 1000,
    unit: 'usd',
    unitPrice: 16200,
    assetDefinitionId: 'asset-usd',
    assetName: 'US Dollar Cash',
    assetSymbol: 'USD',
    assetAction: AssetAction.buy,
    feeAmount: 100000,
    feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
