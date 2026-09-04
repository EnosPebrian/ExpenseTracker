import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_file_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_recovery_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_recovery_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/backup/presentation/controllers/backup_export_controller.dart';
import 'package:pilgrim_tracker/features/backup/presentation/controllers/backup_recovery_controller.dart';
import 'package:pilgrim_tracker/features/backup/presentation/screens/backup_export_screen.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_duplicate_detector.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/beta06_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  group('BETA-08A duplicate detector', () {
    const detector = TransactionDuplicateDetector();
    final base = beta06Snapshot()['transactions']!.first;

    test('same identity is exact identity', () {
      expect(
        detector.classify(base, [base]).classification,
        TransactionCandidateClassification.exactIdentity,
      );
    });

    test('different ID with deterministic business match is semantic', () {
      final copy = {...base, 'id': 'other', 'title': '  SALARY---'};
      expect(
        detector.classify(copy, [base]).classification,
        TransactionCandidateClassification.semanticDuplicate,
      );
    });

    test(
      'nearby date is possible while amount and account changes are new',
      () {
        final nearby = {
          ...base,
          'id': 'nearby',
          'transaction_date':
              (base['transaction_date'] as int) + Duration.millisecondsPerDay,
        };
        expect(
          detector.classify(nearby, [base]).classification,
          TransactionCandidateClassification.possibleDuplicate,
        );
        expect(
          detector.classify({...nearby, 'amount': 1}, [base]).classification,
          TransactionCandidateClassification.newRecord,
        );
        expect(
          detector
              .classify({...nearby, 'account': 'Bank'}, [base])
              .classification,
          TransactionCandidateClassification.newRecord,
        );
      },
    );
  });

  group('BETA-08A recovery classification and commit', () {
    test(
      'missing transaction is recoverable and current-only record remains',
      () async {
        final backup = beta06Snapshot();
        backup['transactions']!.add(_transaction('transaction-d', 'Recovered'));
        final local = _copy(backup);
        local['transactions']!.removeWhere(
          (row) => row['id'] == 'transaction-d',
        );
        local['transactions']!.add(
          _transaction('transaction-c', 'Current only'),
        );
        final store = _MemoryRecoveryStore(local);
        final service = BackupRecoveryService(store: store);

        final preview = await service.analyze(
          backup: _decoded(backup),
          activeBookId: 'book-beta06',
        );
        final candidate = preview.candidates.singleWhere(
          (item) => item.id == 'transaction-d',
        );
        expect(candidate.classification, BackupRecoveryClassification.missing);
        await service.recover(preview: preview, selectedKeys: {candidate.key});
        expect(
          store.snapshot['transactions']!.map((row) => row['id']),
          containsAll(['transaction-c', 'transaction-d']),
        );
      },
    );

    test(
      'repeating the same recovery is idempotent with no extra outbox',
      () async {
        final backup = beta06Snapshot();
        final local = _copy(backup)..['transactions'] = [];
        final store = _MemoryRecoveryStore(local, linked: true, ready: true);
        final remote = _MemoryRemote(_copy(local));
        final service = BackupRecoveryService(
          store: store,
          remoteReader: remote,
        );
        var preview = await service.analyze(
          backup: _decoded(backup),
          activeBookId: 'book-beta06',
        );
        final keys = preview.candidates
            .where(
              (candidate) =>
                  candidate.entityType == 'transactions' &&
                  candidate.selectable,
            )
            .map((candidate) => candidate.key)
            .toSet();
        await service.recover(preview: preview, selectedKeys: keys);
        expect(store.outboxWrites, 2);
        remote.snapshot = _copy(store.snapshot);
        preview = await service.analyze(
          backup: _decoded(backup),
          activeBookId: 'book-beta06',
        );
        expect(
          preview.candidates
              .where((candidate) => candidate.entityType == 'transactions')
              .every(
                (candidate) =>
                    candidate.classification ==
                    BackupRecoveryClassification.identical,
              ),
          isTrue,
        );
        expect(store.outboxWrites, 2);
      },
    );

    test('same ID different content conflicts without mutation', () async {
      final backup = beta06Snapshot();
      final local = _copy(backup);
      local['transactions']!.first['amount'] = 999;
      final store = _MemoryRecoveryStore(local);
      final preview = await BackupRecoveryService(
        store: store,
      ).analyze(backup: _decoded(backup), activeBookId: 'book-beta06');
      expect(
        preview.candidates
            .firstWhere((candidate) => candidate.id == 'transaction-income')
            .classification,
        BackupRecoveryClassification.changedConflict,
      );
      expect(store.commits, 0);
    });

    test('remote tombstone blocks resurrection', () async {
      final backup = beta06Snapshot();
      final local = _copy(backup)..['transactions'] = [];
      final remote = _copy(local);
      remote['transactions'] = [
        {...backup['transactions']!.first, 'deleted_at': 1770000000000},
      ];
      final store = _MemoryRecoveryStore(local, linked: true, ready: true);
      final preview = await BackupRecoveryService(
        store: store,
        remoteReader: _MemoryRemote(remote),
      ).analyze(backup: _decoded(backup), activeBookId: 'book-beta06');
      expect(
        preview.candidates
            .firstWhere((candidate) => candidate.id == 'transaction-income')
            .classification,
        BackupRecoveryClassification.remoteDeleted,
      );
    });

    test('cloud-linked recovery blocks when remote is unavailable', () async {
      final store = _MemoryRecoveryStore(
        beta06Snapshot(),
        linked: true,
        ready: true,
      );
      final preview = await BackupRecoveryService(store: store).analyze(
        backup: _decoded(beta06Snapshot()),
        activeBookId: 'book-beta06',
      );
      expect(preview.canRecover, isFalse);
      expect(preview.blockingErrors.single, contains('Cloud verification'));
    });

    test('foreign household is rejected with required guidance', () async {
      final store = _MemoryRecoveryStore(beta06Snapshot());
      final preview = await BackupRecoveryService(store: store).analyze(
        backup: _decoded(beta06Snapshot(bookId: 'foreign')),
        activeBookId: 'book-beta06',
      );
      expect(preview.canRecover, isFalse);
      expect(
        preview.blockingErrors.single,
        'This backup belongs to a different household. Use Restore as new household instead.',
      );
    });

    test(
      'safe missing account is selected as transaction dependency',
      () async {
        final backup = beta06Snapshot();
        final local = _copy(backup)
          ..['accounts'] = []
          ..['transactions'] = [];
        final preview = await BackupRecoveryService(
          store: _MemoryRecoveryStore(local),
        ).analyze(backup: _decoded(backup), activeBookId: 'book-beta06');
        final transaction = preview.candidates.firstWhere(
          (candidate) => candidate.id == 'transaction-income',
        );
        expect(transaction.dependencies, contains('accounts::account-cash'));
        final plan = BackupRecoveryService(
          store: _MemoryRecoveryStore(local),
        ).buildPlan(preview, {transaction.key});
        expect(plan.selectedKeys, contains('accounts::account-cash'));
      },
    );

    test('missing member authority blocks dependent transaction', () async {
      final backup = beta06Snapshot();
      final local = _copy(backup)
        ..['members'] = []
        ..['transactions'] = [];
      final preview = await BackupRecoveryService(
        store: _MemoryRecoveryStore(local),
      ).analyze(backup: _decoded(backup), activeBookId: 'book-beta06');
      expect(
        preview.candidates
            .firstWhere((candidate) => candidate.id == 'transaction-income')
            .classification,
        BackupRecoveryClassification.invalidReference,
      );
    });

    test('manual market price is preview-only unsupported', () async {
      final local = beta06Snapshot()..['manual_market_prices'] = [];
      final preview =
          await BackupRecoveryService(
            store: _MemoryRecoveryStore(local),
          ).analyze(
            backup: _decoded(beta06Snapshot()),
            activeBookId: 'book-beta06',
          );
      expect(
        preview.candidates
            .firstWhere(
              (candidate) => candidate.entityType == 'manual_market_prices',
            )
            .classification,
        BackupRecoveryClassification.unsupported,
      );
    });

    test(
      'missing budget recovers and becomes identical on reanalysis',
      () async {
        final backup = beta06Snapshot()
          ..['budgets'] = [_budget('budget-groceries')];
        final local = _copy(backup)..['budgets'] = [];
        final store = _MemoryRecoveryStore(local);
        final service = BackupRecoveryService(store: store);
        var preview = await service.analyze(
          backup: _decoded(backup),
          activeBookId: 'book-beta06',
        );
        final budget = preview.candidates.singleWhere(
          (candidate) => candidate.id == 'budget-groceries',
        );
        expect(budget.classification, BackupRecoveryClassification.missing);
        await service.recover(preview: preview, selectedKeys: {budget.key});
        preview = await service.analyze(
          backup: _decoded(backup),
          activeBookId: 'book-beta06',
        );
        expect(
          preview.candidates
              .singleWhere((candidate) => candidate.id == 'budget-groceries')
              .classification,
          BackupRecoveryClassification.identical,
        );
      },
    );

    test('budget semantic uniqueness collision keeps current', () async {
      final backup = beta06Snapshot()..['budgets'] = [_budget('budget-backup')];
      final local = _copy(backup)
        ..['budgets'] = [_budget('budget-current', limitMinor: 900000)];
      final store = _MemoryRecoveryStore(local);
      final preview = await BackupRecoveryService(
        store: store,
      ).analyze(backup: _decoded(backup), activeBookId: 'book-beta06');
      expect(
        preview.candidates
            .singleWhere((candidate) => candidate.id == 'budget-backup')
            .classification,
        BackupRecoveryClassification.changedConflict,
      );
      expect(store.commits, 0);
    });

    test(
      'v1 backup without budgets leaves current budgets untouched',
      () async {
        final backup = beta06Snapshot()..remove('budgets');
        final local = _copy(beta06Snapshot())
          ..['budgets'] = [_budget('current-budget')];
        final store = _MemoryRecoveryStore(local);
        final preview = await BackupRecoveryService(store: store).analyze(
          backup: _decoded(backup, formatVersion: 1),
          activeBookId: 'book-beta06',
        );
        expect(
          preview.candidates.where(
            (candidate) => candidate.entityType == 'budgets',
          ),
          isEmpty,
        );
        expect(store.snapshot['budgets']!.single['id'], 'current-budget');
      },
    );

    test('commit failure is atomic in recovery store contract', () async {
      final backup = beta06Snapshot();
      final local = _copy(backup)..['transactions'] = [];
      final store = _MemoryRecoveryStore(local)..failCommit = true;
      final service = BackupRecoveryService(store: store);
      final before = _copy(store.snapshot);
      final preview = await service.analyze(
        backup: _decoded(backup),
        activeBookId: 'book-beta06',
      );
      final keys = preview.candidates
          .where((candidate) => candidate.entityType == 'transactions')
          .map((candidate) => candidate.key)
          .toSet();
      await expectLater(
        service.recover(preview: preview, selectedKeys: keys),
        throwsStateError,
      );
      expect(store.snapshot, before);
      expect(store.outboxWrites, 0);
    });
  });

  test(
    'native atomic recovery preserves cloud state and creates normal outbox',
    () async {
      final directory = await Directory.systemTemp.createTemp('beta08a-');
      final store = LocalStore(databasePath: p.join(directory.path, 'test.db'));
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      await store.initialize();
      final backup = beta06Snapshot();
      final local = _copy(backup)..['transactions'] = [];
      final prepared = HouseholdBackupIntegrity.prepareForRestore(local);
      await store.activateHouseholdBackupSnapshot(prepared);
      final currentBook = (await store.getFinancialBooks()).single;
      await store.upsertFinancialBook({
        ...currentBook,
        'remote_linked_at': 1770000000000,
      }, enqueueSync: false);
      await store.setSyncInitializationState('book-beta06', 'ready');
      final adapter = _NativeRecoveryStore(store);
      final remote = _MemoryRemote(_copy(local));
      final service = BackupRecoveryService(
        store: adapter,
        remoteReader: remote,
      );
      final cursorBefore = await store.getSyncCursor('book-beta06');

      final preview = await service.analyze(
        backup: _decoded(backup),
        activeBookId: 'book-beta06',
      );
      final selected = preview.candidates
          .where((candidate) => candidate.entityType == 'transactions')
          .map((candidate) => candidate.key)
          .toSet();
      final result = await service.recover(
        preview: preview,
        selectedKeys: selected,
      );

      final saved = await store.getTransactions(
        includeDeleted: true,
        bookId: 'book-beta06',
      );
      expect(saved, hasLength(2));
      expect(
        saved.map((row) => row['id']),
        containsAll(['transaction-income', 'transaction-expense']),
      );
      expect(
        saved.every((row) => row['device_id'] == 'backup-recovery'),
        isTrue,
      );
      expect(saved.every((row) => row['sync_status'] == 'pending'), isTrue);
      expect(result.pendingCount, 2);
      expect(
        (await store.getFinancialBooks()).single['remote_linked_at'],
        1770000000000,
      );
      expect(await store.getSyncCursor('book-beta06'), cursorBefore);
    },
  );

  testWidgets('recovery is a visible action separate from restore', (
    tester,
  ) async {
    final snapshot = beta06Snapshot();
    final backupStore = _NoopBackupStore(snapshot);
    final exportController = BackupExportController(
      backupService: HouseholdBackupService(backupStore),
      fileService: const PortableFileService(),
    );
    final recoveryController = BackupRecoveryController(
      backupService: HouseholdBackupService(backupStore),
      recoveryService: BackupRecoveryService(
        store: _MemoryRecoveryStore(snapshot),
      ),
      fileService: const PortableFileService(),
    )..load('book-beta06');
    addTearDown(exportController.dispose);
    addTearDown(recoveryController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BackupExportScreen(
          controller: exportController,
          recoveryController: recoveryController,
        ),
      ),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Restore entire backup'), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      if (find.text('Recover missing records').evaluate().isNotEmpty) break;
    }
    expect(find.text('Recover missing records'), findsOneWidget);
    expect(find.textContaining('without replacing'), findsOneWidget);
  });
}

DecodedBackup _decoded(
  Map<String, List<Map<String, Object?>>> snapshot, {
  int formatVersion = 2,
}) {
  final household = snapshot['household']!.single;
  return DecodedBackup(
    manifest: PortableBackupManifest(
      formatVersion: formatVersion,
      applicationVersion: 'test',
      databaseSchemaVersion: 21,
      exportedAt: DateTime(2026, 8, 9),
      bookId: household['id'] as String,
      bookName: household['name'] as String,
      baseCurrencyCode: household['base_currency_code'] as String,
      entityCounts: {
        for (final entry in snapshot.entries) entry.key: entry.value.length,
      },
      contentChecksum: 'test',
      encryptionMetadata: const {},
      financialSummary: const {},
      deletedStateCounts: const {},
    ),
    snapshot: snapshot,
  );
}

Map<String, Object?> _transaction(String id, String title) => {
  ...beta06Snapshot()['transactions']!.first,
  'id': id,
  'title': title,
  'amount': 12345,
};

Map<String, Object?> _budget(String id, {int limitMinor = 500000}) => {
  'id': id,
  'book_id': 'book-beta06',
  'category_id': 'category-expense',
  'month_start': '2026-08-01',
  'limit_minor': limitMinor,
  'currency_code': 'IDR',
  'note': null,
  'created_at': 1767225600000,
  'updated_at': 1767225600000,
  'deleted_at': null,
  'version': 1,
  'device_id': 'old-device',
  'sync_status': 'synced',
};

Map<String, List<Map<String, Object?>>> _copy(
  Map<String, List<Map<String, Object?>>> source,
) => {
  for (final entry in source.entries)
    entry.key: entry.value.map(Map<String, Object?>.of).toList(),
};

class _MemoryRecoveryStore implements BackupRecoveryStore {
  _MemoryRecoveryStore(
    Map<String, List<Map<String, Object?>>> snapshot, {
    this.linked = false,
    this.ready = false,
  }) : snapshot = _copy(snapshot);

  Map<String, List<Map<String, Object?>>> snapshot;
  final bool linked;
  final bool ready;
  int commits = 0;
  int outboxWrites = 0;
  bool failCommit = false;

  @override
  Future<int> commitRecovery(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) async {
    final before = _copy(snapshot);
    try {
      if (failCommit) throw StateError('forced failure');
      for (final entry in records.entries) {
        snapshot
            .putIfAbsent(entry.key, () => [])
            .addAll(
              entry.value.map(
                (row) => {
                  ...row,
                  'version': 1,
                  'device_id': 'backup-recovery',
                  'sync_status': enqueueSync ? 'pending' : 'local_only',
                },
              ),
            );
      }
      commits++;
      if (enqueueSync) {
        outboxWrites += records.values.fold(0, (a, b) => a + b.length);
      }
      return outboxWrites;
    } catch (_) {
      snapshot = before;
      rethrow;
    }
  }

  @override
  Future<BackupRecoveryCloudState> recoveryCloudState(String bookId) async =>
      BackupRecoveryCloudState(linked: linked, ready: ready, cursor: 17);

  @override
  Future<Map<String, List<Map<String, Object?>>>> recoverySnapshot(
    String bookId,
  ) async => _copy(snapshot);
}

class _MemoryRemote implements BackupRecoveryRemoteReader {
  _MemoryRemote(this.snapshot);
  Map<String, List<Map<String, Object?>>> snapshot;

  @override
  bool get available => true;

  @override
  Future<Map<String, List<Map<String, Object?>>>> read(String bookId) async =>
      _copy(snapshot);
}

class _NativeRecoveryStore implements BackupRecoveryStore {
  const _NativeRecoveryStore(this.store);

  final LocalStore store;

  @override
  Future<int> commitRecovery(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) => store.recoverHouseholdBackupRecords(
    bookId,
    records,
    enqueueSync: enqueueSync,
  );

  @override
  Future<BackupRecoveryCloudState> recoveryCloudState(String bookId) async {
    final book = (await store.getFinancialBooks(
      includeDeleted: true,
    )).firstWhere((row) => row['id'] == bookId);
    final cursor = await store.getSyncCursor(bookId);
    final linked = book['remote_linked_at'] != null;
    return BackupRecoveryCloudState(
      linked: linked,
      ready: !linked || cursor?['initialization_state'] == 'ready',
      cursor: (cursor?['last_server_sequence'] as num?)?.toInt(),
    );
  }

  @override
  Future<Map<String, List<Map<String, Object?>>>> recoverySnapshot(
    String bookId,
  ) => store.createHouseholdBackupSnapshot(bookId);
}

class _NoopBackupStore implements HouseholdBackupStore {
  _NoopBackupStore(this.value);
  final Map<String, List<Map<String, Object?>>> value;

  @override
  int get schemaVersion => 21;

  @override
  Future<void> activate(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> localHouseholds() async =>
      value['household']!;

  @override
  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    String bookId,
  ) async => _copy(value);
}
