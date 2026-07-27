import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/local_profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'fresh database uses final schema with account and profile fields',
    () async {
      final fixture = await _Fixture.create('fresh');
      addTearDown(fixture.dispose);
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);

      expect(await store.db.getVersion(), LocalStore.schemaVersion);
      expect(
        await _columns(store.db, 'accounts'),
        containsAll([
          'currency_code',
          'opening_balance',
          'opening_balance_date',
        ]),
      );
      expect(
        await _tables(store.db),
        containsAll(['local_profiles', 'local_session']),
      );
      expect(await store.getLocalProfiles(), isEmpty);
    },
  );

  test(
    'v10 migration preserves rows and creates safe legacy profile',
    () async {
      final fixture = await _Fixture.create('migration-v10');
      addTearDown(fixture.dispose);
      await _createV10Database(fixture.path);

      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);

      final accounts = await store.getAccounts();
      expect(accounts, hasLength(1));
      expect(accounts.single['id'], 'existing-account');
      expect(accounts.single['name'], 'Existing Cash');
      expect(accounts.single['currency_code'], 'IDR');
      expect(accounts.single['opening_balance'], 0);
      expect(accounts.single['opening_balance_date'], isNull);
      expect(
        (await store.db.query('transactions')).single['id'],
        'existing-transaction',
      );
      expect(
        (await store.db.query('asset_definitions')).single['id'],
        'existing-asset',
      );
      final profile = await store.getActiveLocalProfile();
      expect(profile?['display_name'], 'Local User');
      expect(profile?['default_currency_code'], 'IDR');
      expect((await store.getLocalSession())?['onboarding_completed'], 1);
    },
  );

  test('native account and profile survive close and reopen', () async {
    final fixture = await _Fixture.create('round-trip');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    final account = Account(
      id: 'round-trip-account',
      name: 'USD Wallet',
      accountType: AccountType.eWallet,
      currencyCode: 'USD',
      openingBalance: -250,
      openingBalanceDate: DateTime(2026, 7, 20),
    );
    final profile = LocalProfile(
      id: 'round-trip-profile',
      displayName: 'Enos',
      defaultCurrencyCode: 'USD',
    );
    await store.upsertAccount(account.toRecord());
    await store.upsertLocalProfile(profile.toRecord());
    await store.saveLocalSession(
      activeProfileId: profile.id,
      onboardingCompleted: true,
    );
    await store.close();

    final reopened = LocalStore(databasePath: fixture.path);
    await reopened.initialize();
    addTearDown(reopened.close);
    final restored = Account.fromRecord((await reopened.getAccounts()).single);
    expect(restored.id, account.id);
    expect(restored.openingBalance, -250);
    expect(restored.openingBalanceDate, account.openingBalanceDate);
    expect(
      LocalProfile.fromRecord(
        (await reopened.getActiveLocalProfile())!,
      ).defaultCurrencyCode,
      'USD',
    );
    expect((await reopened.getLocalSession())?['onboarding_completed'], 1);
  });

  test('opening balance removal persists zero and null date', () async {
    final fixture = await _Fixture.create('remove-opening');
    addTearDown(fixture.dispose);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    final account = Account(
      id: 'remove-opening-account',
      name: 'Cash',
      openingBalance: 100,
      openingBalanceDate: DateTime(2026, 7, 1),
    );
    await store.upsertAccount(account.toRecord());
    await store.upsertAccount(
      account.copyWith(openingBalance: 0, openingBalanceDate: null).toRecord(),
    );
    final restored = Account.fromRecord((await store.getAccounts()).single);
    expect(restored.openingBalance, 0);
    expect(restored.openingBalanceDate, isNull);
  });

  test(
    'account seeding is idempotent and rejects active duplicate names',
    () async {
      final fixture = await _Fixture.create('idempotent');
      addTearDown(fixture.dispose);
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      await store.ensureAccountSeeds(const ['Cash', 'Bank']);
      await store.ensureAccountSeeds(const ['Cash', 'Bank']);
      expect(await store.getAccounts(), hasLength(2));
      await expectLater(
        store.upsertAccount(Account(name: ' cash ').toRecord()),
        throwsStateError,
      );
    },
  );

  test('web store has structured account and local-profile parity', () async {
    final store = web.LocalStore(databasePath: 'beta01-web-parity');
    await store.initialize();
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final account = Account(
      id: 'web-account-$suffix',
      name: 'Web Cash $suffix',
      openingBalance: 0,
      openingBalanceDate: DateTime(2026, 7, 26),
    );
    final profile = LocalProfile(
      id: 'web-profile-$suffix',
      displayName: 'Web User',
      defaultCurrencyCode: 'SGD',
    );
    await store.upsertAccount(account.toRecord());
    await store.upsertLocalProfile(profile.toRecord());
    await store.saveLocalSession(
      activeProfileId: profile.id,
      onboardingCompleted: true,
    );

    final restored = (await store.getAccounts()).firstWhere(
      (record) => record['id'] == account.id,
    );
    expect(Account.fromRecord(restored).hasOpeningBalance, isTrue);
    expect((await store.getActiveLocalProfile())?['id'], profile.id);
    expect((await store.getLocalSession())?['onboarding_completed'], 1);
  });
}

Future<Set<String>> _columns(Database database, String table) async {
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

Future<Set<String>> _tables(Database database) async {
  final rows = await database.query(
    'sqlite_master',
    columns: ['name'],
    where: "type = 'table'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<void> _createV10Database(String path) async {
  final database = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 10,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL,
            account_type TEXT NOT NULL DEFAULT 'asset',
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
            deleted_at INTEGER, version INTEGER NOT NULL DEFAULT 1,
            device_id TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'local_only'
          )
        ''');
        await database.execute(
          'CREATE TABLE transactions (id TEXT PRIMARY KEY, title TEXT)',
        );
        await database.execute(
          'CREATE TABLE asset_definitions (id TEXT PRIMARY KEY, display_name TEXT)',
        );
        await database.insert('accounts', {
          'id': 'existing-account',
          'name': 'Existing Cash',
          'account_type': 'asset',
          'created_at': 1,
          'updated_at': 2,
          'version': 3,
          'device_id': 'device',
          'sync_status': 'pending',
        });
        await database.insert('transactions', {
          'id': 'existing-transaction',
          'title': 'Preserved',
        });
        await database.insert('asset_definitions', {
          'id': 'existing-asset',
          'display_name': 'Preserved asset',
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
    final directory = await Directory.systemTemp.createTemp('beta01-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
