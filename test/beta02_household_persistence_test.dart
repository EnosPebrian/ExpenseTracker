import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/local_profile.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('book and member entity mappings preserve sync-ready metadata', () {
    final created = DateTime(2026, 7, 1);
    final book = FinancialBook(
      id: 'book-1',
      name: 'Enos & Grace',
      baseCurrencyCode: 'idr',
      createdAt: created,
      updatedAt: created,
      version: 3,
      deviceId: 'device-a',
      syncStatus: 'pending',
    );
    final member = HouseholdMember(
      id: 'member-1',
      bookId: book.id,
      displayName: 'Enos',
      role: HouseholdMemberRole.owner,
      createdAt: created,
      updatedAt: created,
      version: 2,
      deviceId: 'device-a',
      syncStatus: 'synced',
    );

    expect(FinancialBook.fromRecord(book.toRecord()).baseCurrencyCode, 'IDR');
    final restoredMember = HouseholdMember.fromRecord(member.toRecord());
    expect(restoredMember.bookId, book.id);
    expect(restoredMember.role, HouseholdMemberRole.owner);
    expect(restoredMember.version, 2);
  });

  test('profile bootstrap creates one owner and remains idempotent', () async {
    final fixture = await _Fixture.create('bootstrap');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    final profile = LocalProfile(
      id: 'profile-enos',
      displayName: 'Enos',
      defaultCurrencyCode: 'SGD',
    );
    await store.upsertLocalProfile(profile.toRecord());
    await store.saveLocalSession(
      activeProfileId: profile.id,
      onboardingCompleted: true,
    );

    await store.ensureHouseholdForProfile(profile.toRecord());
    await store.ensureHouseholdForProfile(profile.toRecord());

    final books = await store.getFinancialBooks();
    final members = await store.getHouseholdMembers();
    final session = await store.getLocalSession();
    expect(books, hasLength(1));
    expect(books.single['name'], 'My Household');
    expect(books.single['base_currency_code'], 'SGD');
    expect(members, hasLength(1));
    expect(members.single['display_name'], 'Enos');
    expect(members.single['role'], 'owner');
    expect(session?['active_book_id'], books.single['id']);
    expect(session?['active_member_id'], members.single['id']);
  });

  test('v11 migration attaches legacy rows and survives reopen', () async {
    final fixture = await _Fixture.create('migration');
    addTearDown(fixture.dispose);
    await _createV11Database(fixture.path);

    var store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    expect(await store.db.getVersion(), LocalStore.schemaVersion);
    final books = await store.getFinancialBooks();
    final members = await store.getHouseholdMembers();
    expect(books, hasLength(1));
    expect(books.single['base_currency_code'], 'IDR');
    expect(members, hasLength(1));
    expect(members.single['display_name'], 'Enos');
    final bookId = books.single['id'];
    for (final table in const [
      'accounts',
      'categories',
      'projects',
      'transactions',
      'asset_definitions',
      'asset_market_prices',
    ]) {
      expect((await store.db.query(table)).single['book_id'], bookId);
    }
    await store.close();

    store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    expect(await store.getFinancialBooks(), hasLength(1));
    expect(await store.getHouseholdMembers(), hasLength(1));
  });

  test(
    'member rules, ownership, attribution, and active member persist',
    () async {
      final fixture = await _Fixture.create('members');
      addTearDown(fixture.dispose);
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      final profile = LocalProfile(id: 'p', displayName: 'Enos');
      await store.upsertLocalProfile(profile.toRecord());
      await store.saveLocalSession(
        activeProfileId: profile.id,
        onboardingCompleted: true,
      );
      await store.ensureHouseholdForProfile(profile.toRecord());
      final bookId = store.activeBookId!;
      final grace = HouseholdMember(
        id: 'grace',
        bookId: bookId,
        displayName: 'Grace',
      );
      await store.upsertHouseholdMember(grace.toRecord());
      await expectLater(
        store.upsertHouseholdMember(
          HouseholdMember(bookId: bookId, displayName: ' grace ').toRecord(),
        ),
        throwsStateError,
      );
      final renamed = grace.copyWith(displayName: 'Grace Pebrian', version: 2);
      await store.upsertHouseholdMember(renamed.toRecord());
      final account = Account(
        id: 'grace-account',
        bookId: bookId,
        ownerMemberId: grace.id,
        name: 'Grace Cash',
        openingBalance: 250000,
        openingBalanceDate: DateTime(2026, 7, 1),
      );
      await store.upsertAccount(account.toRecord());
      await expectLater(
        store.softDeleteHouseholdMember(grace.id),
        throwsStateError,
      );
      final transaction = Transaction(
        id: 'entered-by-grace',
        bookId: bookId,
        enteredByMemberId: grace.id,
        title: 'Groceries',
        category: 'Konsumsi',
        account: account.name,
        date: DateTime(2026, 7, 2),
        amount: 100000,
        type: TransactionType.expense,
      );
      await store.upsertTransaction(transaction.toRecord());
      await store.saveLocalSession(
        activeProfileId: profile.id,
        onboardingCompleted: true,
        activeBookId: bookId,
        activeMemberId: grace.id,
      );
      await store.close();

      final reopened = LocalStore(databasePath: fixture.path);
      await reopened.initialize();
      reopened.setActiveBookId(bookId);
      addTearDown(reopened.close);
      final restoredAccount = Account.fromRecord(
        (await reopened.getAccounts()).single,
      );
      final restoredTransaction = Transaction.fromRecord(
        (await reopened.getTransactions()).single,
      );
      expect(restoredAccount.id, account.id);
      expect(restoredAccount.ownerMemberId, grace.id);
      expect(restoredAccount.openingBalance, 250000);
      expect(restoredTransaction.enteredByMemberId, grace.id);
      expect((await reopened.getLocalSession())?['active_member_id'], grace.id);
    },
  );

  test('active book scopes records and seeds independently', () async {
    final fixture = await _Fixture.create('scope');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    final now = DateTime(2026, 7, 1);
    for (final id in const ['book-a', 'book-b']) {
      await store.upsertFinancialBook(
        FinancialBook(id: id, name: id).toRecord(),
      );
      store.setActiveBookId(id);
      await store.ensureAccountSeeds(['Cash $id']);
      await store.ensureMasterSeeds('categories', [
        'Food $id',
      ], categoryType: 'expense');
      await store.upsertTransaction(
        Transaction(
          id: 'transaction-$id',
          title: id,
          category: 'Food $id',
          account: 'Cash $id',
          date: now,
          amount: 1,
          type: TransactionType.expense,
        ).toRecord(),
      );
    }

    store.setActiveBookId('book-a');
    expect((await store.getAccounts()).single['name'], 'Cash book-a');
    expect(await store.getMasterNames('categories', categoryType: 'expense'), [
      'Food book-a',
    ]);
    expect((await store.getTransactions()).single['id'], 'transaction-book-a');
    store.setActiveBookId('book-b');
    expect((await store.getAccounts()).single['name'], 'Cash book-b');
    expect(await store.getMasterNames('categories', categoryType: 'expense'), [
      'Food book-b',
    ]);
    expect((await store.getTransactions()).single['id'], 'transaction-book-b');
  });

  test('web store mirrors household, ownership, and scoped behavior', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final store = web.LocalStore(databasePath: 'beta02-$suffix');
    final profile = LocalProfile(
      id: 'web-profile-$suffix',
      displayName: 'Enos Web $suffix',
    );
    await store.upsertLocalProfile(profile.toRecord());
    await store.saveLocalSession(
      activeProfileId: profile.id,
      onboardingCompleted: true,
    );
    await store.ensureHouseholdForProfile(profile.toRecord());
    final bookId = store.activeBookId!;
    final member = HouseholdMember(
      id: 'web-grace-$suffix',
      bookId: bookId,
      displayName: 'Grace Web $suffix',
    );
    await store.upsertHouseholdMember(member.toRecord());
    await store.upsertAccount(
      Account(
        id: 'web-owned-$suffix',
        ownerMemberId: member.id,
        name: 'Web owned $suffix',
      ).toRecord(),
    );
    expect(await store.getFinancialBooks(), isNotEmpty);
    expect(
      (await store.getHouseholdMembers()).any((row) => row['id'] == member.id),
      isTrue,
    );
    expect(
      (await store.getAccounts()).singleWhere(
        (row) => row['id'] == 'web-owned-$suffix',
      )['owner_member_id'],
      member.id,
    );
  });
}

Future<void> _createV11Database(String path) async {
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 11,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE books (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL, device_id TEXT NOT NULL, sync_status TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE accounts (id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, account_type TEXT NOT NULL, currency_code TEXT NOT NULL, opening_balance INTEGER NOT NULL, opening_balance_date INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL, device_id TEXT NOT NULL, sync_status TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE categories (id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, category_type TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL, device_id TEXT NOT NULL, sync_status TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE projects (id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, status TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL, device_id TEXT NOT NULL, sync_status TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE transactions (id TEXT PRIMARY KEY, title TEXT, book_id TEXT)',
        );
        await db.execute(
          'CREATE TABLE asset_definitions (id TEXT PRIMARY KEY, display_name TEXT, book_id TEXT)',
        );
        await db.execute(
          'CREATE TABLE asset_market_prices (asset_key TEXT PRIMARY KEY, book_id TEXT)',
        );
        await db.execute(
          'CREATE TABLE local_profiles (id TEXT PRIMARY KEY, display_name TEXT NOT NULL, default_currency_code TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE local_session (id INTEGER PRIMARY KEY, active_profile_id TEXT, onboarding_completed INTEGER NOT NULL)',
        );
        const common = <String, Object?>{
          'created_at': 1,
          'updated_at': 1,
          'version': 1,
          'device_id': 'old',
          'sync_status': 'synced',
        };
        await db.insert('books', {
          'id': 'existing-book',
          'name': 'Personal',
          ...common,
        });
        await db.insert('accounts', {
          'id': 'a',
          'name': 'Cash',
          'account_type': 'cash',
          'currency_code': 'IDR',
          'opening_balance': 0,
          ...common,
        });
        await db.insert('categories', {
          'id': 'c',
          'name': 'Food',
          'category_type': 'expense',
          ...common,
        });
        await db.insert('projects', {
          'id': 'p',
          'name': 'Life',
          'status': 'active',
          ...common,
        });
        await db.insert('transactions', {'id': 't', 'title': 'Legacy'});
        await db.insert('asset_definitions', {
          'id': 'd',
          'display_name': 'Gold',
        });
        await db.insert('asset_market_prices', {'asset_key': 'd'});
        await db.insert('local_profiles', {
          'id': 'profile',
          'display_name': 'Enos',
          'default_currency_code': 'IDR',
          'created_at': 1,
          'updated_at': 1,
        });
        await db.insert('local_session', {
          'id': 1,
          'active_profile_id': 'profile',
          'onboarding_completed': 1,
        });
      },
    ),
  );
  await db.close();
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta02-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
