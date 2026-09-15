import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/investments/domain/entities/brokerage_settlement.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'support/beta06_fixture.dart';

void main() {
  test(
    'SQLite v28 upgrade adds evidence storage without changing financial rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'settlement-upgrade-',
      );
      final store = native.LocalStore(
        databasePath: '${directory.path}/test.db',
      );
      await store.initialize();
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final snapshot = beta06Snapshot(bookId: 'upgrade');
      await store.activateHouseholdBackupSnapshot(
        HouseholdBackupIntegrity.prepareForRestore(snapshot),
      );
      final before = await store.getTransactions();
      await store.db.execute('DROP TABLE brokerage_settlements');
      await store.db.execute('PRAGMA user_version = 28');
      await store.close();
      await store.initialize();
      store.setActiveBookId('upgrade');
      expect(await store.getSchemaVersion(), 29);
      expect(await store.getTransactions(), before);
      expect(await store.getBrokerageSettlements(), isEmpty);
    },
  );
  for (final platform in ['native', 'web']) {
    test(
      '$platform settlement persistence is atomic, scoped and restart safe',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'settlement-test-',
        );
        final dynamic store = platform == 'native'
            ? native.LocalStore(databasePath: '${directory.path}/test.db')
            : web.LocalStore();
        await store.initialize();
        addTearDown(() async {
          await store.close();
          await directory.delete(recursive: true);
        });
        final book = 'settlement-$platform';
        final snapshot = beta06Snapshot(bookId: book)..['transactions'] = [];
        await store.activateHouseholdBackupSnapshot(
          HouseholdBackupIntegrity.prepareForRestore(snapshot),
          replaceBookId: book,
        );
        final broker = Account(
          id: 'broker-$platform',
          bookId: book,
          name: 'Broker',
          accountType: AccountType.brokerage,
          currencyCode: 'IDR',
        );
        await store.upsertAccount(broker.toRecord(), enqueueSync: false);
        if (platform == 'native') {
          await store.db.update(
            'books',
            {'remote_linked_at': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?',
            whereArgs: [book],
          );
          await store.setSyncInitializationState(book, 'ready');
        }
        final now = DateTime(2026, 9, 15);
        final evidence = BrokerageSettlement(
          id: 'settlement-$platform',
          bookId: book,
          brokerageAccountId: broker.id,
          date: now,
          type: BrokerageSettlementType.buySettlement,
          amount: 100,
          currencyCode: 'IDR',
          sourceFingerprint: 'source',
          sourceRowIdentity: 'row-1',
          sourceRowFingerprint: 'fingerprint',
          reference: 'RDN',
          note: 'source note',
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
        );
        final row = evidence.toRecord();
        await expectLater(
          store.insertInvestmentImportAtomic(
            transactions: <Map<String, Object?>>[],
            assetDefinitions: <Map<String, Object?>>[],
            transferLinks: <Map<String, Object?>>[],
            settlements: [row, row],
          ),
          throwsA(anything),
        );
        expect(await store.getBrokerageSettlements(), isEmpty);
        expect(await store.getTransactions(), isEmpty);
        await store.insertInvestmentImportAtomic(
          transactions: <Map<String, Object?>>[],
          assetDefinitions: <Map<String, Object?>>[],
          transferLinks: <Map<String, Object?>>[],
          settlements: [row],
        );
        expect(await store.getBrokerageSettlements(), hasLength(1));
        final count = await store.getPendingSyncCount(book);
        if (platform == 'native') expect(count, 1);
        await expectLater(
          store.insertInvestmentImportAtomic(
            transactions: <Map<String, Object?>>[],
            assetDefinitions: <Map<String, Object?>>[],
            transferLinks: <Map<String, Object?>>[],
            settlements: [row],
          ),
          throwsA(anything),
        );
        expect(await store.getPendingSyncCount(book), count);
        expect(await store.getTransactions(), isEmpty);
        await store.close();
        await store.initialize();
        store.setActiveBookId(book);
        final restored = BrokerageSettlement.fromRecord(
          (await store.getBrokerageSettlements()).single
              as Map<String, Object?>,
        );
        expect(restored.state, 'unmatched');
        expect(restored.note, 'source note');
        expect(restored.reference, 'RDN');
        await store.applyRemoteSyncBatch(
          book,
          changes: <Map<String, Object?>>[
            {
              'entity_type': 'brokerage_settlements',
              'entity_id': row['id'],
              'payload': {...row, 'version': 2},
            },
          ],
          finalSequence: 1,
        );
        expect(await store.getPendingSyncCount(book), count);
        expect(await store.getTransactions(), isEmpty);
        expect((await store.getBrokerageSettlements()).single['version'], 2);
        final Map<String, List<Map<String, Object?>>> backupSnapshot =
            await store.createHouseholdBackupSnapshot(book);
        HouseholdBackupIntegrity.validate(backupSnapshot);
        final codec = PortableBackupCodec(
          databaseSchemaVersion: native.LocalStore.schemaVersion,
        );
        final encoded = await codec.encode(
          snapshot: backupSnapshot,
          password: 'synthetic-test-password',
        );
        expect(encoded.manifest.formatVersion, 8);
        final decoded = await codec.decode(
          encoded.bytes,
          'synthetic-test-password',
        );
        expect(decoded.snapshot['brokerage_settlements'], hasLength(1));
        final clone = HouseholdBackupIntegrity.prepareForRestore(
          decoded.snapshot,
          remapAsCopy: true,
        );
        HouseholdBackupIntegrity.validate(clone);
        expect(clone['brokerage_settlements']!.single['book_id'], isNot(book));
        expect(
          clone['brokerage_settlements']!.single['brokerage_account_id'],
          isNot(broker.id),
        );
        expect(
          clone['brokerage_settlements']!.single['source_fingerprint'],
          'source',
        );
        await expectLater(
          store.reconcileBrokerageSettlement({
            ...row,
            'trade_ids_json': '["missing-trade"]',
          }, expectedVersion: 2),
          throwsStateError,
        );
        expect(
          BrokerageSettlement.fromRecord(
            (await store.getBrokerageSettlements()).single
                as Map<String, Object?>,
          ).state,
          'unmatched',
        );
        store.setActiveBookId('other');
        expect(await store.getBrokerageSettlements(), isEmpty);
      },
    );
  }
}
