import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/beta06_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v19 migration preserves prices and scopes identical keys by book',
    () async {
      final fixture = await _Fixture.create('beta06-v19');
      addTearDown(fixture.dispose);
      final old = await databaseFactoryFfi.openDatabase(
        fixture.path,
        options: OpenDatabaseOptions(version: 19, onCreate: _createV19),
      );
      await old.close();

      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      expect(await store.db.getVersion(), 20);
      expect(
        (await store.db.query('asset_market_prices')).single['price_minor'],
        1000000,
      );
      await store.db.insert('books', _book('book-two', 'Second'));
      await store.db.insert('asset_market_prices', {
        ..._price('book-two'),
        'price_minor': 2000000,
      });
      expect(
        await store.db.query(
          'asset_market_prices',
          where: 'asset_key = ?',
          whereArgs: ['gold'],
        ),
        hasLength(2),
      );
    },
  );

  test('restore is atomic and leaves unrelated households untouched', () async {
    final fixture = await _Fixture.create('beta06-restore');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);

    final first = HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot());
    await store.activateHouseholdBackupSnapshot(first);
    final second = HouseholdBackupIntegrity.prepareForRestore(
      beta06Snapshot(bookId: 'book-other', bookName: 'Other Household'),
      remapAsCopy: true,
    );
    await store.activateHouseholdBackupSnapshot(second);
    final otherId = second['household']!.single['id'] as String;

    await store.activateHouseholdBackupSnapshot(
      first,
      replaceBookId: 'book-beta06',
    );
    final books = await store.getFinancialBooks(includeDeleted: true);
    expect(
      books.map((book) => book['id']),
      containsAll(['book-beta06', otherId]),
    );
    expect(await store.createHouseholdBackupSnapshot(otherId), isNotEmpty);
    final scoped = await store.createHouseholdBackupSnapshot('book-beta06');
    for (final entry in scoped.entries.where(
      (entry) => entry.key != 'household',
    )) {
      for (final record in entry.value) {
        if (record.containsKey('book_id')) {
          expect(record['book_id'], 'book-beta06');
        }
      }
    }
    expect(await store.db.query('sync_outbox'), isEmpty);

    final broken = HouseholdBackupIntegrity.prepareForRestore(
      beta06Snapshot(bookId: 'book-broken', bookName: 'Broken'),
      remapAsCopy: true,
    );
    broken['transactions'] = [
      ...broken['transactions']!,
      Map.of(broken['transactions']!.first),
    ];
    await expectLater(
      store.activateHouseholdBackupSnapshot(broken),
      throwsA(anything),
    );
    final brokenId = broken['household']!.single['id'];
    expect(
      (await store.getFinancialBooks(
        includeDeleted: true,
      )).where((book) => book['id'] == brokenId),
      isEmpty,
    );
  });

  test(
    'idempotent restore skips identical rows and creates no outbox',
    () async {
      final fixture = await _Fixture.create('beta07-idempotent');
      addTearDown(fixture.dispose);
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      final snapshot = HouseholdBackupIntegrity.prepareForRestore(
        beta06Snapshot(),
      );

      await store.activateHouseholdBackupSnapshot(snapshot);
      final before = await store.createHouseholdBackupSnapshot('book-beta06');
      await store.activateHouseholdBackupSnapshot(snapshot, idempotent: true);
      final after = await store.createHouseholdBackupSnapshot('book-beta06');

      expect(
        {for (final entry in after.entries) entry.key: entry.value.length},
        {for (final entry in before.entries) entry.key: entry.value.length},
      );
      expect(await store.db.query('sync_outbox'), isEmpty);
    },
  );

  test('transactional restore conflict leaves every row unchanged', () async {
    final fixture = await _Fixture.create('beta07-conflict');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    final snapshot = HouseholdBackupIntegrity.prepareForRestore(
      beta06Snapshot(),
    );
    await store.activateHouseholdBackupSnapshot(snapshot);
    final conflicting = {
      for (final entry in snapshot.entries)
        entry.key: entry.value.map(Map<String, Object?>.of).toList(),
    };
    conflicting['transactions']!.first['amount_minor'] = 999;
    final before = await store.createHouseholdBackupSnapshot('book-beta06');

    await expectLater(
      store.activateHouseholdBackupSnapshot(conflicting, idempotent: true),
      throwsA(anything),
    );
    expect(await store.createHouseholdBackupSnapshot('book-beta06'), before);
  });

  test(
    'reopening a restored database preserves data without new sync',
    () async {
      final fixture = await _Fixture.create('beta06-reopen');
      addTearDown(fixture.dispose);
      final firstStore = LocalStore(databasePath: fixture.path);
      await firstStore.initialize();
      await firstStore.activateHouseholdBackupSnapshot(
        HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot()),
      );
      await firstStore.close();

      final reopened = LocalStore(databasePath: fixture.path);
      await reopened.initialize();
      addTearDown(reopened.close);
      final snapshot = await reopened.createHouseholdBackupSnapshot(
        'book-beta06',
      );

      expect(snapshot['transactions'], hasLength(2));
      expect(await reopened.db.query('sync_outbox'), isEmpty);
    },
  );

  test(
    'reference diagnostics distinguish missing, deleted, and cross-book',
    () {
      final missing = beta06Snapshot();
      missing['transactions']!.first['category'] = 'Removed category';
      expect(
        HouseholdBackupIntegrity.referenceIssues(missing).single.severity,
        ReferenceIssueSeverity.warning,
      );
      HouseholdBackupIntegrity.validate(missing);

      missing['categories']!.add({
        ...missing['categories']!.first,
        'id': 'category-restored',
        'name': 'Removed category',
      });
      expect(HouseholdBackupIntegrity.referenceIssues(missing), isEmpty);

      final deleted = beta06Snapshot();
      deleted['categories']!.first['deleted_at'] = 2;
      final deletedIssue = HouseholdBackupIntegrity.referenceIssues(
        deleted,
      ).single;
      expect(deletedIssue.state, ReferenceState.softDeleted);
      expect(deletedIssue.severity, ReferenceIssueSeverity.information);
      HouseholdBackupIntegrity.validate(deleted);

      final crossBook = beta06Snapshot();
      crossBook['categories']!.first['book_id'] = 'another-book';
      expect(
        HouseholdBackupIntegrity.referenceIssues(crossBook).single.severity,
        ReferenceIssueSeverity.fatal,
      );
    },
  );
}

Future<void> _createV19(Database db, int version) async {
  await db.execute('''
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      base_currency_code TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER,
      version INTEGER NOT NULL,
      device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      remote_linked_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE asset_market_prices (
      asset_key TEXT PRIMARY KEY,
      book_id TEXT,
      symbol TEXT,
      price_minor INTEGER NOT NULL,
      minor_unit_scale INTEGER NOT NULL DEFAULT 1,
      currency_code TEXT NOT NULL,
      unit TEXT NOT NULL,
      quoted_at INTEGER NOT NULL,
      source TEXT NOT NULL,
      is_delayed INTEGER NOT NULL DEFAULT 0,
      is_manual INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.insert('books', _book('book-one', 'First'));
  await db.insert('asset_market_prices', _price('book-one'));
}

Map<String, Object?> _book(String id, String name) => {
  'id': id,
  'name': name,
  'base_currency_code': 'IDR',
  'created_at': 1,
  'updated_at': 1,
  'deleted_at': null,
  'version': 1,
  'device_id': 'test',
  'sync_status': 'local_only',
  'remote_linked_at': null,
};

Map<String, Object?> _price(String bookId) => {
  'asset_key': 'gold',
  'book_id': bookId,
  'symbol': 'XAU',
  'price_minor': 1000000,
  'minor_unit_scale': 1,
  'currency_code': 'IDR',
  'unit': 'gram',
  'quoted_at': 1,
  'source': 'manual',
  'is_delayed': 0,
  'is_manual': 1,
  'updated_at': 1,
};

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('$name-');
    return _Fixture(directory, p.join(directory.path, 'pilgrim_tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
