import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v13 to v14 migration preserves rows without historical enqueue',
    () async {
      final fixture = await _Fixture.create('migration');
      addTearDown(fixture.dispose);
      await _createV13Database(fixture.path);

      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);

      expect(await store.db.getVersion(), LocalStore.schemaVersion);
      expect((await store.db.query('transactions')).single['amount'], 125000);
      expect(await store.db.query('sync_outbox'), isEmpty);
      final cursor = (await store.db.query('sync_cursors')).single;
      expect(cursor['initialization_state'], 'primaryUploadRequired');
      expect(cursor['last_server_sequence'], 0);
    },
  );

  test('fresh schema creates sync tables and useful indexes', () async {
    final fixture = await _Fixture.create('fresh');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);

    for (final table in const [
      'sync_outbox',
      'sync_cursors',
      'sync_conflicts',
    ]) {
      expect(
        await store.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        ),
        isNotEmpty,
      );
    }
    final indexes = (await store.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_sync_%'",
    )).map((row) => row['name']);
    expect(indexes, contains('idx_sync_outbox_book_status_created'));
    expect(indexes, contains('idx_sync_outbox_entity'));
    expect(indexes, contains('idx_sync_outbox_next_attempt'));
  });

  test('linked transaction and outbox commit atomically', () async {
    final fixture = await _linkedFixture('atomic');
    addTearDown(fixture.dispose);
    final transaction = _transaction(fixture.book.id, id: 'transaction-a');

    await fixture.store.upsertTransaction(transaction.toRecord());

    expect(
      (await fixture.store.getTransactions()).single['id'],
      transaction.id,
    );
    final operation = (await fixture.store.db.query('sync_outbox')).single;
    expect(operation['entity_type'], 'transactions');
    expect(operation['entity_id'], transaction.id);
    expect(operation['base_version'], 0);
    expect(operation['status'], 'pending');
  });

  test('outbox failure rolls back the financial record', () async {
    final fixture = await _linkedFixture('rollback');
    addTearDown(fixture.dispose);
    await fixture.store.db.execute('''
      CREATE TRIGGER fail_sync_outbox BEFORE INSERT ON sync_outbox
      BEGIN SELECT RAISE(ABORT, 'forced outbox failure'); END
    ''');

    await expectLater(
      fixture.store.upsertTransaction(
        _transaction(fixture.book.id, id: 'rolled-back').toRecord(),
      ),
      throwsA(anything),
    );
    expect(await fixture.store.getTransactions(), isEmpty);
    expect(await fixture.store.db.query('sync_outbox'), isEmpty);
  });

  test('soft deletion enqueues a tombstone payload', () async {
    final fixture = await _linkedFixture('delete');
    addTearDown(fixture.dispose);
    final transaction = _transaction(fixture.book.id, id: 'deleted');
    await fixture.store.upsertTransaction(transaction.toRecord());
    await fixture.store.softDeleteTransaction(
      transaction.id,
      DateTime(2026, 7, 26).millisecondsSinceEpoch,
      version: 2,
    );

    final operations = await fixture.store.db.query(
      'sync_outbox',
      orderBy: 'created_at ASC',
    );
    expect(operations, hasLength(2));
    expect(operations.last['operation_type'], 'delete');
    expect(operations.last['payload_json'], contains('deleted_at'));
  });

  test(
    'linked asset fee change enqueues parent and child operations',
    () async {
      final fixture = await _linkedFixture('fee');
      addTearDown(fixture.dispose);
      final parent = _transaction(
        fixture.book.id,
        id: 'asset-parent',
        type: TransactionType.assetConversion,
      );
      final fee = _transaction(
        fixture.book.id,
        id: 'asset-fee',
      ).copyWith(relatedTransactionId: parent.id);

      await fixture.store.saveAssetFeeChange(
        parent: parent.toRecord(),
        linkedExpense: fee.toRecord(),
      );

      final operations = await fixture.store.db.query('sync_outbox');
      expect(operations, hasLength(2));
      expect(
        operations.map((row) => row['entity_id']),
        containsAll([parent.id, fee.id]),
      );
    },
  );

  test(
    'every supported linked entity mutation creates an outbox operation',
    () async {
      final fixture = await _linkedFixture('all-entities');
      addTearDown(fixture.dispose);
      final now = DateTime(2026, 7, 26).millisecondsSinceEpoch;

      await fixture.store.upsertFinancialBook({
        ...fixture.book.toRecord(),
        'name': 'Renamed household',
        'updated_at': now,
        'version': 2,
        'sync_status': 'pending',
      });
      await fixture.store.upsertHouseholdMember({
        'id': 'member-all',
        'book_id': fixture.book.id,
        'display_name': 'Member',
        'role': 'member',
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'test-device',
        'sync_status': 'pending',
      });
      await fixture.store.upsertAccount({
        'id': 'account-all',
        'book_id': fixture.book.id,
        'name': 'Account',
        'account_type': 'asset',
        'currency_code': 'IDR',
        'opening_balance': 0,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'test-device',
        'sync_status': 'pending',
      });
      await fixture.store.saveMasterName(
        'categories',
        'Food',
        categoryType: 'expense',
      );
      await fixture.store.saveMasterName('projects', 'Life');
      await fixture.store.upsertAssetDefinition({
        'id': 'asset-all',
        'book_id': fixture.book.id,
        'display_name': 'Gold',
        'asset_kind': 'gold',
        'symbol': 'XAU',
        'currency_code': 'IDR',
        'unit': 'gram',
        'lot_size': 1,
        'online_pricing_enabled': 0,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'test-device',
        'sync_status': 'pending',
      });
      await fixture.store.upsertTransaction(
        _transaction(fixture.book.id, id: 'transaction-all').toRecord(),
      );

      final entityTypes = (await fixture.store.db.query(
        'sync_outbox',
      )).map((row) => row['entity_type']).toSet();
      expect(
        entityTypes,
        containsAll(const {
          'books',
          'household_members',
          'accounts',
          'categories',
          'projects',
          'transactions',
          'asset_definitions',
        }),
      );
    },
  );

  test(
    'pending and conflict records survive reopen and sending recovers',
    () async {
      final fixture = await _linkedFixture('reopen');
      addTearDown(fixture.dispose);
      await fixture.store.upsertTransaction(
        _transaction(fixture.book.id, id: 'pending').toRecord(),
      );
      final operation = (await fixture.store.db.query('sync_outbox')).single;
      await fixture.store.markSyncOperationsSending([
        operation['operation_id'] as String,
      ]);
      await fixture.store.recordSyncConflict({
        'book_id': fixture.book.id,
        'entity_type': 'transactions',
        'entity_id': 'conflicted',
        'operation_id': 'conflict-operation',
        'base_version': 1,
        'server_version': 2,
      });
      final path = fixture.path;
      await fixture.store.close();

      final reopened = LocalStore(databasePath: path);
      await reopened.initialize();
      reopened.setActiveBookId(fixture.book.id);
      await reopened.recoverInterruptedSyncOperations(fixture.book.id);
      addTearDown(reopened.close);
      final restored = (await reopened.db.query('sync_outbox')).single;
      expect(restored['status'], 'retry');
      expect(await reopened.getUnresolvedSyncConflictCount(fixture.book.id), 1);
    },
  );

  test(
    'remote batch is atomic, does not enqueue, and advances cursor last',
    () async {
      final fixture = await _linkedFixture('remote');
      addTearDown(fixture.dispose);
      await fixture.store.setSyncInitializationState(fixture.book.id, 'ready');
      final valid = _transaction(fixture.book.id, id: 'remote-one').toRecord();

      await expectLater(
        fixture.store.applyRemoteSyncBatch(
          fixture.book.id,
          changes: [
            {
              'entity_type': 'transactions',
              'entity_id': 'remote-one',
              'payload': valid,
            },
            {
              'entity_type': 'transactions',
              'entity_id': 'wrong-id',
              'payload': _transaction(
                fixture.book.id,
                id: 'actual-id',
              ).toRecord(),
            },
          ],
          finalSequence: 8,
        ),
        throwsStateError,
      );
      expect(await fixture.store.getTransactions(), isEmpty);
      expect(
        (await fixture.store.getSyncCursor(
          fixture.book.id,
        ))!['last_server_sequence'],
        0,
      );

      await fixture.store.applyRemoteSyncBatch(
        fixture.book.id,
        changes: [
          {
            'entity_type': 'transactions',
            'entity_id': 'remote-one',
            'payload': valid,
          },
        ],
        finalSequence: 8,
      );
      await fixture.store.applyRemoteSyncBatch(
        fixture.book.id,
        changes: [
          {
            'entity_type': 'transactions',
            'entity_id': 'remote-one',
            'payload': valid,
          },
        ],
        finalSequence: 8,
      );
      expect(await fixture.store.getTransactions(), hasLength(1));
      expect(await fixture.store.db.query('sync_outbox'), isEmpty);
      expect(
        (await fixture.store.getSyncCursor(
          fixture.book.id,
        ))!['last_server_sequence'],
        8,
      );
    },
  );

  test('unlinked books remain local without outbox noise', () async {
    final fixture = await _Fixture.create('local-only');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    final book = FinancialBook(id: 'local-book', name: 'Local');
    await store.upsertFinancialBook(book.toRecord());
    store.setActiveBookId(book.id);
    await store.upsertTransaction(
      _transaction(book.id, id: 'local').toRecord(),
    );
    expect(await store.db.query('sync_outbox'), isEmpty);
  });

  test('web store mirrors outbox and remote apply behavior', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final store = web.LocalStore(databasePath: 'beta04a-$suffix');
    final book = FinancialBook(
      id: 'web-book-$suffix',
      name: 'Web',
      remoteLinkedAt: DateTime(2026, 7, 26),
    );
    await store.upsertFinancialBook(book.toRecord(), enqueueSync: false);
    store.setActiveBookId(book.id);
    await store.setSyncInitializationState(book.id, 'ready');
    await store.upsertTransaction(
      _transaction(book.id, id: 'web-local-$suffix').toRecord(),
    );
    expect(await store.getPendingSyncCount(book.id), 1);
    await store.applyRemoteSyncBatch(
      book.id,
      changes: [
        {
          'entity_type': 'transactions',
          'entity_id': 'web-remote-$suffix',
          'payload': _transaction(book.id, id: 'web-remote-$suffix').toRecord(),
        },
        {
          'entity_type': 'categories',
          'entity_id': 'web-category-$suffix',
          'payload': {
            'id': 'web-category-$suffix',
            'book_id': book.id,
            'name': 'Remote category',
            'category_type': 'expense',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
            'version': 1,
            'device_id': 'remote-device',
          },
        },
      ],
      finalSequence: 4,
    );
    expect(
      (await store.getTransactions()).where(
        (row) => row['id'] == 'web-remote-$suffix',
      ),
      hasLength(1),
    );
    expect(
      await store.getMasterNames('categories', categoryType: 'expense'),
      contains('Remote category'),
    );
    expect((await store.getSyncCursor(book.id))!['last_server_sequence'], 4);
  });
}

Transaction _transaction(
  String bookId, {
  required String id,
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: id,
  bookId: bookId,
  title: 'Test',
  category: 'Test',
  account: 'Cash',
  date: DateTime(2026, 7, 26),
  amount: 125000,
  type: type,
  syncStatus: 'pending',
);

Future<_LinkedFixture> _linkedFixture(String name) async {
  final fixture = await _Fixture.create(name);
  final store = LocalStore(databasePath: fixture.path);
  await store.initialize();
  final book = FinancialBook(
    id: 'book-$name',
    name: 'Linked',
    remoteLinkedAt: DateTime(2026, 7, 26),
  );
  await store.upsertFinancialBook(book.toRecord(), enqueueSync: false);
  store.setActiveBookId(book.id);
  await store.setSyncInitializationState(book.id, 'primaryUploadRequired');
  return _LinkedFixture(fixture.directory, fixture.path, store, book);
}

Future<void> _createV13Database(String path) async {
  final database = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 13,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY, name TEXT NOT NULL,
            base_currency_code TEXT NOT NULL DEFAULT 'IDR',
            remote_linked_at INTEGER, created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, deleted_at INTEGER,
            version INTEGER NOT NULL, device_id TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY, book_id TEXT, title TEXT NOT NULL,
            category TEXT NOT NULL, account TEXT NOT NULL,
            transaction_date INTEGER NOT NULL, amount INTEGER NOT NULL,
            transaction_type TEXT NOT NULL, created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, deleted_at INTEGER,
            version INTEGER NOT NULL, device_id TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
        await db.insert('books', {
          'id': 'linked-book',
          'name': 'Linked',
          'remote_linked_at': 1,
          'created_at': 1,
          'updated_at': 1,
          'version': 1,
          'device_id': 'device',
          'sync_status': 'synced',
        });
        await db.insert('transactions', {
          'id': 'historical',
          'book_id': 'linked-book',
          'title': 'Historical',
          'category': 'Food',
          'account': 'Cash',
          'transaction_date': 1,
          'amount': 125000,
          'transaction_type': 'expense',
          'created_at': 1,
          'updated_at': 1,
          'version': 1,
          'device_id': 'device',
          'sync_status': 'local_only',
        });
      },
    ),
  );
  await database.close();
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta04a-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _LinkedFixture extends _Fixture {
  const _LinkedFixture(super.directory, super.path, this.store, this.book);
  final LocalStore store;
  final FinancialBook book;

  @override
  Future<void> dispose() async {
    await store.close();
    await super.dispose();
  }
}
