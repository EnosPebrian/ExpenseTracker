// The analyzer resolves conditional stores to web while this suite deliberately
// exercises the native SQLite implementation. The native test compiler resolves
// both facades to the matching native types.
// ignore_for_file: argument_type_not_assignable

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';
import 'package:pilgrim_tracker/features/sync/data/initial_sync_store_native.dart';
import 'package:pilgrim_tracker/features/sync/data/local_initial_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/data/local_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/data/supabase_sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/domain/cloud_sync_state_classifier.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_coordinator.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_models.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/initial_sync_controller.dart';
import 'package:pilgrim_tracker/features/sync/presentation/widgets/initial_sync_section.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v14 to v15 migration preserves cursor and adds durable staging',
    () async {
      final fixture = await _Fixture.create('migration');
      addTearDown(fixture.dispose);
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      await store.db.execute('DROP TABLE initial_sync_staging');
      await store.db.execute('DROP TABLE sync_cursors');
      await store.db.execute('''
      CREATE TABLE sync_cursors (
        book_id TEXT PRIMARY KEY,
        last_server_sequence INTEGER NOT NULL DEFAULT 0,
        initialization_state TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      await store.db.insert('sync_cursors', {
        'book_id': 'linked-book',
        'last_server_sequence': 42,
        'initialization_state': 'primaryUploadRequired',
        'updated_at': 1,
      });
      await store.db.setVersion(14);
      await store.close();

      final reopened = LocalStore(databasePath: fixture.path);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(await reopened.db.getVersion(), LocalStore.schemaVersion);
      final cursor = (await reopened.db.query('sync_cursors')).single;
      expect(cursor['last_server_sequence'], 42);
      expect(cursor['uploaded_count'], 0);
      expect(
        await reopened.db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'initial_sync_staging'],
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'stable upload snapshot leaves post-boundary mutation pending',
    () async {
      final fixture = await _linkedFixture('snapshot');
      addTearDown(fixture.dispose);
      final adapter = InitialSyncStoreAdapter(fixture.store);
      final manifest = await adapter.captureUploadSnapshot(fixture.book.id);
      final capturedTransactions = manifest.counts['transactions'];

      await fixture.store.upsertTransaction(
        _transaction(fixture.book.id, 'after-snapshot').toRecord(),
      );
      for (final entityType in initialSyncEntityOrder) {
        while (true) {
          final rows = await adapter.readUploadRows(
            fixture.book.id,
            entityType,
          );
          if (rows.isEmpty) break;
          await adapter.markUploadRowsTransferred(
            fixture.book.id,
            entityType,
            rows.map((row) => row['id'] as String),
          );
        }
      }
      await adapter.completeUpload(fixture.book.id, 73);

      expect(capturedTransactions, 1);
      final pending = await fixture.store.db.query(
        'sync_outbox',
        where: 'entity_id = ?',
        whereArgs: ['after-snapshot'],
      );
      expect(pending.single['status'], 'pending');
      expect(
        (await fixture.store.getSyncCursor(
          fixture.book.id,
        ))!['initialization_state'],
        'ready',
      );
    },
  );

  test(
    'interrupted primary upload resumes with one remote row per ID',
    () async {
      final fixture = await _linkedFixture('resume-upload');
      addTearDown(fixture.dispose);
      final repository = _repository(fixture.store);
      final transport = _FakeInitialTransport(failFirstUploadBatch: true);
      final coordinator = InitialSyncCoordinator(
        repository: repository,
        transport: transport,
      );

      final first = await coordinator.upload(
        bookId: fixture.book.id,
        isOwner: true,
        ownerConfirmed: true,
      );
      expect(first.success, isFalse);
      expect(
        (await repository.getCursor(fixture.book.id))!.initializationState,
        SyncInitializationState.failed,
      );

      final second = await coordinator.upload(
        bookId: fixture.book.id,
        isOwner: true,
        ownerConfirmed: true,
      );
      expect(second.success, isTrue);
      expect(transport.beginUploadCalls, 1);
      expect(
        transport.uploadedKeys.length,
        transport.uploadAttempts.toSet().length,
      );
      expect(
        (await repository.getCursor(fixture.book.id))!.initializationState,
        SyncInitializationState.ready,
      );
    },
  );

  test(
    'primary upload denies non-owner and occupied remote household',
    () async {
      final fixture = await _linkedFixture('eligibility');
      addTearDown(fixture.dispose);
      final repository = _repository(fixture.store);
      final transport = _FakeInitialTransport();
      final coordinator = InitialSyncCoordinator(
        repository: repository,
        transport: transport,
      );
      expect(
        (await coordinator.upload(
          bookId: fixture.book.id,
          isOwner: false,
          ownerConfirmed: true,
        )).success,
        isFalse,
      );
      expect(transport.beginUploadCalls, 0);

      transport.remoteRecordCount = 1;
      expect(
        (await coordinator.upload(
          bookId: fixture.book.id,
          isOwner: true,
          ownerConfirmed: true,
        )).message,
        contains('already contains'),
      );
      expect(transport.beginUploadCalls, 0);
    },
  );

  test(
    'interrupted secondary download resumes without exposing partial data',
    () async {
      final fixture = await _localFixture('resume-download');
      addTearDown(fixture.dispose);
      final repository = _repository(fixture.store);
      const remoteBookId = 'remote-book';
      await repository.prepareSecondary(remoteBookId);
      final transport = _FakeInitialTransport(failFirstDownloadBatch: true);
      final coordinator = InitialSyncCoordinator(
        repository: repository,
        transport: transport,
      );

      final first = await coordinator.download(
        bookId: remoteBookId,
        authUserId: 'auth-user',
      );
      expect(first.success, isFalse);
      expect(
        (await repository.getCursor(remoteBookId))!.initializationState,
        SyncInitializationState.failed,
      );
      expect(
        (await fixture.store.getLocalSession())!['active_book_id'],
        fixture.book.id,
      );
      expect(
        (await fixture.store.getFinancialBooks()).where(
          (row) => row['id'] == remoteBookId,
        ),
        isEmpty,
      );

      final second = await coordinator.download(
        bookId: remoteBookId,
        authUserId: 'auth-user',
      );
      expect(second.success, isTrue);
      expect(transport.beginDownloadCalls, 1);
      expect(
        (await fixture.store.getLocalSession())!['active_book_id'],
        remoteBookId,
      );
      expect(await fixture.store.db.query('sync_outbox'), isEmpty);
    },
  );

  test(
    'secondary download refuses a populated target without deleting it',
    () async {
      final fixture = await _localFixture('populated-target');
      addTearDown(fixture.dispose);
      const remoteBookId = 'remote-populated';
      await fixture.store.upsertFinancialBook(
        FinancialBook(id: remoteBookId, name: 'Existing target').toRecord(),
      );
      await fixture.store.upsertTransaction(
        _transaction(remoteBookId, 'independent').toRecord(),
      );
      final repository = _repository(fixture.store);
      await repository.prepareSecondary(remoteBookId);
      final coordinator = InitialSyncCoordinator(
        repository: repository,
        transport: _FakeInitialTransport(),
      );

      final result = await coordinator.download(
        bookId: remoteBookId,
        authUserId: 'auth-user',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('cannot merge'));
      expect(
        await fixture.store.getTransactions(bookId: remoteBookId),
        hasLength(1),
      );
      expect(
        (await fixture.store.getLocalSession())!['active_book_id'],
        fixture.book.id,
      );
    },
  );

  test(
    'secondary activation preserves financial identity and prior book',
    () async {
      final fixture = await _localFixture('download');
      addTearDown(fixture.dispose);
      final adapter = InitialSyncStoreAdapter(fixture.store);
      final manifest = _downloadManifest('remote-book');
      await fixture.store.setSyncInitializationState(
        manifest.bookId,
        SyncInitializationState.secondaryDownloadRequired.name,
      );
      await adapter.startInitialization(
        bookId: manifest.bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'download-session',
        manifest: manifest,
      );
      final rows = _downloadRows(manifest.bookId);
      for (final entityType in initialSyncEntityOrder) {
        final typed = rows
            .where((row) => row['entity_type'] == entityType)
            .map((row) => row['payload'] as Map<String, Object?>)
            .toList();
        await adapter.stageDownloadBatch(
          manifest.bookId,
          InitialSyncBatch(
            entityType: entityType,
            rows: typed,
            nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
            complete: true,
          ),
        );
      }
      await adapter.activateDownload(
        bookId: manifest.bookId,
        manifest: manifest,
        authUserId: 'auth-user',
      );

      expect(
        await fixture.store.getTransactions(bookId: fixture.book.id),
        hasLength(1),
      );
      final downloaded = await fixture.store.getTransactions(
        bookId: manifest.bookId,
        includeDeleted: true,
      );
      expect(downloaded, hasLength(3));
      expect(
        downloaded.singleWhere((row) => row['id'] == 'fee')['fee_amount'],
        0,
      );
      expect(
        downloaded.singleWhere(
          (row) => row['id'] == 'fee',
        )['related_transaction_id'],
        'asset-parent',
      );
      expect(
        (await fixture.store.getAccounts(
          bookId: manifest.bookId,
        )).single['opening_balance'],
        250000,
      );
      expect(
        (await fixture.store.getHouseholdMembers(
          bookId: manifest.bookId,
        )).single['auth_user_id'],
        'auth-user',
      );
      expect(
        (await fixture.store.getLocalSession())!['active_book_id'],
        manifest.bookId,
      );
      expect(await fixture.store.db.query('sync_outbox'), isEmpty);
      expect(
        (await fixture.store.getSyncCursor(
          manifest.bookId,
        ))!['last_server_sequence'],
        1854,
      );
    },
  );

  test(
    'empty device imports a valid 22-record snapshot and exposes every entity',
    () async {
      final fixture = await _localFixture('download-22');
      addTearDown(fixture.dispose);
      final adapter = InitialSyncStoreAdapter(fixture.store);
      final manifest = _twentyTwoManifest('remote-22');
      await fixture.store.setSyncInitializationState(
        manifest.bookId,
        SyncInitializationState.secondaryDownloadRequired.name,
      );
      await adapter.startInitialization(
        bookId: manifest.bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'download-22-session',
        manifest: manifest,
      );
      final rows = _twentyTwoRows(manifest.bookId);
      for (final entityType in initialSyncEntityOrder) {
        final typed = rows
            .where((row) => row['entity_type'] == entityType)
            .map((row) => row['payload'] as Map<String, Object?>)
            .toList();
        await adapter.stageDownloadBatch(
          manifest.bookId,
          InitialSyncBatch(
            entityType: entityType,
            rows: typed,
            nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
            complete: true,
          ),
        );
      }

      var cursor = (await fixture.store.getSyncCursor(manifest.bookId))!;
      expect(cursor['downloaded_count'], 0);
      expect((await adapter.getDiagnosticSummary(manifest.bookId)).decoded, 22);

      await adapter.activateDownload(
        bookId: manifest.bookId,
        manifest: manifest,
        authUserId: 'auth-user',
      );

      cursor = (await fixture.store.getSyncCursor(manifest.bookId))!;
      expect(cursor['downloaded_count'], 22);
      expect(cursor['initialization_state'], 'ready');
      expect(cursor['last_error_message'], isNull);
      expect(await fixture.store.getHouseholdMembers(), hasLength(2));
      expect(await fixture.store.getAccounts(), hasLength(3));
      expect(await fixture.store.getMasterNames('categories'), hasLength(4));
      expect(await fixture.store.getProjectRecords(), hasLength(2));
      expect(await fixture.store.getAssetDefinitions(), hasLength(2));
      expect(await fixture.store.getTransactions(), hasLength(8));
      final diagnostic = await adapter.getDiagnosticSummary(manifest.bookId);
      expect(diagnostic.persisted, 22);
      expect(
        diagnostic.entities.values.fold<int>(
          0,
          (total, value) => total + value.locallyQueryable,
        ),
        22,
      );
    },
  );

  test(
    'new-device staging activates 5000 transactions without duplication',
    () async {
      final fixture = await _localFixture('download-5000');
      addTearDown(fixture.dispose);
      const bookId = 'remote-5000';
      final adapter = InitialSyncStoreAdapter(fixture.store);
      final now = DateTime(2026, 7, 26).millisecondsSinceEpoch;
      Map<String, Object?> syncedRecord(String id) => {
        'id': id,
        'book_id': bookId,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'remote',
        'sync_status': 'synced',
      };
      final categories = <Map<String, Object?>>[
        {
          ...syncedRecord('category'),
          'name': 'Food',
          'category_type': 'expense',
        },
        for (var index = 0; index < 200; index++)
          {
            ...syncedRecord('category-$index'),
            'name': 'Category $index',
            'category_type': 'expense',
          },
      ];
      final accounts = <Map<String, Object?>>[
        _accountRecord(bookId),
        {..._accountRecord(bookId), 'id': 'account-2', 'name': 'Cash'},
      ];
      final transactions = <Map<String, Object?>>[
        _transaction(
          bookId,
          'transfer-out',
        ).copyWith(account: 'Bank').toRecord(),
        _transaction(
          bookId,
          'transfer-in',
        ).copyWith(account: 'Cash', type: TransactionType.income).toRecord(),
        for (var index = 2; index < 5000; index++)
          _transaction(bookId, 'bulk-$index').toRecord(),
      ];
      final rowsByEntity = <String, List<Map<String, Object?>>>{
        'books': [_bookRecord(bookId, 'Large shared household')],
        'household_members': [
          {
            ...syncedRecord('remote-member'),
            'display_name': 'Grace',
            'role': 'member',
          },
        ],
        'categories': categories,
        'monthly_category_budgets': [
          for (var index = 0; index < 200; index++)
            {
              ...syncedRecord('budget-$index'),
              'category_id': 'category-$index',
              'month_start': '2026-07-01',
              'limit_minor': 100000 + index,
              'currency_code': 'IDR',
              'note': null,
            },
        ],
        'accounts': accounts,
        'transaction_import_rules': [
          for (var index = 0; index < 200; index++)
            {
              ...syncedRecord('rule-$index'),
              'name': 'Rule $index',
              'enabled': 1,
              'priority': index,
              'transaction_type': 'expense',
              'match_field': 'description',
              'match_operator': 'contains',
              'pattern': 'merchant $index',
              'pattern_key': 'merchant $index',
              'account_id': null,
              'category_id': 'category-$index',
            },
        ],
        'import_review_sessions': [
          {
            ...syncedRecord('session-1'),
            'source_type': 'csv',
            'title': 'Pending CSV',
            'source_fingerprint': 'source-fingerprint',
            'destination_account_id': 'account',
            'state': 'pendingReview',
            'created_by_member_id': 'remote-member',
            'summary_json': '{"row_count":10}',
            'completed_at': null,
          },
        ],
        'import_review_drafts': [
          for (var index = 0; index < 10; index++)
            {
              ...syncedRecord('draft-$index'),
              'session_id': 'session-1',
              'source_row_identity': 'source-row-$index',
              'source_row_key': '$index',
              'deterministic_transaction_id': null,
              'deterministic_transaction_account_id': null,
              'source_index': index,
              'transaction_date': now,
              'description': 'Draft $index',
              'amount_minor': 1000 + index,
              'currency_code': 'IDR',
              'transaction_type': 'expense',
              'category_name': '',
              'category_id': null,
              'category_provenance': 'unresolved',
              'reference_text': '',
              'note_text': '',
              'merchant_hint': '',
              'included': 1,
              'user_edited_fields_json': '[]',
              'warnings_json': '[]',
            },
        ],
        'transactions': transactions,
        'transfer_links': [
          {
            ...syncedRecord('transfer-link'),
            'outgoing_transaction_id': 'transfer-out',
            'incoming_transaction_id': 'transfer-in',
            'source_account_id': 'account',
            'destination_account_id': 'account-2',
            'currency_code': 'IDR',
            'amount': 100000,
          },
        ],
      };
      final manifest = InitialSyncManifest(
        bookId: bookId,
        bookName: 'Large shared household',
        baseCurrencyCode: 'IDR',
        counts: {
          for (final entityType in initialSyncEntityOrder)
            entityType: rowsByEntity[entityType]?.length ?? 0,
        },
        snapshotSequence: 5000,
        memberRole: 'member',
        householdMemberId: 'remote-member',
        remoteInitializationComplete: true,
        remoteRecordCount: rowsByEntity.values.fold(
          0,
          (total, rows) => total + rows.length,
        ),
      );
      await fixture.store.setSyncInitializationState(
        bookId,
        SyncInitializationState.secondaryDownloadRequired.name,
      );
      await adapter.startInitialization(
        bookId: bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'download-5000-session',
        manifest: manifest,
      );
      for (final entityType in initialSyncEntityOrder) {
        final entityRows =
            rowsByEntity[entityType] ?? const <Map<String, Object?>>[];
        if (entityRows.isEmpty) {
          await adapter.stageDownloadBatch(
            bookId,
            InitialSyncBatch(
              entityType: entityType,
              rows: const [],
              nextCursor: null,
              complete: true,
            ),
          );
          continue;
        }
        for (var offset = 0; offset < entityRows.length; offset += 100) {
          final rows = entityRows.skip(offset).take(100).toList();
          await adapter.stageDownloadBatch(
            bookId,
            InitialSyncBatch(
              entityType: entityType,
              rows: rows,
              nextCursor: rows.last['id'] as String,
              complete: offset + rows.length == entityRows.length,
            ),
          );
        }
      }

      await adapter.activateDownload(
        bookId: bookId,
        manifest: manifest,
        authUserId: 'auth-user',
      );

      expect(await fixture.store.getTransactions(), hasLength(5000));
      expect(await fixture.store.getMasterNames('categories'), hasLength(201));
      expect(await fixture.store.getMonthlyCategoryBudgets(), hasLength(200));
      expect(await fixture.store.getTransactionImportRules(), hasLength(200));
      expect(await fixture.store.getImportReviewSessions(), hasLength(1));
      expect(
        await fixture.store.getAllImportReviewDrafts(bookId: bookId),
        hasLength(10),
      );
      expect(await fixture.store.getTransferLinks(), hasLength(1));
      expect(await fixture.store.getPendingSyncCount(bookId), 0);
      expect(
        (await fixture.store.getSyncCursor(bookId))!['initialization_state'],
        SyncInitializationState.ready.name,
      );
    },
  );

  test(
    'resume keeps the last committed cursor and never double-counts staging',
    () async {
      final fixture = await _localFixture('idempotent-download');
      addTearDown(fixture.dispose);
      const bookId = 'remote-idempotent';
      final manifest = _twentyTwoManifest(bookId);
      final adapter = InitialSyncStoreAdapter(fixture.store);
      await fixture.store.setSyncInitializationState(
        bookId,
        SyncInitializationState.secondaryDownloadRequired.name,
      );
      await adapter.startInitialization(
        bookId: bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'resume-session',
        manifest: manifest,
      );
      final transactions = _twentyTwoRows(bookId)
          .where((row) => row['entity_type'] == 'transactions')
          .map((row) => row['payload'] as Map<String, Object?>)
          .toList();
      final lastId = transactions.last['id'] as String;
      await adapter.stageDownloadBatch(
        bookId,
        InitialSyncBatch(
          entityType: 'transactions',
          rows: transactions,
          nextCursor: lastId,
          complete: true,
        ),
      );
      await adapter.stageDownloadBatch(
        bookId,
        const InitialSyncBatch(
          entityType: 'transactions',
          rows: [],
          nextCursor: null,
          complete: true,
        ),
      );
      await adapter.stageDownloadBatch(
        bookId,
        InitialSyncBatch(
          entityType: 'transactions',
          rows: transactions,
          nextCursor: lastId,
          complete: true,
        ),
      );

      final cursor = (await fixture.store.getSyncCursor(bookId))!;
      expect(cursor['last_processed_cursor'], lastId);
      expect(cursor['downloaded_count'], 0);
      final diagnostic = await adapter.getDiagnosticSummary(bookId);
      expect(diagnostic.entities['transactions']!.decoded, 8);
      expect(diagnostic.entities['transactions']!.skipped, 8);
      expect(diagnostic.decoded, lessThanOrEqualTo(manifest.totalCount));
    },
  );

  test(
    'v18 to v19 migration preserves cursor rows and adds diagnostics',
    () async {
      final fixture = await _Fixture.create('migration-v19');
      addTearDown(fixture.dispose);
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      await store.db.insert('sync_cursors', {
        'book_id': 'existing-book',
        'last_server_sequence': 41,
        'initialization_state': 'failed',
        'initialization_direction': 'download',
        'downloaded_count': 7,
        'last_error_message': 'Existing safe error',
        'updated_at': 1,
      });
      await store.db.execute(
        'ALTER TABLE sync_cursors DROP COLUMN initial_sync_diagnostic_json',
      );
      await store.db.setVersion(18);
      await store.close();

      final reopened = LocalStore(databasePath: fixture.path);
      await reopened.initialize();
      addTearDown(reopened.close);
      final cursor = (await reopened.db.query(
        'sync_cursors',
        where: 'book_id = ?',
        whereArgs: ['existing-book'],
      )).single;
      expect(cursor['last_server_sequence'], 41);
      expect(cursor['downloaded_count'], 0);
      expect(cursor['last_error_message'], 'Existing safe error');
      expect(cursor['initial_sync_diagnostic_json'], isNull);
      expect(await reopened.db.getVersion(), LocalStore.schemaVersion);
    },
  );

  test(
    'app restart resumes durable staging from its committed cursor',
    () async {
      final fixture = await _Fixture.create('restart-download');
      addTearDown(fixture.dispose);
      const bookId = 'remote-restart';
      final manifest = _twentyTwoManifest(bookId);
      final firstStore = LocalStore(databasePath: fixture.path);
      await firstStore.initialize();
      await firstStore.setSyncInitializationState(
        bookId,
        SyncInitializationState.secondaryDownloadRequired.name,
      );
      final firstAdapter = InitialSyncStoreAdapter(firstStore);
      await firstAdapter.startInitialization(
        bookId: bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'restart-session',
        manifest: manifest,
      );
      final rows = _twentyTwoRows(bookId);
      for (final entityType in initialSyncEntityOrder.take(3)) {
        final typed = rows
            .where((row) => row['entity_type'] == entityType)
            .map((row) => row['payload'] as Map<String, Object?>)
            .toList();
        await firstAdapter.stageDownloadBatch(
          bookId,
          InitialSyncBatch(
            entityType: entityType,
            rows: typed,
            nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
            complete: true,
          ),
        );
      }
      await firstStore.close();

      final reopened = LocalStore(databasePath: fixture.path);
      await reopened.initialize();
      addTearDown(reopened.close);
      final resumedAdapter = InitialSyncStoreAdapter(reopened);
      expect((await resumedAdapter.getDiagnosticSummary(bookId)).decoded, 7);
      for (final entityType in initialSyncEntityOrder.skip(3)) {
        final typed = rows
            .where((row) => row['entity_type'] == entityType)
            .map((row) => row['payload'] as Map<String, Object?>)
            .toList();
        await resumedAdapter.stageDownloadBatch(
          bookId,
          InitialSyncBatch(
            entityType: entityType,
            rows: typed,
            nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
            complete: true,
          ),
        );
      }
      await resumedAdapter.activateDownload(
        bookId: bookId,
        manifest: manifest,
        authUserId: 'auth-user',
      );
      expect((await reopened.getTransactions()), hasLength(8));
      expect(
        (await reopened.getSyncCursor(bookId))!['initialization_state'],
        'ready',
      );
    },
  );

  test('failed batch does not advance checkpoint and reports record', () async {
    final fixture = await _localFixture('failed-batch');
    addTearDown(fixture.dispose);
    const bookId = 'remote-failed-batch';
    final adapter = InitialSyncStoreAdapter(fixture.store);
    final manifest = _twentyTwoManifest(bookId);
    await fixture.store.setSyncInitializationState(
      bookId,
      SyncInitializationState.secondaryDownloadRequired.name,
    );
    await adapter.startInitialization(
      bookId: bookId,
      direction: InitialSyncDirection.download,
      sessionId: 'failed-batch-session',
      manifest: manifest,
    );

    await expectLater(
      adapter.stageDownloadBatch(
        bookId,
        InitialSyncBatch(
          entityType: 'accounts',
          rows: [
            _accountRecord(bookId),
            {..._accountRecord('another-book'), 'id': 'wrong-account'},
          ],
          nextCursor: 'wrong-account',
          complete: true,
        ),
      ),
      throwsA(
        isA<InitialSyncException>()
            .having((error) => error.entityType, 'entity', 'accounts')
            .having((error) => error.recordId, 'record', 'wrong-account')
            .having((error) => error.phase, 'phase', 'validate'),
      ),
    );
    final cursor = (await fixture.store.getSyncCursor(bookId))!;
    expect(cursor['last_processed_cursor'], isNull);
    expect(cursor['downloaded_count'], 0);
    expect(
      await fixture.store.db.query(
        'initial_sync_staging',
        where: 'book_id = ?',
        whereArgs: [bookId],
      ),
      isEmpty,
    );
  });

  test(
    'late record rejection rolls back activation with precise diagnostic',
    () async {
      final fixture = await _localFixture('late-rejection');
      addTearDown(fixture.dispose);
      const bookId = 'remote-late-rejection';
      final manifest = _twentyTwoManifest(bookId);
      final adapter = InitialSyncStoreAdapter(fixture.store);
      await fixture.store.setSyncInitializationState(
        bookId,
        SyncInitializationState.secondaryDownloadRequired.name,
      );
      await adapter.startInitialization(
        bookId: bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'late-rejection-session',
        manifest: manifest,
      );
      final rows = _twentyTwoRows(bookId);
      final lastTransaction = rows.last['payload'] as Map<String, Object?>;
      lastTransaction['title'] = null;
      for (final entityType in initialSyncEntityOrder) {
        final typed = rows
            .where((row) => row['entity_type'] == entityType)
            .map((row) => row['payload'] as Map<String, Object?>)
            .toList();
        await adapter.stageDownloadBatch(
          bookId,
          InitialSyncBatch(
            entityType: entityType,
            rows: typed,
            nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
            complete: true,
          ),
        );
      }

      await expectLater(
        adapter.activateDownload(
          bookId: bookId,
          manifest: manifest,
          authUserId: 'auth-user',
        ),
        throwsA(
          isA<InitialSyncException>()
              .having((error) => error.entityType, 'entity', 'transactions')
              .having((error) => error.recordId, 'record', 'transaction-8')
              .having((error) => error.phase, 'phase', 'persist')
              .having((error) => error.committedRecords, 'persisted', 0),
        ),
      );
      expect(
        (await fixture.store.getFinancialBooks()).where(
          (book) => book['id'] == bookId,
        ),
        isEmpty,
      );
      expect(
        (await fixture.store.getSyncCursor(bookId))!['downloaded_count'],
        0,
      );
    },
  );

  test('cloud payload mapper excludes provider-only fields', () {
    final mapped = SupabaseSyncTransport.toLocalPayload('accounts', {
      ..._accountRecord('book'),
      'server_sequence': 99,
      'private_note': 'must not enter SQLite',
    });
    expect(mapped, isNot(contains('server_sequence')));
    expect(mapped, isNot(contains('private_note')));
    expect(mapped['sync_status'], 'synced');

    final book = SupabaseSyncTransport.toLocalPayload('books', {
      'id': 'book',
      'name': 'Shared household',
      'base_currency_code': 'IDR',
      'created_by_user_id': 'cloud-user',
      'created_at': '2026-07-29T00:00:00.000Z',
      'updated_at': '2026-07-29T00:00:00.000Z',
      'deleted_at': null,
      'version': 1,
      'device_id': 'primary-device',
      'server_sequence': 22,
      'remote_updated_at': '2026-07-29T00:00:00.000Z',
    });
    expect(book, isNot(contains('created_by_user_id')));
    expect(book, isNot(contains('server_sequence')));
    expect(book, isNot(contains('remote_updated_at')));
  });

  test('activation strips provider columns from a staged cloud row', () async {
    final fixture = await _localFixture('provider-columns');
    addTearDown(fixture.dispose);
    final adapter = InitialSyncStoreAdapter(fixture.store);
    final manifest = _downloadManifest('remote-provider-columns');
    await fixture.store.setSyncInitializationState(
      manifest.bookId,
      SyncInitializationState.secondaryDownloadRequired.name,
    );
    await adapter.startInitialization(
      bookId: manifest.bookId,
      direction: InitialSyncDirection.download,
      sessionId: 'provider-columns-session',
      manifest: manifest,
    );
    final rows = _downloadRows(manifest.bookId);
    for (final entityType in initialSyncEntityOrder) {
      final typed = rows.where((row) => row['entity_type'] == entityType).map((
        row,
      ) {
        final payload = Map<String, Object?>.from(
          row['payload'] as Map<String, Object?>,
        );
        payload['created_by_user_id'] = 'cloud-provider-user';
        payload['server_sequence'] = 22;
        payload['remote_updated_at'] = '2026-07-29T00:00:00.000Z';
        return payload;
      }).toList();
      await adapter.stageDownloadBatch(
        manifest.bookId,
        InitialSyncBatch(
          entityType: entityType,
          rows: typed,
          nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
          complete: true,
        ),
      );
    }

    await adapter.activateDownload(
      bookId: manifest.bookId,
      manifest: manifest,
      authUserId: 'auth-user',
    );

    final book = (await fixture.store.db.query(
      'books',
      where: 'id = ?',
      whereArgs: [manifest.bookId],
    )).single;
    expect(book['name'], manifest.bookName);
    expect(book, isNot(contains('created_by_user_id')));
    expect(
      (await fixture.store.getSyncCursor(
        manifest.bookId,
      ))!['initialization_state'],
      SyncInitializationState.ready.name,
    );
  });

  test('repeated download taps share one active coordinator job', () async {
    final fixture = await _localFixture('concurrent-download');
    addTearDown(fixture.dispose);
    const bookId = 'remote-concurrent';
    final repository = _repository(fixture.store);
    await repository.prepareSecondary(bookId);
    final transport = _BlockingInitialTransport();
    final coordinator = InitialSyncCoordinator(
      repository: repository,
      transport: transport,
    );

    final first = coordinator.download(bookId: bookId, authUserId: 'auth');
    final second = coordinator.download(bookId: bookId, authUserId: 'auth');
    transport.release.complete();
    final results = await Future.wait([first, second]);
    expect(results.every((result) => result.success), isTrue);
    expect(transport.beginDownloadCalls, 1);
  });

  test('download integrity failure leaves active book unchanged', () async {
    final fixture = await _localFixture('integrity');
    addTearDown(fixture.dispose);
    final adapter = InitialSyncStoreAdapter(fixture.store);
    final manifest = InitialSyncManifest(
      bookId: 'remote-invalid',
      bookName: 'Invalid',
      baseCurrencyCode: 'IDR',
      counts: const {
        'books': 1,
        'household_members': 0,
        'categories': 0,
        'projects': 0,
        'accounts': 1,
        'asset_definitions': 0,
        'transactions': 0,
      },
      snapshotSequence: 9,
      remoteInitializationComplete: true,
    );
    await fixture.store.setSyncInitializationState(
      manifest.bookId,
      SyncInitializationState.secondaryDownloadRequired.name,
    );
    await adapter.startInitialization(
      bookId: manifest.bookId,
      direction: InitialSyncDirection.download,
      sessionId: 'invalid-session',
      manifest: manifest,
    );
    await adapter.stageDownloadBatch(
      manifest.bookId,
      InitialSyncBatch(
        entityType: 'books',
        rows: [_bookRecord(manifest.bookId, 'Invalid')],
        nextCursor: manifest.bookId,
        complete: true,
      ),
    );
    await adapter.stageDownloadBatch(
      manifest.bookId,
      InitialSyncBatch(
        entityType: 'accounts',
        rows: [_accountRecord(manifest.bookId, ownerId: 'missing-member')],
        nextCursor: 'account',
        complete: true,
      ),
    );
    await expectLater(
      adapter.activateDownload(
        bookId: manifest.bookId,
        manifest: manifest,
        authUserId: 'auth-user',
      ),
      throwsA(isA<InitialSyncException>()),
    );
    expect(
      (await fixture.store.getLocalSession())!['active_book_id'],
      fixture.book.id,
    );
    expect(
      (await fixture.store.getFinancialBooks()).where(
        (row) => row['id'] == manifest.bookId,
      ),
      isEmpty,
    );
  });

  test(
    'same-ID reconnect replaces local data and restores a ready cursor',
    () async {
      final fixture = await _localFixture('same-id-reconnect');
      addTearDown(fixture.dispose);
      final bookId = fixture.book.id;
      final repository = _repository(fixture.store);
      final transport = _FakeInitialTransport()..downloadBookId = bookId;
      final coordinator = InitialSyncCoordinator(
        repository: repository,
        transport: transport,
      );
      await coordinator.prepareReconnect(bookId);

      final result = await coordinator.download(
        bookId: bookId,
        authUserId: 'auth-grace',
        replaceExisting: true,
      );

      expect(result.success, isTrue);
      final transactions = await fixture.store.db.query(
        'transactions',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      expect(
        transactions.map((row) => row['id']),
        containsAll(['asset-parent', 'fee', 'deleted']),
      );
      expect(
        transactions.map((row) => row['id']),
        isNot(contains('local-record')),
      );
      expect(await fixture.store.getPendingSyncCount(bookId), 0);
      final cursor = await fixture.store.getSyncCursor(bookId);
      expect(
        cursor?['initialization_state'],
        SyncInitializationState.ready.name,
      );
      expect(cursor?['last_server_sequence'], 1854);
      final restoredBook = (await fixture.store.getFinancialBooks())
          .singleWhere((row) => row['id'] == bookId);
      expect(restoredBook['remote_linked_at'], isNotNull);
      final mapped = (await fixture.store.getHouseholdMembers(
        bookId: bookId,
      )).singleWhere((row) => row['id'] == 'remote-member');
      expect(mapped['auth_user_id'], 'auth-grace');
    },
  );

  test('failed same-ID activation keeps original financial rows', () async {
    final fixture = await _localFixture('same-id-invalid');
    addTearDown(fixture.dispose);
    final bookId = fixture.book.id;
    final adapter = InitialSyncStoreAdapter(fixture.store);
    final manifest = _downloadManifest(bookId);
    await fixture.store.setSyncInitializationState(
      bookId,
      SyncInitializationState.secondaryDownloadRequired.name,
    );
    await adapter.startInitialization(
      bookId: bookId,
      direction: InitialSyncDirection.download,
      sessionId: 'invalid-reconnect',
      manifest: manifest,
    );
    final rows = _downloadRows(bookId);
    (rows.last['payload'] as Map<String, Object?>)['entered_by_member_id'] =
        'foreign-member';
    for (final entityType in initialSyncEntityOrder) {
      final typed = rows
          .where((row) => row['entity_type'] == entityType)
          .map((row) => row['payload'] as Map<String, Object?>)
          .toList();
      await adapter.stageDownloadBatch(
        bookId,
        InitialSyncBatch(
          entityType: entityType,
          rows: typed,
          nextCursor: typed.isEmpty ? null : typed.last['id'] as String,
          complete: true,
        ),
      );
    }

    await expectLater(
      adapter.activateDownload(
        bookId: bookId,
        manifest: manifest,
        authUserId: 'auth-grace',
        replaceExisting: true,
      ),
      throwsA(isA<InitialSyncException>()),
    );
    final transactions = await fixture.store.db.query(
      'transactions',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    expect(transactions.map((row) => row['id']), contains('local-record'));
  });

  test(
    'exact hosted snapshot reattaches without rewriting financial rows',
    () async {
      final fixture = await _localFixture('exact-reconnect');
      addTearDown(fixture.dispose);
      final bookId = fixture.book.id;
      final repository = _repository(fixture.store);
      final coordinator = InitialSyncCoordinator(
        repository: repository,
        transport: _FakeInitialTransport()..downloadBookId = bookId,
      );
      await repository.prepareSecondary(bookId);
      expect(
        (await coordinator.download(
          bookId: bookId,
          authUserId: 'auth-grace',
          replaceExisting: true,
        )).success,
        isTrue,
      );
      final before = await fixture.store.db.query(
        'transactions',
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'id',
      );
      await fixture.store.db.update(
        'books',
        {'remote_linked_at': null},
        where: 'id = ?',
        whereArgs: [bookId],
      );
      await coordinator.prepareReconnect(bookId);

      final result = await coordinator.download(
        bookId: bookId,
        authUserId: 'auth-grace',
        replaceExisting: true,
      );

      expect(result.success, isTrue);
      expect(result.message, contains('already matched'));
      expect(
        await fixture.store.db.query(
          'transactions',
          where: 'book_id = ?',
          whereArgs: [bookId],
          orderBy: 'id',
        ),
        before,
      );
      expect(await fixture.store.getPendingSyncCount(bookId), 0);
    },
  );

  testWidgets(
    'initial-sync UI requires upload confirmation and warns against merge',
    (tester) async {
      final book = FinancialBook(
        id: 'book-widget',
        name: 'Household',
        remoteLinkedAt: DateTime(2026, 7, 26),
      );
      final transport = _FakeInitialTransport();
      final controller =
          InitialSyncController(
              coordinator: InitialSyncCoordinator(
                repository: _NoopInitialSyncRepository(),
                transport: transport,
              ),
            )
            ..primaryBook = book
            ..primaryIsOwner = true
            ..primaryCursor = SyncCursor(
              bookId: book.id,
              lastServerSequence: 0,
              initializationState:
                  SyncInitializationState.primaryUploadRequired,
              updatedAt: DateTime(2026, 7, 26),
            )
            ..primaryRemoteManifest = transport.remoteManifest(book.id)
            ..decision = CloudSyncDecision(
              CloudSyncClassification.genuinePrimaryUploadRequired,
              reason: 'widget-test',
              targetBookId: book.id,
            )
            ..secondaryBookId = 'remote-secondary'
            ..secondaryRole = 'member'
            ..secondaryRemoteManifest = _downloadManifest('remote-secondary');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InitialSyncSection(controller: controller),
            ),
          ),
        ),
      );

      final upload = tester.widget<FilledButton>(
        find.byKey(const Key('initial-upload-button')),
      );
      expect(upload.onPressed, isNull);
      await tester.tap(find.byKey(const Key('initial-upload-confirmation')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('initial-upload-button')),
            )
            .onPressed,
        isNotNull,
      );
      controller.decision = const CloudSyncDecision(
        CloudSyncClassification.downloadAdditionalHostedHousehold,
        reason: 'widget-test-secondary',
        targetBookId: 'remote-secondary',
      );
      controller.notifyListeners();
      await tester.pump();
      expect(
        find.byKey(const Key('initial-download-non-merge-warning')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('new device explicitly selects among hosted households', (
    tester,
  ) async {
    InitialSyncManifest manifest(String id, String name) => InitialSyncManifest(
      bookId: id,
      bookName: name,
      baseCurrencyCode: 'IDR',
      counts: const {'transactions': 2},
      snapshotSequence: 2,
      memberRole: 'member',
      remoteInitializationComplete: true,
      remoteRecordCount: 2,
    );

    final controller =
        InitialSyncController(
            coordinator: InitialSyncCoordinator(
              repository: _NoopInitialSyncRepository(),
              transport: _FakeInitialTransport(),
            ),
          )
          ..primaryBook = FinancialBook(id: 'local', name: 'Local')
          ..authUserId = 'auth-user'
          ..remoteStateLoaded = true
          ..hostedBookIds = const ['hosted-a', 'hosted-b']
          ..hostedRoles = const {'hosted-a': 'owner', 'hosted-b': 'member'}
          ..secondaryBookId = 'hosted-a'
          ..secondaryRole = 'owner'
          ..secondaryRemoteManifest = manifest('hosted-a', 'Family A')
          ..hostedManifests.addAll({
            'hosted-a': manifest('hosted-a', 'Family A'),
            'hosted-b': manifest('hosted-b', 'Family B'),
          })
          ..decision = const CloudSyncDecision(
            CloudSyncClassification.downloadAdditionalHostedHousehold,
            reason: 'new-device-selection',
            targetBookId: 'hosted-a',
          );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InitialSyncSection(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('Choose a household'), findsOneWidget);
    expect(find.text('Family A'), findsWidgets);
    expect(find.text('Family B'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('initial-download-household-hosted-b')),
    );
    await tester.pumpAndSettle();

    expect(controller.secondaryBookId, 'hosted-b');
    expect(controller.secondaryRole, 'member');
    expect(controller.decision.targetBookId, 'hosted-b');
    expect(controller.canDownload, isTrue);
  });
}

class _NoopInitialSyncRepository implements InitialSyncRepository {
  @override
  Future<SyncCursor?> getCursor(String bookId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalInitialSyncRepository _repository(LocalStore store) =>
    LocalInitialSyncRepository(
      syncRepository: LocalSyncRepository(store),
      store: InitialSyncStoreAdapter(store),
    );

Future<_StoreFixture> _linkedFixture(String name) async {
  final fixture = await _Fixture.create(name);
  final store = LocalStore(databasePath: fixture.path);
  await store.initialize();
  final book = FinancialBook(
    id: 'book-$name',
    name: 'Household',
    remoteLinkedAt: DateTime(2026, 7, 26),
  );
  await store.upsertFinancialBook(book.toRecord(), enqueueSync: false);
  store.setActiveBookId(book.id);
  await store.setSyncInitializationState(
    book.id,
    SyncInitializationState.primaryUploadRequired.name,
  );
  await store.upsertHouseholdMember(
    HouseholdMember(
      id: 'member-$name',
      bookId: book.id,
      displayName: 'Owner',
      role: HouseholdMemberRole.owner,
    ).toRecord(),
  );
  await store.upsertTransaction(_transaction(book.id, 'initial').toRecord());
  return _StoreFixture(fixture.directory, fixture.path, store, book);
}

Future<_StoreFixture> _localFixture(String name) async {
  final fixture = await _Fixture.create(name);
  final store = LocalStore(databasePath: fixture.path);
  await store.initialize();
  final now = DateTime(2026, 7, 26).millisecondsSinceEpoch;
  await store.upsertLocalProfile({
    'id': 'profile-$name',
    'display_name': 'Local',
    'default_currency_code': 'IDR',
    'created_at': now,
    'updated_at': now,
  });
  final book = FinancialBook(id: 'local-$name', name: 'Local household');
  await store.upsertFinancialBook(book.toRecord());
  store.setActiveBookId(book.id);
  await store.saveLocalSession(
    activeProfileId: 'profile-$name',
    onboardingCompleted: true,
    activeBookId: book.id,
    activeMemberId: null,
  );
  await store.upsertTransaction(
    _transaction(book.id, 'local-record').toRecord(),
  );
  return _StoreFixture(fixture.directory, fixture.path, store, book);
}

Transaction _transaction(String bookId, String id) => Transaction(
  id: id,
  bookId: bookId,
  title: id,
  category: 'Food',
  account: 'Cash',
  date: DateTime(2026, 7, 26),
  amount: 100000,
  type: TransactionType.expense,
);

InitialSyncManifest _downloadManifest(String bookId) => InitialSyncManifest(
  bookId: bookId,
  bookName: 'Shared household',
  baseCurrencyCode: 'IDR',
  counts: const {
    'books': 1,
    'household_members': 1,
    'categories': 1,
    'projects': 1,
    'accounts': 1,
    'asset_definitions': 1,
    'transactions': 3,
  },
  snapshotSequence: 1854,
  memberRole: 'member',
  householdMemberId: 'remote-member',
  remoteInitializationComplete: true,
  remoteRecordCount: 8,
);

List<Map<String, Object?>> _downloadRows(String bookId) {
  final now = DateTime(2026, 7, 26).millisecondsSinceEpoch;
  final parent = Transaction(
    id: 'asset-parent',
    bookId: bookId,
    enteredByMemberId: 'remote-member',
    projectId: 'project',
    title: 'Gold purchase',
    category: 'Asset conversion',
    account: 'Bank',
    date: DateTime(2026, 7, 20),
    amount: 1000000,
    type: TransactionType.assetConversion,
    quantity: 1,
    unit: 'gram',
    unitPrice: 1000000,
    assetDefinitionId: 'asset',
    assetName: 'Gold',
    assetSymbol: 'XAU',
    assetAction: AssetAction.buy,
  );
  final fee = _transaction(bookId, 'fee').copyWith(
    relatedTransactionId: parent.id,
    relationType: TransactionRelationType.assetFeeExpense,
  );
  final deleted = _transaction(
    bookId,
    'deleted',
  ).copyWith(deletedAt: DateTime(2026, 7, 25));
  return [
    {
      'entity_type': 'books',
      'payload': _bookRecord(bookId, 'Shared household'),
    },
    {
      'entity_type': 'household_members',
      'payload': {
        'id': 'remote-member',
        'book_id': bookId,
        'display_name': 'Grace',
        'role': 'member',
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'remote',
        'sync_status': 'synced',
      },
    },
    {
      'entity_type': 'categories',
      'payload': {
        'id': 'category',
        'book_id': bookId,
        'name': 'Food',
        'category_type': 'expense',
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'remote',
        'sync_status': 'synced',
      },
    },
    {
      'entity_type': 'projects',
      'payload': {
        'id': 'project',
        'book_id': bookId,
        'name': 'Life',
        'status': 'active',
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'remote',
        'sync_status': 'synced',
      },
    },
    {'entity_type': 'accounts', 'payload': _accountRecord(bookId)},
    {
      'entity_type': 'asset_definitions',
      'payload': {
        'id': 'asset',
        'book_id': bookId,
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
        'device_id': 'remote',
        'sync_status': 'synced',
      },
    },
    for (final transaction in [parent, fee, deleted])
      {'entity_type': 'transactions', 'payload': transaction.toRecord()},
  ];
}

InitialSyncManifest _twentyTwoManifest(String bookId) => InitialSyncManifest(
  bookId: bookId,
  bookName: 'Synthetic 22 household',
  baseCurrencyCode: 'IDR',
  counts: const {
    'books': 1,
    'household_members': 2,
    'categories': 4,
    'monthly_category_budgets': 0,
    'projects': 2,
    'accounts': 3,
    'asset_definitions': 2,
    'transactions': 8,
  },
  snapshotSequence: 2200,
  memberRole: 'member',
  householdMemberId: 'member-2',
  remoteInitializationComplete: true,
  remoteRecordCount: 21,
);

List<Map<String, Object?>> _twentyTwoRows(String bookId) {
  final now = DateTime(2026, 7, 29).millisecondsSinceEpoch;
  Map<String, Object?> canonical(String id) => {
    'id': id,
    'book_id': bookId,
    'created_at': now,
    'updated_at': now,
    'version': 1,
    'device_id': 'synthetic-device',
    'sync_status': 'synced',
  };

  final rows = <Map<String, Object?>>[
    {
      'entity_type': 'books',
      'payload': _bookRecord(bookId, 'Synthetic 22 household'),
    },
    for (final member in const [
      ('member-1', 'Owner', 'owner'),
      ('member-2', 'Member', 'member'),
    ])
      {
        'entity_type': 'household_members',
        'payload': {
          ...canonical(member.$1),
          'display_name': member.$2,
          'role': member.$3,
        },
      },
    for (var index = 1; index <= 4; index++)
      {
        'entity_type': 'categories',
        'payload': {
          ...canonical('category-$index'),
          'name': 'Category $index',
          'category_type': index == 4 ? 'income' : 'expense',
        },
      },
    for (var index = 1; index <= 2; index++)
      {
        'entity_type': 'projects',
        'payload': {
          ...canonical('project-$index'),
          'name': 'Project $index',
          'status': 'active',
        },
      },
    for (var index = 1; index <= 3; index++)
      {
        'entity_type': 'accounts',
        'payload': {
          ...canonical('account-$index'),
          'owner_member_id': index == 3 ? 'member-2' : 'member-1',
          'name': 'Account $index',
          'account_type': index == 3 ? 'cash' : 'bank',
          'currency_code': 'IDR',
          'opening_balance': index * 100000,
          'opening_balance_date': now,
        },
      },
    for (var index = 1; index <= 2; index++)
      {
        'entity_type': 'asset_definitions',
        'payload': {
          ...canonical('asset-$index'),
          'display_name': 'Asset $index',
          'asset_kind': index == 1 ? 'gold' : 'crypto',
          'symbol': index == 1 ? 'XAU' : 'BTC',
          'currency_code': 'IDR',
          'unit': index == 1 ? 'gram' : 'btc',
          'lot_size': 1,
          'online_pricing_enabled': 0,
        },
      },
  ];
  for (var index = 1; index <= 8; index++) {
    rows.add({
      'entity_type': 'transactions',
      'payload': Transaction(
        id: 'transaction-$index',
        bookId: bookId,
        enteredByMemberId: index.isEven ? 'member-2' : 'member-1',
        projectId: index <= 4 ? 'project-1' : 'project-2',
        title: 'Transaction $index',
        category: index == 8 ? 'Category 4' : 'Category 1',
        account: 'Account 1',
        date: DateTime(2026, 7, index),
        amount: index * 10000,
        type: index == 8 ? TransactionType.income : TransactionType.expense,
      ).toRecord(),
    });
  }
  return rows;
}

Map<String, Object?> _bookRecord(String id, String name) {
  final now = DateTime(2026, 7, 26).millisecondsSinceEpoch;
  return {
    'id': id,
    'name': name,
    'base_currency_code': 'IDR',
    'created_at': now,
    'updated_at': now,
    'version': 1,
    'device_id': 'remote',
    'sync_status': 'synced',
  };
}

Map<String, Object?> _accountRecord(
  String bookId, {
  String? ownerId = 'remote-member',
}) {
  final now = DateTime(2026, 7, 26).millisecondsSinceEpoch;
  return {
    'id': 'account',
    'book_id': bookId,
    'owner_member_id': ownerId,
    'name': 'Bank',
    'account_type': 'asset',
    'currency_code': 'IDR',
    'opening_balance': 250000,
    'opening_balance_date': now,
    'created_at': now,
    'updated_at': now,
    'version': 1,
    'device_id': 'remote',
    'sync_status': 'synced',
  };
}

class _FakeInitialTransport implements InitialSyncTransport {
  _FakeInitialTransport({
    this.failFirstUploadBatch = false,
    this.failFirstDownloadBatch = false,
  });

  final bool failFirstUploadBatch;
  final bool failFirstDownloadBatch;
  int remoteRecordCount = 0;
  int beginUploadCalls = 0;
  int beginDownloadCalls = 0;
  bool failedOnce = false;
  bool failedDownloadOnce = false;
  String downloadBookId = 'remote-book';
  final Map<String, List<Map<String, Object?>>> _downloadRowsByBook = {};
  final uploadedKeys = <String>{};
  final uploadAttempts = <String>[];

  InitialSyncManifest remoteManifest(String bookId) => InitialSyncManifest(
    bookId: bookId,
    bookName: 'Household',
    baseCurrencyCode: 'IDR',
    counts: const {},
    snapshotSequence: 0,
    memberRole: 'owner',
    remoteRecordCount: remoteRecordCount,
  );

  @override
  bool get isConfigured => true;
  @override
  bool get isAuthenticated => true;
  @override
  Future<InitialSyncManifest> inspect(String bookId) async =>
      remoteManifest(bookId);
  @override
  Future<InitialSyncSession> beginUpload(InitialSyncManifest manifest) async {
    beginUploadCalls++;
    return InitialSyncSession(
      id: 'upload-session',
      manifest: manifest,
      direction: InitialSyncDirection.upload,
    );
  }

  @override
  Future<int> uploadBatch({
    required String sessionId,
    required String entityType,
    required List<Map<String, Object?>> rows,
  }) async {
    for (final row in rows) {
      uploadAttempts.add('$entityType:${row['id']}');
    }
    if (failFirstUploadBatch && !failedOnce) {
      failedOnce = true;
      throw const InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'Temporary failure.',
      );
    }
    for (final row in rows) {
      uploadedKeys.add('$entityType:${row['id']}');
    }
    return uploadedKeys.where((key) => key.startsWith('$entityType:')).length;
  }

  @override
  Future<int> completeUpload(String sessionId) async => 77;
  @override
  Future<InitialSyncSession> beginDownload(String bookId) async {
    beginDownloadCalls++;
    downloadBookId = bookId;
    return InitialSyncSession(
      id: 'download-session',
      manifest: _downloadManifest(bookId),
      direction: InitialSyncDirection.download,
    );
  }

  @override
  Future<InitialSyncBatch> downloadBatch({
    required String sessionId,
    required String entityType,
    String? afterEntityId,
    int limit = 100,
  }) async {
    if (failFirstDownloadBatch &&
        !failedDownloadOnce &&
        entityType == 'categories') {
      failedDownloadOnce = true;
      throw const InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'Temporary download failure.',
      );
    }
    final rows = _downloadRowsByBook
        .putIfAbsent(downloadBookId, () => _downloadRows(downloadBookId))
        .where((row) => row['entity_type'] == entityType)
        .map((row) => row['payload'] as Map<String, Object?>)
        .toList();
    final page = afterEntityId == null ? rows : const <Map<String, Object?>>[];
    return InitialSyncBatch(
      entityType: entityType,
      rows: page,
      nextCursor: page.isEmpty ? null : page.last['id'] as String,
      complete: true,
    );
  }

  @override
  Future<void> cancel(String sessionId) async {}
}

class _BlockingInitialTransport implements InitialSyncTransport {
  final release = Completer<void>();
  int beginDownloadCalls = 0;

  @override
  bool get isConfigured => true;
  @override
  bool get isAuthenticated => true;
  @override
  Future<InitialSyncManifest> inspect(String bookId) async =>
      _twentyTwoManifest(bookId);
  @override
  Future<InitialSyncSession> beginDownload(String bookId) async {
    beginDownloadCalls++;
    await release.future;
    return InitialSyncSession(
      id: 'blocking-session',
      manifest: _twentyTwoManifest(bookId),
      direction: InitialSyncDirection.download,
    );
  }

  @override
  Future<InitialSyncBatch> downloadBatch({
    required String sessionId,
    required String entityType,
    String? afterEntityId,
    int limit = 100,
  }) async {
    final rows = _twentyTwoRows('remote-concurrent')
        .where((row) => row['entity_type'] == entityType)
        .map((row) => row['payload'] as Map<String, Object?>)
        .toList();
    return InitialSyncBatch(
      entityType: entityType,
      rows: afterEntityId == null ? rows : const [],
      nextCursor: rows.isEmpty ? null : rows.last['id'] as String,
      complete: true,
    );
  }

  @override
  Future<InitialSyncSession> beginUpload(InitialSyncManifest manifest) =>
      throw UnimplementedError();
  @override
  Future<int> uploadBatch({
    required String sessionId,
    required String entityType,
    required List<Map<String, Object?>> rows,
  }) => throw UnimplementedError();
  @override
  Future<int> completeUpload(String sessionId) => throw UnimplementedError();
  @override
  Future<void> cancel(String sessionId) async {}
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta04b-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _StoreFixture extends _Fixture {
  const _StoreFixture(super.directory, super.path, this.store, this.book);
  final LocalStore store;
  final FinancialBook book;

  @override
  Future<void> dispose() async {
    await store.close();
    await super.dispose();
  }
}
