import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('durable conflict is idempotent and resolves exactly once', () async {
    final directory = await Directory.systemTemp.createTemp('beta04c-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(databasePath: p.join(directory.path, 'test.db'));
    await store.initialize();
    addTearDown(store.close);
    final now = DateTime(2026, 7, 27).millisecondsSinceEpoch;
    final payload = _transaction(now);
    await store.db.insert('transactions', payload);
    await store.db.insert('sync_outbox', _outbox(now));
    final conflict = {..._conflict(payload), 'resolution_status': 'unresolved'};
    await store.recordSyncConflict(conflict);
    await store.recordSyncConflict(conflict);
    expect(await store.getUnresolvedSyncConflictCount('book'), 1);
    final saved = (await store.getSyncConflicts('book')).single;
    expect(saved['conflict_type'], 'openingBalanceConflict');
    expect(
      await store.beginSyncConflictResolution(
        saved['id'] as String,
        'resolution-1',
      ),
      isTrue,
    );
    expect(
      await store.beginSyncConflictResolution(
        saved['id'] as String,
        'resolution-2',
      ),
      isFalse,
    );
    await store.completeSyncConflictResolution(
      saved['id'] as String,
      resolution: 'keepServer',
      canonicalPayload: {...payload, 'title': 'Shared', 'version': 2},
      serverSequence: 7,
    );
    expect(await store.getUnresolvedSyncConflictCount('book'), 0);
    expect((await store.getTransactions()).single['title'], 'Shared');
    expect((await store.db.query('sync_outbox')).single['status'], 'completed');
  });

  test('web conflict store has equivalent resolution lifecycle', () async {
    final store = web.LocalStore();
    await store.initialize();
    final now = DateTime(2026, 7, 27).millisecondsSinceEpoch;
    final payload = _transaction(now);
    await store.recordSyncConflict({
      ..._conflict(payload),
      'resolution_status': 'unresolved',
    });
    final saved = (await store.getSyncConflicts('book')).single;
    expect(
      await store.beginSyncConflictResolution(
        saved['id'] as String,
        'resolution-web',
      ),
      isTrue,
    );
    await store.completeSyncConflictResolution(
      saved['id'] as String,
      resolution: 'keepServer',
      canonicalPayload: payload,
      serverSequence: 4,
    );
    expect(await store.getUnresolvedSyncConflictCount('book'), 0);
  });
}

Map<String, Object?> _conflict(Map<String, Object?> payload) => {
  'book_id': 'book',
  'entity_type': 'transactions',
  'entity_id': 'transaction',
  'operation_id': 'operation',
  'base_version': 1,
  'server_version': 2,
  'local_payload_json': jsonEncode(payload),
  'server_payload_json': jsonEncode(payload),
  'conflict_type': 'openingBalanceConflict',
  'changed_local_fields_json': '["amount"]',
  'changed_server_fields_json': '["amount"]',
};

Map<String, Object?> _outbox(int now) => {
  'operation_id': 'operation',
  'book_id': 'book',
  'entity_type': 'transactions',
  'entity_id': 'transaction',
  'operation_type': 'upsert',
  'base_version': 1,
  'payload_json': '{}',
  'created_at': now,
  'updated_at': now,
  'attempt_count': 0,
  'status': 'conflict',
};

Map<String, Object?> _transaction(int now) => {
  'id': 'transaction',
  'book_id': 'book',
  'title': 'Local',
  'category': 'Food',
  'account': 'Cash',
  'transaction_date': now,
  'amount': 100,
  'transaction_type': 'expense',
  'created_at': now,
  'updated_at': now,
  'version': 1,
  'device_id': 'device',
  'sync_status': 'conflict',
};
