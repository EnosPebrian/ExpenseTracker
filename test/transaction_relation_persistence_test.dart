import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pilgrim-transaction-relation-test-',
    );
    databasePath = p.join(temporaryDirectory.path, 'pilgrim_tracker_test.db');
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('linked fee relationship survives native SQLite round trip', () async {
    final store = LocalStore(databasePath: databasePath);
    await store.initialize();
    addTearDown(store.close);
    final repository = LocalTransactionRepository(store);
    final parent = _parent();
    final child = _child(parent.id);

    await repository.saveAssetFeeChange(parent: parent, linkedExpense: child);

    final restoredChild = await repository.getAssetFeeExpense(parent.id);
    expect(restoredChild!.id, child.id);
    expect(restoredChild.relatedTransactionId, parent.id);
    expect(restoredChild.relationType, TransactionRelationType.assetFeeExpense);
  });

  test('version 8 upgrades to latest without losing D12 data', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final oldDatabase = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 8,
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
              fee_amount INTEGER NOT NULL DEFAULT 0,
              fee_treatment TEXT NOT NULL DEFAULT 'none',
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
        },
      ),
    );
    final timestamp = DateTime(2026, 7, 24).millisecondsSinceEpoch;
    await oldDatabase.insert('transactions', {
      'id': 'legacy-parent',
      'project_id': 'life',
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
      'fee_amount': 100000,
      'fee_treatment': 'capitalizeIntoCostBasis',
      'created_at': timestamp,
      'updated_at': timestamp,
      'version': 3,
      'device_id': 'device-a',
      'sync_status': 'synced',
    });
    await oldDatabase.insert('asset_definitions', {
      'id': 'asset-usd',
      'display_name': 'US Dollar Cash',
    });
    await oldDatabase.insert('asset_market_prices', {
      'asset_key': 'asset-usd',
      'price_minor': 16450,
    });
    await oldDatabase.close();

    final store = LocalStore(databasePath: databasePath);
    await store.initialize();
    addTearDown(store.close);
    final repository = LocalTransactionRepository(store);
    final restored = (await repository.getAll()).single;

    expect(restored.id, 'legacy-parent');
    expect(restored.feeAmount, 100000);
    expect(restored.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(restored.assetDefinitionId, 'asset-usd');
    expect(restored.assetName, 'US Dollar Cash');
    expect(restored.assetSymbol, 'USD');
    expect(restored.relatedTransactionId, isNull);
    expect(restored.relationType, TransactionRelationType.none);
    expect(restored.version, 3);
    expect(restored.deviceId, 'device-a');
    expect(restored.syncStatus, 'synced');
    expect(restored.deletedAt, isNull);
    expect(restored.marketReferenceUnitPrice, isNull);

    final verificationDatabase = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    addTearDown(verificationDatabase.close);
    expect(
      (await verificationDatabase.query(
        'asset_definitions',
      )).single['display_name'],
      'US Dollar Cash',
    );
    expect(
      (await verificationDatabase.query(
        'asset_market_prices',
      )).single['price_minor'],
      16450,
    );
    expect(
      (await verificationDatabase.rawQuery(
        'PRAGMA user_version',
      )).single['user_version'],
      10,
    );
  });
}

Transaction _parent() => Transaction(
  id: 'parent-usd',
  title: 'USD acquisition',
  category: 'Asset conversion',
  account: 'Cash -> US Dollar Cash',
  date: DateTime(2026, 7, 24),
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
  feeTreatment: AssetFeeTreatment.recordAsSeparateExpense,
);

Transaction _child(String parentId) => Transaction(
  id: 'child-fee',
  title: 'Fee - Buy USD',
  category: 'Asset Fees',
  account: 'Cash',
  date: DateTime(2026, 7, 24),
  amount: 100000,
  type: TransactionType.expense,
  relatedTransactionId: parentId,
  relationType: TransactionRelationType.assetFeeExpense,
);
