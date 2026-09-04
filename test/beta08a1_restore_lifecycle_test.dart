import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/restore_lifecycle_service.dart';
import 'package:pilgrim_tracker/features/backup/presentation/controllers/restore_lifecycle_controller.dart';
import 'package:pilgrim_tracker/features/backup/presentation/widgets/restore_lifecycle_panel.dart';

import 'support/beta06_fixture.dart';

void main() {
  group('BETA-08A1 restore lifecycle clone', () {
    test(
      'preview validates a completed restored local-only household',
      () async {
        final store = _MemoryStore(_restoredSnapshot());
        final preview = await RestoreLifecycleService(
          store,
        ).preview('book-beta06');

        expect(preview.householdName, 'Beta Household');
        expect(preview.baseCurrencyCode, 'IDR');
        expect(preview.entityCounts['transactions'], 2);
        expect(preview.entityCounts['budgets'], 1);
        expect(preview.recordCount, greaterThan(0));
      },
    );

    test(
      'clone remaps every supported identity and preserves source',
      () async {
        final source = _restoredSnapshot();
        final original = _copy(source);
        final store = _MemoryStore(source);
        final clone = await RestoreLifecycleService(store)
            .cloneForNewSharedHousehold(
              sourceBookId: 'book-beta06',
              proposedName: 'Recovered Family',
            );

        expect(clone.book.id, isNot('book-beta06'));
        expect(clone.book.name, 'Recovered Family');
        expect(clone.book.remoteLinkedAt, isNull);
        expect(clone.owner.authUserId, isNull);
        expect(store.data['book-beta06'], original);

        final copied = store.data[clone.book.id]!;
        for (final entry in copied.entries) {
          if (entry.key == 'household') continue;
          for (final record in entry.value) {
            expect(record['book_id'], clone.book.id, reason: entry.key);
          }
        }

        final memberIds = _ids(copied['members']);
        final accountIds = _ids(copied['accounts']);
        final categoryIds = _ids(copied['categories']);
        final projectIds = _ids(copied['projects']);
        final transactionIds = _ids(copied['transactions']);
        final definitionIds = _ids(copied['asset_definitions']);
        expect(memberIds.intersection({'member-owner'}), isEmpty);
        expect(accountIds.intersection({'account-cash'}), isEmpty);
        expect(
          categoryIds.intersection({'category-income', 'category-expense'}),
          isEmpty,
        );
        expect(projectIds.intersection({'project-home'}), isEmpty);
        expect(
          transactionIds.intersection({
            'transaction-income',
            'transaction-expense',
          }),
          isEmpty,
        );
        expect(definitionIds.intersection({'asset-gold'}), isEmpty);

        expect(copied['accounts']!.single['owner_member_id'], isIn(memberIds));
        for (final row in copied['transactions']!) {
          expect(row['entered_by_member_id'], isIn(memberIds));
          expect(row['project_id'], isIn(projectIds));
          if (row['related_transaction_id'] != null) {
            expect(row['related_transaction_id'], isIn(transactionIds));
          }
          if (row['asset_definition_id'] != null) {
            expect(row['asset_definition_id'], isIn(definitionIds));
          }
        }
        expect(copied['budgets']!.single['category_id'], isIn(categoryIds));
        expect(
          copied['manual_market_prices']!.single['asset_key'],
          isIn(definitionIds),
        );
        HouseholdBackupIntegrity.validate(copied);
      },
    );

    test('new-share bootstrap always receives a fresh household ID', () async {
      final store = _MemoryStore(_restoredSnapshot());
      String? bootstrappedBookId;
      final controller = RestoreLifecycleController(
        service: RestoreLifecycleService(store),
        bootstrapCloud: (clone) async => bootstrappedBookId = clone.book.id,
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');

      await controller.createNewSharedHousehold('Separate Recovery');

      expect(bootstrappedBookId, isNotNull);
      expect(bootstrappedBookId, isNot('book-beta06'));
      expect(store.data, contains('book-beta06'));
      expect(store.data, contains(bootstrappedBookId));
      expect(controller.error, isNull);
    });

    test(
      'bootstrap failure cannot alter the original restored snapshot',
      () async {
        final source = _restoredSnapshot();
        final before = _copy(source);
        final store = _MemoryStore(source);
        final controller = RestoreLifecycleController(
          service: RestoreLifecycleService(store),
          bootstrapCloud: (_) async => throw StateError('remote unavailable'),
        );
        addTearDown(controller.dispose);
        await controller.load('book-beta06');

        await controller.createNewSharedHousehold('Failed Recovery');

        expect(controller.error, contains('remote unavailable'));
        expect(store.data['book-beta06'], before);
        expect(
          store.data.length,
          2,
          reason: 'only the protected local clone may remain',
        );
      },
    );
  });

  group('BETA-08A1 restore lifecycle UI', () {
    testWidgets('restored local household exposes all three destinations', (
      tester,
    ) async {
      final controller = RestoreLifecycleController(
        service: RestoreLifecycleService(_MemoryStore(_restoredSnapshot())),
        bootstrapCloud: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestoreLifecyclePanel(
              controller: controller,
              bookId: 'book-beta06',
              authenticatedEmail: 'owner@example.com',
              onReconnect: () {},
              onRecoverMissing: () {},
            ),
          ),
        ),
      );

      expect(find.text('Keep local only'), findsOneWidget);
      expect(find.text('Create new shared household'), findsOneWidget);
      expect(find.text('Reconnect existing shared household'), findsOneWidget);
      expect(find.text('Recover missing records'), findsOneWidget);
      await tester.tap(find.byKey(const Key('restore-keep-local')));
      await tester.pump();
      expect(
        find.text('This restored household will remain local-only.'),
        findsOneWidget,
      );
    });

    testWidgets('ordinary or synchronized household hides restore controls', (
      tester,
    ) async {
      final store = _MemoryStore(beta06Snapshot());
      final controller = RestoreLifecycleController(
        service: RestoreLifecycleService(store),
        bootstrapCloud: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');

      await tester.pumpWidget(
        MaterialApp(
          home: RestoreLifecyclePanel(
            controller: controller,
            bookId: 'book-beta06',
          ),
        ),
      );

      expect(find.byKey(const Key('restore-lifecycle-panel')), findsNothing);
    });
  });
}

Map<String, List<Map<String, Object?>>> _restoredSnapshot() {
  final snapshot = HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot());
  snapshot['transactions']![1] = {
    ...snapshot['transactions']![1],
    'related_transaction_id': 'transaction-income',
    'asset_definition_id': 'asset-gold',
  };
  snapshot['budgets'] = [
    {
      'id': 'budget-groceries',
      'book_id': 'book-beta06',
      'category_id': 'category-expense',
      'month_start': '2026-07-01',
      'limit_minor': 700000,
      'currency_code': 'IDR',
      'note': null,
      'created_at': 1767225600000,
      'updated_at': 1767225600000,
      'deleted_at': null,
      'version': 1,
      'device_id': 'restore-device',
      'sync_status': 'local_only',
    },
  ];
  return snapshot;
}

Set<String> _ids(List<Map<String, Object?>>? records) => {
  for (final record in records ?? const []) record['id'] as String,
};

Map<String, List<Map<String, Object?>>> _copy(
  Map<String, List<Map<String, Object?>>> source,
) => {
  for (final entry in source.entries)
    entry.key: entry.value.map(Map<String, Object?>.of).toList(),
};

class _MemoryStore implements HouseholdBackupStore {
  _MemoryStore(Map<String, List<Map<String, Object?>>> source)
    : data = {source['household']!.single['id'] as String: _copy(source)};

  final Map<String, Map<String, List<Map<String, Object?>>>> data;

  @override
  int get schemaVersion => 21;

  @override
  Future<void> activate(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) async {
    final id = snapshot['household']!.single['id'] as String;
    if (data.containsKey(id)) throw StateError('duplicate household');
    data[id] = _copy(snapshot);
  }

  @override
  Future<List<Map<String, Object?>>> localHouseholds() async => [
    for (final snapshot in data.values)
      Map<String, Object?>.of(snapshot['household']!.single),
  ];

  @override
  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    String bookId,
  ) async => _copy(data[bookId]!);
}
