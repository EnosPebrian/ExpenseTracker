import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v12 migration adds nullable remote authorization columns', () async {
    final fixture = await _Fixture.create('migration');
    addTearDown(fixture.dispose);
    await _createV12Database(fixture.path);

    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);

    expect(await store.db.getVersion(), LocalStore.schemaVersion);
    final bookColumns = await store.db.rawQuery('PRAGMA table_info(books)');
    final memberColumns = await store.db.rawQuery(
      'PRAGMA table_info(household_members)',
    );
    expect(bookColumns.map((row) => row['name']), contains('remote_linked_at'));
    expect(memberColumns.map((row) => row['name']), contains('auth_user_id'));
    expect((await store.db.query('books')).single['remote_linked_at'], isNull);
    expect(
      (await store.db.query('household_members')).single['auth_user_id'],
      isNull,
    );
  });

  test('remote link metadata and local finance survive reopen', () async {
    final fixture = await _Fixture.create('roundtrip');
    addTearDown(fixture.dispose);
    final linkedAt = DateTime.utc(2026, 7, 26, 8, 30);
    final book = FinancialBook(
      id: 'book',
      name: 'Enos & Grace',
      remoteLinkedAt: linkedAt,
    );
    final member = HouseholdMember(
      id: 'enos',
      bookId: book.id,
      displayName: 'Enos',
      role: HouseholdMemberRole.owner,
      authUserId: 'auth-user',
    );
    final account = Account(
      id: 'cash',
      bookId: book.id,
      ownerMemberId: member.id,
      name: 'Cash Enos',
      openingBalance: 250000,
    );

    var store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    await store.upsertFinancialBook(book.toRecord());
    store.setActiveBookId(book.id);
    await store.upsertHouseholdMember(member.toRecord());
    await store.upsertAccount(account.toRecord());
    await store.close();

    store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    store.setActiveBookId(book.id);
    addTearDown(store.close);

    final restoredBook = FinancialBook.fromRecord(
      (await store.getFinancialBooks()).single,
    );
    final restoredMember = HouseholdMember.fromRecord(
      (await store.getHouseholdMembers()).single,
    );
    final restoredAccount = Account.fromRecord(
      (await store.getAccounts()).single,
    );
    expect(
      restoredBook.remoteLinkedAt?.millisecondsSinceEpoch,
      linkedAt.millisecondsSinceEpoch,
    );
    expect(restoredMember.authUserId, 'auth-user');
    expect(restoredAccount.name, 'Cash Enos');
    expect(restoredAccount.openingBalance, 250000);
  });

  test('web store preserves remote authorization metadata', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final store = web.LocalStore(databasePath: 'beta03-$suffix');
    final linkedAt = DateTime(2026, 7, 26);
    final book = FinancialBook(
      id: 'web-book-$suffix',
      name: 'Web household',
      remoteLinkedAt: linkedAt,
    );
    final member = HouseholdMember(
      id: 'web-member-$suffix',
      bookId: book.id,
      displayName: 'Grace',
      authUserId: 'web-auth-user',
    );
    await store.upsertFinancialBook(book.toRecord());
    store.setActiveBookId(book.id);
    await store.upsertHouseholdMember(member.toRecord());

    final restoredBook = FinancialBook.fromRecord(
      (await store.getFinancialBooks()).singleWhere(
        (record) => record['id'] == book.id,
      ),
    );
    final restoredMember = HouseholdMember.fromRecord(
      (await store.getHouseholdMembers()).singleWhere(
        (record) => record['id'] == member.id,
      ),
    );
    expect(
      restoredBook.remoteLinkedAt?.millisecondsSinceEpoch,
      linkedAt.millisecondsSinceEpoch,
    );
    expect(restoredMember.authUserId, 'web-auth-user');
  });
}

Future<void> _createV12Database(String path) async {
  final database = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 12,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            base_currency_code TEXT NOT NULL DEFAULT 'IDR',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            version INTEGER NOT NULL DEFAULT 1,
            device_id TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'local_only'
          )
        ''');
        await db.execute('''
          CREATE TABLE household_members (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'member',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            version INTEGER NOT NULL DEFAULT 1,
            device_id TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'local_only'
          )
        ''');
        await db.insert('books', {
          'id': 'book',
          'name': 'Existing household',
          'created_at': 1,
          'updated_at': 1,
          'device_id': 'device',
        });
        await db.insert('household_members', {
          'id': 'member',
          'book_id': 'book',
          'display_name': 'Enos',
          'role': 'owner',
          'created_at': 1,
          'updated_at': 1,
          'device_id': 'device',
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
    final directory = await Directory.systemTemp.createTemp('beta03-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
