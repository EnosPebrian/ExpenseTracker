import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'latest schema repairs only uniquely matched legacy project references',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'project-id-v18-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'migration.db');
      final store = LocalStore(databasePath: path);
      await store.initialize();
      final db = store.db;
      const bookId = 'book-1';
      const projectId = '11111111-1111-4111-8111-111111111111';
      const transactionId = '22222222-2222-4222-8222-222222222222';
      final now = DateTime.utc(2026, 7, 29).millisecondsSinceEpoch;

      await db.insert(
        'projects',
        _project(projectId, bookId, 'BETA TEST Home', now),
      );
      await db.insert(
        'projects',
        _project('ambiguous-1', bookId, 'Same Project', now),
      );
      await db.insert(
        'projects',
        _project('ambiguous-2', bookId, ' Same   Project ', now),
      );
      await db.insert(
        'transactions',
        _transaction(transactionId, bookId, 'beta-test-home', now),
      );
      await db.insert(
        'transactions',
        _transaction('ambiguous-transaction', bookId, 'same-project', now),
      );
      await db.insert(
        'transactions',
        _transaction('unmatched-transaction', bookId, 'missing-project', now),
      );
      final payload = jsonEncode(
        _transaction(transactionId, bookId, 'beta-test-home', now),
      );
      await db.insert('sync_outbox', {
        'operation_id': 'operation-1',
        'book_id': bookId,
        'entity_type': 'transactions',
        'entity_id': transactionId,
        'operation_type': 'upsert',
        'base_version': 0,
        'payload_json': payload,
        'created_at': now,
        'updated_at': now,
        'status': 'pending',
      });
      await db.insert('initial_sync_staging', {
        'book_id': bookId,
        'direction': 'upload',
        'entity_type': 'transactions',
        'entity_id': transactionId,
        'payload_json': payload,
      });
      await db.insert('sync_conflicts', {
        'id': 'conflict-1',
        'book_id': bookId,
        'entity_type': 'transactions',
        'entity_id': transactionId,
        'operation_id': 'conflict-operation-1',
        'base_version': 1,
        'server_version': 2,
        'local_payload_json': payload,
        'server_payload_json': payload,
        'created_at': now,
      });
      await db.setVersion(17);
      await store.close();

      final reopened = LocalStore(databasePath: path);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(await reopened.db.getVersion(), 20);
      final transactions = await reopened.db.query('transactions');
      expect(
        transactions.singleWhere(
          (row) => row['id'] == transactionId,
        )['project_id'],
        projectId,
      );
      expect(
        transactions.singleWhere(
          (row) => row['id'] == 'ambiguous-transaction',
        )['project_id'],
        'same-project',
      );
      expect(
        transactions.singleWhere(
          (row) => row['id'] == 'unmatched-transaction',
        )['project_id'],
        'missing-project',
      );
      for (final encoded in [
        (await reopened.db.query('sync_outbox')).single['payload_json'],
        (await reopened.db.query(
          'initial_sync_staging',
        )).single['payload_json'],
        (await reopened.db.query(
          'sync_conflicts',
        )).single['local_payload_json'],
        (await reopened.db.query(
          'sync_conflicts',
        )).single['server_payload_json'],
      ]) {
        expect(jsonDecode(encoded! as String)['project_id'], projectId);
      }
    },
  );
}

Map<String, Object?> _project(String id, String bookId, String name, int now) =>
    {
      'id': id,
      'book_id': bookId,
      'name': name,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    };

Map<String, Object?> _transaction(
  String id,
  String bookId,
  String projectId,
  int now,
) => {
  'id': id,
  'book_id': bookId,
  'project_id': projectId,
  'title': 'Synthetic project expense',
  'category': 'Synthetic category',
  'account': 'Synthetic account',
  'transaction_date': now,
  'amount': 100,
  'transaction_type': 'expense',
  'created_at': now,
  'updated_at': now,
  'device_id': 'test-device',
};
