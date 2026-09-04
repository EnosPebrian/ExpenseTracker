import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/restore_classifier.dart';

import 'support/beta06_fixture.dart';

void main() {
  test('same backup replacement keeps identical final counts', () async {
    final source = _MemoryBackupStore([beta06Snapshot()]);
    final created = await HouseholdBackupService(
      source,
    ).create(bookId: 'book-beta06', password: 'strong-password');
    final store = _MemoryBackupStore([]);
    final service = HouseholdBackupService(store);
    final decoded = await service.validate(created.bytes, 'strong-password');

    await service.restore(
      backup: decoded,
      mode: RestoreMode.newHousehold,
      activeBookId: 'empty',
    );
    final counts = _counts(store.snapshots.single);
    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.replaceMatchingHousehold,
      activeBookId: 'book-beta06',
    );
    await service.restore(
      backup: decoded,
      mode: RestoreMode.replaceMatchingHousehold,
      activeBookId: 'book-beta06',
      confirmedHouseholdName: 'Beta Household',
    );

    expect(_counts(store.snapshots.single), counts);
    expect(preview.newRecords, 0);
    expect(preview.alreadyPresent, counts.values.fold(0, (a, b) => a + b));
    expect(preview.recordsToReplace, 0);
    expect(store.outboxWrites, 0);
  });

  test('restore as new blocks a matching household ID collision', () async {
    final full = beta06Snapshot();
    final partial = HouseholdBackupIntegrity.prepareForRestore({
      for (final entry in full.entries)
        entry.key: entry.key == 'transactions'
            ? [Map<String, Object?>.of(entry.value.first)]
            : entry.value.map(Map<String, Object?>.of).toList(),
    });
    final store = _MemoryBackupStore([partial]);
    final service = HouseholdBackupService(store);
    final decoded = DecodedBackup(
      manifest: (await HouseholdBackupService(
        _MemoryBackupStore([full]),
      ).create(bookId: 'book-beta06', password: 'strong-password')).manifest,
      snapshot: full,
    );

    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.newHousehold,
      activeBookId: 'book-beta06',
    );
    expect(preview.canRestore, isFalse);
    expect(preview.conflicts, greaterThan(0));
    await expectLater(
      service.restore(
        backup: decoded,
        mode: RestoreMode.newHousehold,
        activeBookId: 'book-beta06',
      ),
      throwsA(isA<RestoreCollisionException>()),
    );
    expect(store.snapshots.single['transactions'], hasLength(1));
  });

  test('same stable ID with different content blocks atomically', () async {
    final incoming = beta06Snapshot();
    final local = HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot());
    local['transactions']!.first['amount_minor'] = 999;
    final before = local.toString();
    final store = _MemoryBackupStore([local]);
    final service = HouseholdBackupService(store);
    final created = await HouseholdBackupService(
      _MemoryBackupStore([incoming]),
    ).create(bookId: 'book-beta06', password: 'strong-password');
    final decoded = DecodedBackup(
      manifest: created.manifest,
      snapshot: incoming,
    );

    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.newHousehold,
      activeBookId: 'book-beta06',
    );
    expect(preview.conflicts, greaterThan(0));
    await expectLater(
      service.restore(
        backup: decoded,
        mode: RestoreMode.newHousehold,
        activeBookId: 'book-beta06',
      ),
      throwsA(isA<RestoreCollisionException>()),
    );
    expect(store.snapshots.single.toString(), before);
    expect(store.activationCount, 0);
  });

  test('foreign-household record is invalid and never applied', () async {
    final incoming = beta06Snapshot();
    incoming['accounts']!.first['book_id'] = 'foreign-book';
    final store = _MemoryBackupStore([]);
    final service = HouseholdBackupService(store);
    final created = await HouseholdBackupService(
      _MemoryBackupStore([beta06Snapshot()]),
    ).create(bookId: 'book-beta06', password: 'strong-password');
    final decoded = DecodedBackup(
      manifest: created.manifest,
      snapshot: incoming,
    );

    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.newHousehold,
      activeBookId: 'empty',
    );
    expect(preview.invalidRecords, 1);
    await expectLater(
      service.restore(
        backup: decoded,
        mode: RestoreMode.newHousehold,
        activeBookId: 'empty',
      ),
      throwsA(anything),
    );
    expect(store.snapshots, isEmpty);
  });

  test(
    'tombstone is skipped only when identical and never resurrected',
    () async {
      final snapshot = HouseholdBackupIntegrity.prepareForRestore(
        beta06Snapshot(),
      );
      snapshot['projects']!.single['deleted_at'] = 1234;
      final store = _MemoryBackupStore([snapshot]);
      final service = HouseholdBackupService(store);
      final created = await service.create(
        bookId: 'book-beta06',
        password: 'strong-password',
      );
      final decoded = await service.validate(created.bytes, 'strong-password');
      final preview = await service.preview(
        backup: decoded,
        mode: RestoreMode.replaceMatchingHousehold,
        activeBookId: 'book-beta06',
      );

      expect(preview.identicalByEntity['projects'], 1);
      await service.restore(
        backup: decoded,
        mode: RestoreMode.replaceMatchingHousehold,
        activeBookId: 'book-beta06',
        confirmedHouseholdName: 'Beta Household',
      );
      expect(store.snapshots.single['projects']!.single['deleted_at'], 1234);
    },
  );

  test(
    'replacement requires exact active ID and household-name confirmation',
    () async {
      final source = HouseholdBackupService(
        _MemoryBackupStore([beta06Snapshot()]),
      );
      final store = _MemoryBackupStore([
        HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot()),
      ]);
      final service = HouseholdBackupService(store);
      final decoded = await service.validate(
        (await source.create(
          bookId: 'book-beta06',
          password: 'strong-password',
        )).bytes,
        'strong-password',
      );

      await expectLater(
        service.restore(
          backup: decoded,
          mode: RestoreMode.replaceMatchingHousehold,
          activeBookId: 'book-beta06',
          confirmedHouseholdName: 'wrong',
        ),
        throwsA(isA<BackupValidationException>()),
      );
      await service.restore(
        backup: decoded,
        mode: RestoreMode.replaceMatchingHousehold,
        activeBookId: 'book-beta06',
        confirmedHouseholdName: 'Beta Household',
      );
      expect(store.lastReplaceBookId, 'book-beta06');
      expect(store.activationCount, 1);
    },
  );

  test(
    'same-book replacement classifies differences as records to replace',
    () async {
      final incoming = beta06Snapshot();
      final local = HouseholdBackupIntegrity.prepareForRestore(
        beta06Snapshot(),
      );
      local['transactions']!.first['amount_minor'] = 999;
      final store = _MemoryBackupStore([local]);
      final service = HouseholdBackupService(store);
      final created = await HouseholdBackupService(
        _MemoryBackupStore([incoming]),
      ).create(bookId: 'book-beta06', password: 'strong-password');
      final decoded = await service.validate(created.bytes, 'strong-password');

      final preview = await service.preview(
        backup: decoded,
        mode: RestoreMode.replaceMatchingHousehold,
        activeBookId: 'book-beta06',
      );

      expect(preview.recordsToReplace, 1);
      expect(preview.conflicts, 0);
      expect(preview.canRestore, isTrue);
    },
  );

  test(
    'replacement rejects a true cross-book record before activation',
    () async {
      final incoming = beta06Snapshot();
      incoming['transactions']!.first['book_id'] = 'foreign-book';
      final store = _MemoryBackupStore([
        HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot()),
      ]);
      final service = HouseholdBackupService(store);
      final source = HouseholdBackupService(
        _MemoryBackupStore([beta06Snapshot()]),
      );
      final created = await source.create(
        bookId: 'book-beta06',
        password: 'strong-password',
      );
      final decoded = DecodedBackup(
        manifest: created.manifest,
        snapshot: incoming,
      );

      final preview = await service.preview(
        backup: decoded,
        mode: RestoreMode.replaceMatchingHousehold,
        activeBookId: 'book-beta06',
      );

      expect(preview.canRestore, isFalse);
      expect(preview.invalidRecords, 1);
      expect(preview.blockingReason, contains('foreign-household'));
      expect(store.activationCount, 0);
    },
  );

  test('restored snapshot is local-only and contains no cloud identity', () {
    final prepared = HouseholdBackupIntegrity.prepareForRestore(
      beta06Snapshot(),
    );
    final encoded = prepared.values.expand((rows) => rows).toList().toString();

    expect(prepared['household']!.single['remote_linked_at'], isNull);
    expect(prepared['members']!.single['auth_user_id'], isNull);
    expect(encoded, isNot(contains('remote-user-secret')));
    expect(encoded, isNot(contains('device-secret')));
    for (final record in prepared.values.expand((rows) => rows)) {
      if (record.containsKey('sync_status')) {
        expect(record['sync_status'], 'local_only');
      }
    }
  });

  test('format 1 replacement preserves existing monthly budgets', () async {
    final local = beta06Snapshot();
    local['budgets'] = [
      {
        'id': 'budget-existing',
        'book_id': 'book-beta06',
        'category_id': 'category-expense',
        'month_start': '2026-07-01',
        'limit_minor': 750000,
        'currency_code': 'IDR',
        'note': null,
        'created_at': 1767225600000,
        'updated_at': 1767225600000,
        'deleted_at': null,
        'version': 1,
        'device_id': 'device-secret',
        'sync_status': 'local_only',
      },
    ];
    final store = _MemoryBackupStore([
      HouseholdBackupIntegrity.prepareForRestore(local),
    ]);
    final service = HouseholdBackupService(store);
    final created = await service.codec.encode(
      snapshot: beta06Snapshot(),
      password: 'strong-password',
      formatVersion: 1,
    );
    final decoded = await service.validate(created.bytes, 'strong-password');

    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.replaceMatchingHousehold,
      activeBookId: 'book-beta06',
    );
    await service.restore(
      backup: decoded,
      mode: RestoreMode.replaceMatchingHousehold,
      activeBookId: 'book-beta06',
      confirmedHouseholdName: 'Beta Household',
    );

    expect(preview.expectedFinalTotals['budgets'], 1);
    expect(store.snapshots.single['budgets'], hasLength(1));
    expect(store.snapshots.single['budgets']!.single['id'], 'budget-existing');
  });

  test('format 1 preview explains that budgets were not supported', () async {
    final service = HouseholdBackupService(_MemoryBackupStore([]));
    final created = await service.codec.encode(
      snapshot: beta06Snapshot(),
      password: 'strong-password',
      formatVersion: 1,
    );
    final decoded = await service.validate(created.bytes, 'strong-password');

    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.newHousehold,
      activeBookId: 'empty',
    );

    expect(
      preview.details,
      contains(
        'This backup was created before monthly budgets were supported.',
      ),
    );
  });

  test('format 2 restores budgets as new without outbox work', () async {
    final source = beta06Snapshot();
    source['budgets'] = [_budgetRecord(limitMinor: 750000)];
    final sourceService = HouseholdBackupService(_MemoryBackupStore([source]));
    final created = await sourceService.create(
      bookId: 'book-beta06',
      password: 'strong-password',
    );
    final target = _MemoryBackupStore([]);
    final service = HouseholdBackupService(target);
    final decoded = await service.validate(created.bytes, 'strong-password');

    await service.restore(
      backup: decoded,
      mode: RestoreMode.newHousehold,
      activeBookId: 'empty',
    );

    expect(target.snapshots.single['budgets'], hasLength(1));
    expect(target.snapshots.single['budgets']!.single['id'], 'budget-food');
    expect(target.snapshots.single['budgets']!.single['limit_minor'], 750000);
    expect(target.outboxWrites, 0);
  });

  test('format 2 replacement classifies and replaces a budget', () async {
    final incoming = beta06Snapshot();
    incoming['budgets'] = [_budgetRecord(limitMinor: 900000)];
    final existing = HouseholdBackupIntegrity.prepareForRestore(
      beta06Snapshot(),
    );
    existing['budgets'] = [_budgetRecord(limitMinor: 750000)];
    final store = _MemoryBackupStore([existing]);
    final service = HouseholdBackupService(store);
    final created = await HouseholdBackupService(
      _MemoryBackupStore([incoming]),
    ).create(bookId: 'book-beta06', password: 'strong-password');
    final decoded = await service.validate(created.bytes, 'strong-password');

    final preview = await service.preview(
      backup: decoded,
      mode: RestoreMode.replaceMatchingHousehold,
      activeBookId: 'book-beta06',
    );
    expect(preview.replacementByEntity['budgets'], 1);
    await service.restore(
      backup: decoded,
      mode: RestoreMode.replaceMatchingHousehold,
      activeBookId: 'book-beta06',
      confirmedHouseholdName: 'Beta Household',
    );

    expect(store.snapshots.single['budgets']!.single['limit_minor'], 900000);
    expect(store.outboxWrites, 0);
  });

  test(
    'budget with missing category fails preview without activation',
    () async {
      final valid = beta06Snapshot();
      final created = await HouseholdBackupService(
        _MemoryBackupStore([valid]),
      ).create(bookId: 'book-beta06', password: 'strong-password');
      final invalid = beta06Snapshot();
      invalid['budgets'] = [
        {
          ..._budgetRecord(limitMinor: 750000),
          'category_id': 'missing-category',
        },
      ];
      final store = _MemoryBackupStore([]);
      final service = HouseholdBackupService(store);

      final preview = await service.preview(
        backup: DecodedBackup(manifest: created.manifest, snapshot: invalid),
        mode: RestoreMode.newHousehold,
        activeBookId: 'empty',
      );

      expect(preview.canRestore, isFalse);
      expect(store.activationCount, 0);
      expect(store.snapshots, isEmpty);
    },
  );
}

Map<String, Object?> _budgetRecord({required int limitMinor}) => {
  'id': 'budget-food',
  'book_id': 'book-beta06',
  'category_id': 'category-expense',
  'month_start': '2026-07-01',
  'limit_minor': limitMinor,
  'currency_code': 'IDR',
  'note': 'Household groceries',
  'created_at': 1767225600000,
  'updated_at': 1767225600000,
  'deleted_at': null,
  'version': 1,
  'device_id': 'device-beta06',
  'sync_status': 'local_only',
};

class _MemoryBackupStore implements HouseholdBackupStore {
  _MemoryBackupStore(this.snapshots);

  final List<Map<String, List<Map<String, Object?>>>> snapshots;
  String? lastReplaceBookId;
  int activationCount = 0;
  int outboxWrites = 0;

  @override
  int get schemaVersion => 21;

  @override
  Future<void> activate(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) async {
    activationCount++;
    lastReplaceBookId = replaceBookId;
    if (idempotent) {
      final current = snapshots.single;
      for (final key in portableBackupEntityKeys) {
        final target = List<Map<String, Object?>>.of(current[key] ?? const []);
        current[key] = target;
        for (final row in snapshot[key] ?? const []) {
          final identity = RestoreClassifier.identity(key, row);
          final existing = target.where(
            (item) => RestoreClassifier.identity(key, item) == identity,
          );
          if (existing.isEmpty) {
            target.add(Map<String, Object?>.of(row));
          } else if (!RestoreClassifier.sameRecord(existing.single, row)) {
            throw StateError('Restore conflict.');
          }
        }
      }
      return;
    }
    if (replaceBookId != null) {
      snapshots.removeWhere(
        (item) => item['household']!.single['id'] == replaceBookId,
      );
    }
    snapshots.add(snapshot);
  }

  @override
  Future<List<Map<String, Object?>>> localHouseholds() async => [
    for (final snapshot in snapshots) snapshot['household']!.single,
  ];

  @override
  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    String bookId,
  ) async {
    return snapshots.firstWhere(
      (item) => item['household']!.single['id'] == bookId,
    );
  }
}

Map<String, int> _counts(Map<String, List<Map<String, Object?>>> snapshot) => {
  for (final entry in snapshot.entries) entry.key: entry.value.length,
};
