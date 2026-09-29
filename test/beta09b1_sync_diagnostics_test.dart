import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pilgrim_tracker/features/sync/data/local_sync_repository.dart';
import 'beta09a_sync_convergence_test.dart' as fixture;

void main() {
  test(
    'web diagnostics preserve the same pending failed conflict states',
    () async {
      final store = web.LocalStore();
      await store.initialize();
      const book = 'grid-web';
      await store.upsertFinancialBook({
        'id': book,
        'name': 'Grid',
        'remote_linked_at': fixture.stamp,
      }, enqueueSync: false);
      await store.upsertTransaction({
        ...fixture.row('web-grid'),
        'book_id': book,
      });
      final operations = await store.getEligibleSyncOperations(book);
      final operation = operations.single;
      expect(
        (await store.getTransactionSyncDiagnostics(book)).single['status'],
        'pending',
      );
      await store.scheduleSyncRetry(
        operation['operation_id'] as String,
        errorCode: 'network',
        safeMessage: 'Retry',
        nextAttemptAt: DateTime.now().millisecondsSinceEpoch,
      );
      expect(
        (await store.getTransactionSyncDiagnostics(book)).single['status'],
        'retry',
      );
      await store.recordSyncConflict({
        'book_id': book,
        'entity_type': 'transactions',
        'entity_id': 'web-grid',
        'operation_id': operation['operation_id'],
        'base_version': 0,
        'server_version': 1,
        'local_payload_json': jsonEncode(fixture.row('web-grid')),
        'server_payload_json': jsonEncode(fixture.row('web-grid')),
        'resolution_status': 'unresolved',
      });
      expect(
        (await store.getTransactionSyncDiagnostics(
          book,
        )).single['has_conflict'],
        1,
      );
    },
  );
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
    'per-record diagnostics are read-only and distinguish pending failed conflict',
    () async {
      final store = await fixture.database();
      await fixture.save(store, fixture.row('pending'));
      await fixture.save(store, fixture.row('failed'));
      await store.db.update(
        'sync_outbox',
        {'status': 'retry'},
        where: 'entity_id = ?',
        whereArgs: ['failed'],
      );
      await fixture.conflict(store, fixture.Server());
      // The coordinator may have acknowledged unrelated records while resolving dependencies.
      await fixture.save(store, fixture.row('new-pending'));
      await store.db.update(
        'sync_outbox',
        {'status': 'retry'},
        where: 'entity_id = ?',
        whereArgs: ['failed'],
      );
      final before = await store.db.query('sync_outbox');
      final states = await LocalSyncRepository(
        store as dynamic,
      ).transactionSyncStates('book');
      expect(states['new-pending'], 'Pending');
      expect(states['failed'], 'Failed');
      expect(states['edit'], 'Conflict');
      expect(await store.db.query('sync_outbox'), before);
    },
  );
}
