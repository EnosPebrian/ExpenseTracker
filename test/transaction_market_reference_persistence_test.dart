import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  test(
    'v9 migration preserves data and reference snapshot round-trips',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pilgrim-market-reference-',
      );
      final databasePath = p.join(directory.path, 'test.db');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final oldDatabase = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 9,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY, project_id TEXT, title TEXT NOT NULL,
              category TEXT NOT NULL, account TEXT NOT NULL,
              transaction_date INTEGER NOT NULL, amount INTEGER NOT NULL,
              transaction_type TEXT NOT NULL, quantity REAL, unit TEXT,
              unit_price INTEGER, asset_definition_id TEXT, asset_name TEXT,
              asset_symbol TEXT, asset_action TEXT,
              fee_amount INTEGER NOT NULL DEFAULT 0,
              fee_treatment TEXT NOT NULL DEFAULT 'none',
              related_transaction_id TEXT,
              relation_type TEXT NOT NULL DEFAULT 'none',
              created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
              deleted_at INTEGER, version INTEGER NOT NULL DEFAULT 1,
              device_id TEXT NOT NULL,
              sync_status TEXT NOT NULL DEFAULT 'local_only'
            )
          ''');
            await database.execute(
              'CREATE TABLE asset_definitions '
              '(id TEXT PRIMARY KEY, display_name TEXT NOT NULL)',
            );
            await database.execute(
              'CREATE TABLE asset_market_prices '
              '(asset_key TEXT PRIMARY KEY, price_minor INTEGER NOT NULL)',
            );
          },
        ),
      );
      final timestamp = DateTime.utc(2026, 7, 24).millisecondsSinceEpoch;
      await oldDatabase.insert('transactions', {
        'id': 'legacy',
        'title': 'Legacy USD trade',
        'category': 'Asset conversion',
        'account': 'Cash -> USD',
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
        'fee_treatment': 'recordAsSeparateExpense',
        'related_transaction_id': 'parent',
        'relation_type': 'assetFeeExpense',
        'created_at': timestamp,
        'updated_at': timestamp,
        'version': 2,
        'device_id': 'test',
        'sync_status': 'synced',
      });
      await oldDatabase.insert('asset_definitions', {
        'id': 'asset-usd',
        'display_name': 'US Dollar Cash',
      });
      await oldDatabase.insert('asset_market_prices', {
        'asset_key': 'USD',
        'price_minor': 16250,
      });
      await oldDatabase.close();

      final store = LocalStore(databasePath: databasePath);
      await store.initialize();
      addTearDown(store.close);
      final repository = LocalTransactionRepository(store);

      final legacy = (await repository.getAll()).single;
      expect(legacy.feeAmount, 100000);
      expect(legacy.relationType, TransactionRelationType.assetFeeExpense);
      expect(legacy.marketReferenceUnitPrice, isNull);

      final referenceTime = DateTime.utc(2026, 7, 24, 8, 30);
      final referenced = Transaction(
        id: 'referenced',
        title: 'USD acquisition',
        category: 'Asset conversion',
        account: 'Cash -> USD',
        date: referenceTime,
        amount: 16300000,
        type: TransactionType.assetConversion,
        quantity: 1000,
        unit: 'usd',
        unitPrice: 16300,
        assetDefinitionId: 'asset-usd',
        assetName: 'US Dollar Cash',
        assetSymbol: 'USD',
        assetAction: AssetAction.buy,
        marketReferenceUnitPrice: 16250,
        marketReferenceCurrencyCode: 'IDR',
        marketReferenceUnit: 'usd',
        marketReferenceSource: AssetMarketReferenceSource.cachedQuote,
        marketReferenceQuotedAt: referenceTime,
      );
      await repository.save(referenced);
      final restored = (await repository.getAll()).firstWhere(
        (transaction) => transaction.id == 'referenced',
      );
      expect(restored.marketReferenceUnitPrice, 16250);
      expect(restored.marketReferenceCurrencyCode, 'IDR');
      expect(restored.marketReferenceUnit, 'usd');
      expect(
        restored.marketReferenceSource,
        AssetMarketReferenceSource.cachedQuote,
      );
      expect(
        restored.marketReferenceQuotedAt?.millisecondsSinceEpoch,
        referenceTime.millisecondsSinceEpoch,
      );

      final verificationDatabase = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(verificationDatabase.close);
      expect(
        (await verificationDatabase.rawQuery(
          'PRAGMA user_version',
        )).single['user_version'],
        10,
      );
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
        16250,
      );
    },
  );
}
