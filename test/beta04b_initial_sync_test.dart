// The analyzer resolves conditional stores to web while this suite deliberately
// exercises the native SQLite implementation. The native test compiler resolves
// both facades to the matching native types.
// ignore_for_file: argument_type_not_assignable

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
      expect(await reopened.db.getVersion(), 15);
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
      expect(
        find.byKey(const Key('initial-download-non-merge-warning')),
        findsOneWidget,
      );
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
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}

class _NoopInitialSyncRepository implements InitialSyncRepository {
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
    final rows = _downloadRows(downloadBookId)
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
