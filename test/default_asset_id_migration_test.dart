import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/master_data/default_asset_definition_ids.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'version 17 migrates only stable preset IDs and resumable payloads',
    () async {
      final directory = await Directory.systemTemp.createTemp('asset-id-v17-');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'migration.db');
      final store = LocalStore(databasePath: path);
      await store.initialize();
      final db = store.db;
      const bookId = 'book-1';
      const transactionId = 'transaction-1';
      const customId = 'asset-user-custom';
      final now = DateTime.utc(2026, 7, 29).millisecondsSinceEpoch;

      await db.insert(
        'asset_definitions',
        _definition('asset-usd', bookId, now),
      );
      await db.insert('asset_definitions', _definition(customId, bookId, now));
      await db.insert('transactions', {
        'id': transactionId,
        'book_id': bookId,
        'title': 'Synthetic conversion',
        'category': 'Asset conversion',
        'account': 'Synthetic account',
        'transaction_date': now,
        'amount': 100,
        'transaction_type': 'assetConversion',
        'asset_definition_id': 'asset-usd',
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });
      await db.insert('initial_sync_staging', {
        'book_id': bookId,
        'direction': 'upload',
        'entity_type': 'asset_definitions',
        'entity_id': 'asset-usd',
        'payload_json': jsonEncode(_definition('asset-usd', bookId, now)),
      });
      await db.insert('initial_sync_staging', {
        'book_id': bookId,
        'direction': 'upload',
        'entity_type': 'transactions',
        'entity_id': transactionId,
        'payload_json': jsonEncode({
          'id': transactionId,
          'asset_definition_id': 'asset-usd',
        }),
      });
      await db.setVersion(16);
      await store.close();

      final reopened = LocalStore(databasePath: path);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(await reopened.db.getVersion(), LocalStore.schemaVersion);
      expect(
        (await reopened.db.query('asset_definitions')).map((row) => row['id']),
        containsAll([defaultUsdAssetId, customId]),
      );
      expect(
        (await reopened.db.query('transactions')).single['asset_definition_id'],
        defaultUsdAssetId,
      );
      final staged = await reopened.db.query('initial_sync_staging');
      final definitionStage = staged.singleWhere(
        (row) => row['entity_type'] == 'asset_definitions',
      );
      expect(definitionStage['entity_id'], defaultUsdAssetId);
      expect(
        jsonDecode(definitionStage['payload_json']! as String)['id'],
        defaultUsdAssetId,
      );
      final transactionStage = staged.singleWhere(
        (row) => row['entity_type'] == 'transactions',
      );
      expect(
        jsonDecode(
          transactionStage['payload_json']! as String,
        )['asset_definition_id'],
        defaultUsdAssetId,
      );
    },
  );
}

Map<String, Object?> _definition(String id, String bookId, int now) => {
  'id': id,
  'book_id': bookId,
  'display_name': id,
  'asset_kind': 'foreignCurrency',
  'currency_code': 'IDR',
  'unit': 'usd',
  'created_at': now,
  'updated_at': now,
  'device_id': 'test-device',
};
