// The native test compiler resolves the conditional database facade correctly.
// ignore_for_file: argument_type_not_assignable

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/features/backup/data/local_household_backup_store.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';
import 'package:pilgrim_tracker/features/sync/data/initial_sync_store_native.dart';
import 'package:pilgrim_tracker/features/sync/data/local_initial_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/data/local_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/cloud_sync_state_classifier.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_coordinator.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_coordinator.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/initial_sync_controller.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/sync_controller.dart';
import 'package:pilgrim_tracker/features/sync/presentation/widgets/sync_status_section.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('BETA-07C2 deterministic classification', () {
    const classifier = CloudSyncStateClassifier();
    final book = FinancialBook(id: 'household-h', name: 'Household H');
    final linkedBook = book.copyWith(remoteLinkedAt: DateTime(2026, 8, 9));
    final initialized = _manifest('household-h', initialized: true);
    final uninitialized = _manifest('household-h', initialized: false);

    test('unknown remote state is checking and never upload', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: false,
        authenticated: true,
        localBook: linkedBook,
        matchingMembershipIsOwner: true,
        hostedBookIds: const ['household-h'],
        remoteManifests: const {},
        failedManifestBookIds: const {},
        localCursor: _cursor(SyncInitializationState.primaryUploadRequired),
      );
      expect(
        result.classification,
        CloudSyncClassification.remoteStateChecking,
      );
    });

    test('initialized same ID with cleared readiness reconnects', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: true,
        localBook: book,
        matchingMembershipIsOwner: false,
        hostedBookIds: const ['household-h'],
        remoteManifests: {'household-h': initialized},
        failedManifestBookIds: const {},
        localCursor: null,
      );
      expect(
        result.classification,
        CloudSyncClassification.reconnectSameHostedHousehold,
      );
    });

    test('initialized remote can never become primary upload required', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: true,
        localBook: linkedBook,
        matchingMembershipIsOwner: true,
        hostedBookIds: const ['household-h'],
        remoteManifests: {'household-h': initialized},
        failedManifestBookIds: const {},
        localCursor: _cursor(SyncInitializationState.primaryUploadRequired),
      );
      expect(
        result.classification,
        CloudSyncClassification.reconnectSameHostedHousehold,
      );
    });

    test('only authoritative uninitialized owner state permits upload', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: true,
        localBook: linkedBook,
        matchingMembershipIsOwner: true,
        hostedBookIds: const ['household-h'],
        remoteManifests: {'household-h': uninitialized},
        failedManifestBookIds: const {},
        localCursor: _cursor(SyncInitializationState.primaryUploadRequired),
      );
      expect(
        result.classification,
        CloudSyncClassification.genuinePrimaryUploadRequired,
      );
    });

    test('ready same-ID household is already synced', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: true,
        localBook: linkedBook,
        matchingMembershipIsOwner: false,
        hostedBookIds: const ['household-h'],
        remoteManifests: {'household-h': initialized},
        failedManifestBookIds: const {},
        localCursor: _cursor(SyncInitializationState.ready),
      );
      expect(result.classification, CloudSyncClassification.alreadySynced);
    });

    test('different initialized membership is an additional download', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: true,
        localBook: book,
        matchingMembershipIsOwner: false,
        hostedBookIds: const ['other-hosted'],
        remoteManifests: {
          'other-hosted': _manifest('other-hosted', initialized: true),
        },
        failedManifestBookIds: const {},
        localCursor: null,
      );
      expect(
        result.classification,
        CloudSyncClassification.downloadAdditionalHostedHousehold,
      );
    });

    test('authentication and membership requirements are distinct', () {
      CloudSyncDecision classify({
        required bool auth,
        required List<String> ids,
      }) => classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: auth,
        localBook: book,
        matchingMembershipIsOwner: false,
        hostedBookIds: ids,
        remoteManifests: const {},
        failedManifestBookIds: const {},
        localCursor: null,
      );
      expect(
        classify(auth: false, ids: const []).classification,
        CloudSyncClassification.authenticationRequired,
      );
      expect(
        classify(auth: true, ids: const []).classification,
        CloudSyncClassification.membershipRequired,
      );
    });

    test('manifest failure is blocked rather than upload', () {
      final result = classifier.classify(
        cloudConfigured: true,
        remoteStateLoaded: true,
        authenticated: true,
        localBook: linkedBook,
        matchingMembershipIsOwner: true,
        hostedBookIds: const ['household-h'],
        remoteManifests: const {},
        failedManifestBookIds: const {'household-h'},
        localCursor: _cursor(SyncInitializationState.primaryUploadRequired),
      );
      expect(result.classification, CloudSyncClassification.blocked);
    });

    test(
      'remote manifests outside active memberships are never discovered',
      () {
        final result = classifier.classify(
          cloudConfigured: true,
          remoteStateLoaded: true,
          authenticated: true,
          localBook: book,
          matchingMembershipIsOwner: false,
          hostedBookIds: const [],
          remoteManifests: {
            'unlisted-household': _manifest(
              'unlisted-household',
              initialized: true,
            ),
          },
          failedManifestBookIds: const {},
          localCursor: null,
        );
        expect(
          result.classification,
          CloudSyncClassification.membershipRequired,
        );
        expect(result.targetBookId, isNull);
      },
    );
  });

  testWidgets('reconnect state never presents stale upload/success history', (
    tester,
  ) async {
    final sync =
        SyncController(
            SyncCoordinator(
              repository: _NoopSyncRepository(),
              transport: const UnavailableSyncTransport(configured: true),
            ),
          )
          ..result = const SyncRunResult(
            status: SyncStatus.primaryUploadRequired,
          )
          ..lastSuccessfulSyncAt = DateTime(2026, 8, 9, 21, 6);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusSection(
            controller: sync,
            cloudDecision: const CloudSyncDecision(
              CloudSyncClassification.reconnectSameHostedHousehold,
              reason: 'widget-regression',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Reconnect cloud sharing'), findsOneWidget);
    expect(find.text('Initial upload required'), findsNothing);
    expect(find.textContaining('Last successful:'), findsNothing);
    sync.dispose();
  });

  test(
    'replacement restore restart reconnect second restart and incremental sync',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      var store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      final authoritative = await _seedRestoredScenario(store);
      final backupService = HouseholdBackupService(
        LocalHouseholdBackupStore(store),
      );
      final backup = await backupService.create(
        bookId: authoritative.bookId,
        password: 'correct horse battery staple',
      );
      final decoded = await backupService.validate(
        backup.bytes,
        'correct horse battery staple',
      );
      await backupService.restore(
        backup: decoded,
        mode: RestoreMode.replaceMatchingHousehold,
        activeBookId: authoritative.bookId,
        confirmedHouseholdName: 'Enos & Grace Beta Test',
      );
      expect(
        (await store.getFinancialBooks()).single['remote_linked_at'],
        isNull,
      );
      expect(await store.getSyncCursor(authoritative.bookId), isNull);
      await store.close();

      store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      var repository = _initialRepository(store);
      final initialTransport = _SnapshotInitialTransport(
        authoritative.snapshot,
        authoritative.bookId,
        memberId: 'member-grace',
      );
      var controller = InitialSyncController(
        coordinator: InitialSyncCoordinator(
          repository: repository,
          transport: initialTransport,
        ),
      );
      var book = FinancialBook.fromRecord(
        (await store.getFinancialBooks()).single,
      );
      await controller.setContext(
        primaryBook: book,
        primaryIsOwner: false,
        authUserId: 'auth-grace',
        hostedBookIds: [book.id],
        remoteStateLoaded: true,
      );
      expect(
        controller.decision.classification,
        CloudSyncClassification.reconnectSameHostedHousehold,
      );
      expect(controller.canUpload, isFalse);
      await controller.reconnect(book.id);
      expect(controller.lastResult?.success, isTrue);
      expect(await repository.isIncrementallySyncReady(book.id), isTrue);
      expect(await store.getPendingSyncCount(book.id), 0);
      expect(
        (await store.db.query(
          'transactions',
          where: 'book_id = ?',
          whereArgs: [book.id],
        )).map((row) => row['id']),
        contains('remote-a'),
      );
      expect(
        (await store.db.query(
          'transactions',
          where: 'book_id = ?',
          whereArgs: [book.id],
        )).map((row) => row['id']),
        isNot(contains('local-c')),
      );
      controller.dispose();
      await store.close();

      store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      repository = _initialRepository(store);
      controller = InitialSyncController(
        coordinator: InitialSyncCoordinator(
          repository: repository,
          transport: initialTransport,
        ),
      );
      book = FinancialBook.fromRecord((await store.getFinancialBooks()).single);
      await controller.setContext(
        primaryBook: book,
        primaryIsOwner: false,
        authUserId: 'auth-grace',
        hostedBookIds: [book.id],
        remoteStateLoaded: true,
      );
      expect(
        controller.decision.classification,
        CloudSyncClassification.alreadySynced,
      );
      expect(await repository.isIncrementallySyncReady(book.id), isTrue);
      expect(
        (await store.getLocalSession())!['active_member_id'],
        'member-grace',
      );

      await store.upsertTransaction(
        _transaction(
          id: 'android-d',
          bookId: book.id,
          memberId: 'member-grace',
          category: 'Food',
          account: 'Cash',
          amount: 4321,
        ).toRecord(),
      );
      expect(await store.getPendingSyncCount(book.id), 1);
      final incrementalTransport = _ConvergingSyncTransport();
      final result = await SyncCoordinator(
        repository: LocalSyncRepository(store),
        transport: incrementalTransport,
      ).synchronize(book);
      expect(result.status, SyncStatus.synced);
      expect(incrementalTransport.remoteIds, contains('android-d'));
      expect(await store.getPendingSyncCount(book.id), 0);
      expect(await repository.isIncrementallySyncReady(book.id), isTrue);
      controller.dispose();
      await store.close();
    },
  );
}

InitialSyncManifest _manifest(String bookId, {required bool initialized}) =>
    InitialSyncManifest(
      bookId: bookId,
      bookName: 'Enos & Grace Beta Test',
      baseCurrencyCode: 'IDR',
      counts: const {},
      snapshotSequence: initialized ? 50 : 0,
      remoteInitializationComplete: initialized,
      remoteRecordCount: initialized ? 1 : 0,
    );

SyncCursor _cursor(SyncInitializationState state) => SyncCursor(
  bookId: 'household-h',
  lastServerSequence: state == SyncInitializationState.ready ? 50 : 0,
  initializationState: state,
  updatedAt: DateTime(2026, 8, 9),
);

LocalInitialSyncRepository _initialRepository(LocalStore store) =>
    LocalInitialSyncRepository(
      syncRepository: LocalSyncRepository(store),
      store: InitialSyncStoreAdapter(store),
    );

class _SeedResult {
  const _SeedResult(this.bookId, this.snapshot);
  final String bookId;
  final Map<String, List<Map<String, Object?>>> snapshot;
}

Future<_SeedResult> _seedRestoredScenario(LocalStore store) async {
  const bookId = 'household-h';
  final now = DateTime(2026, 8, 9);
  await store.upsertLocalProfile({
    'id': 'profile',
    'display_name': 'Grace device',
    'default_currency_code': 'IDR',
    'created_at': now.millisecondsSinceEpoch,
    'updated_at': now.millisecondsSinceEpoch,
  });
  await store.upsertFinancialBook(
    FinancialBook(
      id: bookId,
      name: 'Enos & Grace Beta Test',
      remoteLinkedAt: now,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
    ).toRecord(),
    enqueueSync: false,
  );
  store.setActiveBookId(bookId);
  for (final member in [
    HouseholdMember(
      id: 'member-enos',
      bookId: bookId,
      displayName: 'Enos',
      role: HouseholdMemberRole.owner,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
    ),
    HouseholdMember(
      id: 'member-grace',
      bookId: bookId,
      displayName: 'Grace',
      role: HouseholdMemberRole.member,
      authUserId: 'auth-grace',
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
    ),
  ]) {
    await store.upsertHouseholdMember(member.toRecord(), enqueueSync: false);
  }
  await store.upsertAccount(
    Account(
      id: 'account-cash',
      bookId: bookId,
      ownerMemberId: 'member-enos',
      name: 'Cash',
      accountType: AccountType.cash,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
    ).toRecord(),
    enqueueSync: false,
  );
  await store.saveMasterName('categories', 'Food', categoryType: 'expense');
  final category = (await store.getCategoryRecords(
    categoryType: 'expense',
  )).single;
  await store.upsertMonthlyCategoryBudget({
    'id': 'budget-b',
    'book_id': bookId,
    'category_id': category['id'],
    'month_start': '2026-08-01',
    'limit_minor': 500000,
    'currency_code': 'IDR',
    'note': null,
    'created_at': now.millisecondsSinceEpoch,
    'updated_at': now.millisecondsSinceEpoch,
    'deleted_at': null,
    'version': 1,
    'device_id': 'windows',
    'sync_status': 'synced',
  });
  await store.upsertTransaction(
    _transaction(
      id: 'remote-a',
      bookId: bookId,
      memberId: 'member-enos',
      category: 'Food',
      account: 'Cash',
      amount: 10000,
    ).toRecord(),
  );
  await store.db.delete(
    'sync_outbox',
    where: 'book_id = ?',
    whereArgs: [bookId],
  );
  await store.setSyncInitializationState(
    bookId,
    SyncInitializationState.ready.name,
  );
  final authoritative = await store.createHouseholdBackupSnapshot(bookId);
  await store.upsertTransaction(
    _transaction(
      id: 'local-c',
      bookId: bookId,
      memberId: 'member-grace',
      category: 'Food',
      account: 'Cash',
      amount: 99999,
    ).toRecord(),
  );
  await store.saveLocalSession(
    activeProfileId: 'profile',
    onboardingCompleted: true,
    activeBookId: bookId,
    activeMemberId: 'member-grace',
  );
  return _SeedResult(bookId, authoritative);
}

Transaction _transaction({
  required String id,
  required String bookId,
  required String memberId,
  required String category,
  required String account,
  required int amount,
}) => Transaction(
  id: id,
  bookId: bookId,
  enteredByMemberId: memberId,
  title: id,
  category: category,
  account: account,
  date: DateTime(2026, 8, 9),
  amount: amount,
  type: TransactionType.expense,
  createdAt: DateTime(2026, 8, 9),
  updatedAt: DateTime(2026, 8, 9),
  syncStatus: 'synced',
);

class _SnapshotInitialTransport implements InitialSyncTransport {
  _SnapshotInitialTransport(
    this.snapshot,
    this.bookId, {
    required this.memberId,
  });

  final Map<String, List<Map<String, Object?>>> snapshot;
  final String bookId;
  final String memberId;

  Map<String, List<Map<String, Object?>>> get rows => {
    'books': snapshot['household'] ?? const [],
    'household_members': snapshot['members'] ?? const [],
    'categories': snapshot['categories'] ?? const [],
    'monthly_category_budgets': snapshot['budgets'] ?? const [],
    'projects': snapshot['projects'] ?? const [],
    'accounts': snapshot['accounts'] ?? const [],
    'asset_definitions': snapshot['asset_definitions'] ?? const [],
    'transactions': snapshot['transactions'] ?? const [],
  };

  InitialSyncManifest get manifest => InitialSyncManifest(
    bookId: bookId,
    bookName: 'Enos & Grace Beta Test',
    baseCurrencyCode: 'IDR',
    counts: {for (final entry in rows.entries) entry.key: entry.value.length},
    snapshotSequence: 50,
    memberRole: 'member',
    householdMemberId: memberId,
    remoteInitializationComplete: true,
    remoteRecordCount: rows.values.fold(0, (sum, value) => sum + value.length),
  );

  @override
  bool get isAuthenticated => true;
  @override
  bool get isConfigured => true;
  @override
  Future<InitialSyncManifest> inspect(String requestedBookId) async => manifest;
  @override
  Future<InitialSyncSession> beginDownload(String requestedBookId) async =>
      InitialSyncSession(
        id: 'download-session',
        manifest: manifest,
        direction: InitialSyncDirection.download,
      );
  @override
  Future<InitialSyncBatch> downloadBatch({
    required String sessionId,
    required String entityType,
    String? afterEntityId,
    int limit = 100,
  }) async {
    final page = afterEntityId == null
        ? rows[entityType] ?? const <Map<String, Object?>>[]
        : const <Map<String, Object?>>[];
    return InitialSyncBatch(
      entityType: entityType,
      rows: page,
      nextCursor: page.isEmpty ? null : page.last['id'] as String,
      complete: true,
    );
  }

  @override
  Future<InitialSyncSession> beginUpload(InitialSyncManifest manifest) =>
      throw StateError('Reconnect must never upload.');
  @override
  Future<int> uploadBatch({
    required String sessionId,
    required String entityType,
    required List<Map<String, Object?>> rows,
  }) => throw StateError('Reconnect must never upload.');
  @override
  Future<int> completeUpload(String sessionId) =>
      throw StateError('Reconnect must never upload.');
  @override
  Future<void> cancel(String sessionId) async {}
}

class _ConvergingSyncTransport implements SyncTransport {
  final remoteIds = <String>{};
  final _changes = <RemoteChange>[];

  @override
  bool get isAuthenticated => true;
  @override
  bool get isConfigured => true;

  @override
  Future<List<PushOperationResult>> push(
    String bookId,
    List<SyncOperation> operations,
  ) async {
    for (final operation in operations) {
      remoteIds.add(operation.entityId);
      _changes.add(
        RemoteChange(
          sequence: 50 + _changes.length + 1,
          entityType: operation.entityType,
          entityId: operation.entityId,
          serverVersion: operation.baseVersion + 1,
          operationType: operation.operationType,
          payload: operation.payload!,
        ),
      );
    }
    return [
      for (final operation in operations)
        PushOperationResult(
          operationId: operation.operationId,
          status: PushResultStatus.applied,
          serverVersion: operation.baseVersion + 1,
        ),
    ];
  }

  @override
  Future<PullBatch> pull(
    String bookId, {
    required int afterSequence,
    int limit = 100,
  }) async {
    final changes = _changes
        .where((change) => change.sequence > afterSequence)
        .toList();
    return PullBatch(
      changes: changes,
      finalSequence: changes.isEmpty ? afterSequence : changes.last.sequence,
    );
  }
}

class _NoopSyncRepository implements SyncRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp('beta07c2-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
