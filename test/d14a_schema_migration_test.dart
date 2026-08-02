import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/core/master_data/default_asset_definition_ids.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _currentTransactionColumns = <String>{
  'project_id',
  'quantity',
  'unit',
  'unit_price',
  'asset_definition_id',
  'asset_name',
  'asset_symbol',
  'asset_action',
  'fee_amount',
  'fee_treatment',
  'related_transaction_id',
  'relation_type',
  'market_reference_unit_price',
  'market_reference_currency_code',
  'market_reference_unit',
  'market_reference_source',
  'market_reference_quoted_at',
  'created_at',
  'updated_at',
  'deleted_at',
  'version',
  'device_id',
  'sync_status',
};

const _currentTables = <String>{
  'transactions',
  'books',
  'accounts',
  'categories',
  'projects',
  'asset_definitions',
  'asset_market_prices',
  'local_profiles',
  'local_session',
};

const _currentAccountColumns = <String>{
  'currency_code',
  'opening_balance',
  'opening_balance_date',
};

const _currentIndexes = <String>{
  'idx_transactions_date',
  'idx_transactions_sync',
  'idx_transactions_project',
  'idx_transactions_asset',
  'idx_transactions_asset_definition',
  'idx_transactions_relation',
  'idx_accounts_name',
  'idx_categories_type',
  'idx_projects_name',
  'idx_asset_definitions_name',
  'idx_asset_definitions_symbol',
  'idx_asset_definitions_sync',
};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh final database has the complete schema and indexes', () async {
    final fixture = await _DatabaseFixture.create('d14a-fresh-schema');
    addTearDown(fixture.dispose);

    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    await store.close();

    final database = await fixture.openReadOnly();
    addTearDown(database.close);

    expect(await _userVersion(database), LocalStore.schemaVersion);
    expect(await _objectNames(database, 'table'), containsAll(_currentTables));
    expect(
      await _columnNames(database, 'transactions'),
      containsAll(_currentTransactionColumns),
    );
    expect(
      await _columnNames(database, 'accounts'),
      containsAll(_currentAccountColumns),
    );
    expect(await _objectNames(database, 'index'), containsAll(_currentIndexes));

    for (final table in const [
      'books',
      'accounts',
      'categories',
      'projects',
      'asset_definitions',
      'asset_market_prices',
    ]) {
      expect(await _columnNames(database, table), isNotEmpty, reason: table);
    }
  });

  for (final historicalVersion in const [1, 3, 5, 7, 8, 9, 10]) {
    test(
      'version $historicalVersion upgrades to final version safely',
      () async {
        final fixture = await _DatabaseFixture.create(
          'd14a-migration-v$historicalVersion',
        );
        addTearDown(fixture.dispose);
        await _createHistoricalDatabase(fixture.path, historicalVersion);

        final store = LocalStore(databasePath: fixture.path);
        await store.initialize();
        await store.close();

        final database = await fixture.openReadOnly();
        addTearDown(database.close);

        expect(await _userVersion(database), LocalStore.schemaVersion);
        expect(
          await _objectNames(database, 'table'),
          containsAll(_currentTables),
        );
        expect(
          await _columnNames(database, 'transactions'),
          containsAll(_currentTransactionColumns),
        );
        expect(
          await _columnNames(database, 'accounts'),
          containsAll(_currentAccountColumns),
        );
        expect(
          await _objectNames(database, 'index'),
          containsAll(_currentIndexes),
        );

        final ordinary = (await database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['ordinary-$historicalVersion'],
        )).single;
        expect(ordinary['title'], 'Historical expense');
        expect(ordinary['transaction_date'], _timestamp);
        expect(ordinary['created_at'], _timestamp - 2000);
        expect(ordinary['updated_at'], _timestamp - 1000);
        expect(ordinary['deleted_at'], isNull);
        expect(ordinary['version'], 4);
        expect(ordinary['device_id'], 'historical-device');
        expect(ordinary['sync_status'], 'synced');
        expect(
          ordinary['project_id'],
          historicalVersion >= 2 ? 'project-life' : isNull,
        );
        expect(ordinary['asset_definition_id'], isNull);
        expect(ordinary['fee_amount'], 0);
        expect(ordinary['fee_treatment'], 'none');
        expect(ordinary['related_transaction_id'], isNull);
        expect(ordinary['relation_type'], 'none');
        expect(ordinary['market_reference_unit_price'], isNull);

        final deleted = (await database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['deleted-$historicalVersion'],
        )).single;
        expect(deleted['deleted_at'], _timestamp + 1000);

        if (historicalVersion >= 3) {
          expect(
            (await database.query('projects')).single,
            containsPair('sync_status', 'synced'),
          );
          expect((await database.query('books')).single['name'], 'Personal');
        }

        if (historicalVersion >= 4) {
          final asset = (await database.query(
            'transactions',
            where: 'id = ?',
            whereArgs: ['asset-$historicalVersion'],
          )).single;
          expect(asset['asset_name'], 'US Dollar Cash');
          expect(asset['asset_action'], 'buy');
          expect(
            asset['asset_symbol'],
            historicalVersion >= 5 ? 'USD' : isNull,
          );
          expect(
            asset['asset_definition_id'],
            historicalVersion >= 7 ? defaultUsdAssetId : isNull,
          );
          expect(asset['fee_amount'], historicalVersion >= 8 ? 100000 : 0);
          expect(
            asset['fee_treatment'],
            historicalVersion >= 8 ? 'capitalizeIntoCostBasis' : 'none',
          );
          expect(asset['related_transaction_id'], isNull);
          expect(asset['relation_type'], 'none');
          expect(
            asset['market_reference_unit_price'],
            historicalVersion >= 10 ? 16300 : isNull,
          );
        }

        if (historicalVersion >= 5) {
          expect(
            (await database.query('asset_market_prices')).single['price_minor'],
            16450,
          );
        }

        if (historicalVersion >= 6) {
          final definition = (await database.query('asset_definitions')).single;
          expect(definition['id'], defaultUsdAssetId);
          expect(definition['provider_symbol'], 'USD/IDR');
          expect(definition['version'], 3);
          expect(definition['sync_status'], 'synced');
        }

        if (historicalVersion >= 9) {
          final fee = (await database.query(
            'transactions',
            where: 'id = ?',
            whereArgs: ['linked-fee'],
          )).single;
          expect(fee['related_transaction_id'], 'asset-9');
          expect(fee['relation_type'], 'assetFeeExpense');
        }
      },
    );
  }
}

const _timestamp = 1784883600000;

Future<void> _createHistoricalDatabase(String path, int version) async {
  final database = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (database, _) => _createHistoricalSchema(database, version),
    ),
  );
  await _insertHistoricalRows(database, version);
  await database.close();
}

Future<void> _createHistoricalSchema(Database database, int version) async {
  final columns = <String>[
    'id TEXT PRIMARY KEY',
    if (version >= 2) 'project_id TEXT',
    'title TEXT NOT NULL',
    'category TEXT NOT NULL',
    'account TEXT NOT NULL',
    'transaction_date INTEGER NOT NULL',
    'amount INTEGER NOT NULL',
    'transaction_type TEXT NOT NULL',
    'quantity REAL',
    'unit TEXT',
    'unit_price INTEGER',
    if (version >= 7) 'asset_definition_id TEXT',
    if (version >= 4) 'asset_name TEXT',
    if (version >= 5) 'asset_symbol TEXT',
    if (version >= 4) 'asset_action TEXT',
    if (version >= 8) 'fee_amount INTEGER NOT NULL DEFAULT 0',
    if (version >= 8) "fee_treatment TEXT NOT NULL DEFAULT 'none'",
    if (version >= 9) 'related_transaction_id TEXT',
    if (version >= 9) "relation_type TEXT NOT NULL DEFAULT 'none'",
    if (version >= 10) 'market_reference_unit_price INTEGER',
    if (version >= 10) 'market_reference_currency_code TEXT',
    if (version >= 10) 'market_reference_unit TEXT',
    if (version >= 10) 'market_reference_source TEXT',
    if (version >= 10) 'market_reference_quoted_at INTEGER',
    'created_at INTEGER NOT NULL',
    'updated_at INTEGER NOT NULL',
    'deleted_at INTEGER',
    'version INTEGER NOT NULL DEFAULT 1',
    'device_id TEXT NOT NULL',
    "sync_status TEXT NOT NULL DEFAULT 'local_only'",
  ];
  await database.execute('CREATE TABLE transactions (${columns.join(', ')})');
  await database.execute(
    'CREATE INDEX idx_transactions_date ON transactions(transaction_date)',
  );
  await database.execute(
    'CREATE INDEX idx_transactions_sync ON transactions(sync_status)',
  );
  if (version >= 2) {
    await database.execute(
      'CREATE INDEX idx_transactions_project ON transactions(project_id)',
    );
  }
  if (version >= 4) {
    await database.execute(
      'CREATE INDEX idx_transactions_asset '
      'ON transactions(asset_name, asset_action)',
    );
  }
  if (version >= 7) {
    await database.execute(
      'CREATE INDEX idx_transactions_asset_definition '
      'ON transactions(asset_definition_id)',
    );
  }
  if (version >= 9) {
    await database.execute(
      'CREATE INDEX idx_transactions_relation '
      'ON transactions(related_transaction_id, relation_type)',
    );
  }

  if (version >= 3) await _createMasterTables(database);
  if (version >= 5) await _createMarketPriceTable(database);
  if (version >= 6) await _createAssetDefinitionTable(database);
}

Future<void> _createMasterTables(Database database) async {
  await database.execute('''
    CREATE TABLE books (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, deleted_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'local_only')
  ''');
  await database.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL,
      account_type TEXT NOT NULL DEFAULT 'asset', created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, deleted_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'local_only')
  ''');
  await database.execute('''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL,
      category_type TEXT NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, deleted_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'local_only')
  ''');
  await database.execute('''
    CREATE TABLE projects (
      id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, deleted_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'local_only')
  ''');
  await database.execute('CREATE INDEX idx_accounts_name ON accounts(name)');
  await database.execute(
    'CREATE INDEX idx_categories_type ON categories(category_type)',
  );
  await database.execute('CREATE INDEX idx_projects_name ON projects(name)');
}

Future<void> _createMarketPriceTable(Database database) async {
  await database.execute('''
    CREATE TABLE asset_market_prices (
      asset_key TEXT PRIMARY KEY, symbol TEXT, price_minor INTEGER NOT NULL,
      minor_unit_scale INTEGER NOT NULL DEFAULT 1,
      currency_code TEXT NOT NULL, unit TEXT NOT NULL,
      quoted_at INTEGER NOT NULL, source TEXT NOT NULL,
      is_delayed INTEGER NOT NULL DEFAULT 0,
      is_manual INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)
  ''');
}

Future<void> _createAssetDefinitionTable(Database database) async {
  await database.execute('''
    CREATE TABLE asset_definitions (
      id TEXT PRIMARY KEY, display_name TEXT NOT NULL,
      asset_kind TEXT NOT NULL, symbol TEXT, provider_code TEXT,
      provider_symbol TEXT, exchange_code TEXT, currency_code TEXT NOT NULL,
      unit TEXT NOT NULL, lot_size INTEGER NOT NULL DEFAULT 1,
      online_pricing_enabled INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      deleted_at INTEGER, version INTEGER NOT NULL DEFAULT 1,
      device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')
  ''');
  await database.execute(
    'CREATE INDEX idx_asset_definitions_name '
    'ON asset_definitions(display_name)',
  );
  await database.execute(
    'CREATE INDEX idx_asset_definitions_symbol ON asset_definitions(symbol)',
  );
  await database.execute(
    'CREATE INDEX idx_asset_definitions_sync '
    'ON asset_definitions(sync_status)',
  );
}

Future<void> _insertHistoricalRows(Database database, int version) async {
  Map<String, Object?> transaction({
    required String id,
    required String title,
    required String type,
    required int amount,
    int? deletedAt,
  }) => <String, Object?>{
    'id': id,
    if (version >= 2) 'project_id': 'project-life',
    'title': title,
    'category': type == 'expense' ? 'Food' : 'Asset conversion',
    'account': type == 'expense' ? 'Cash' : 'Cash -> US Dollar Cash',
    'transaction_date': _timestamp,
    'amount': amount,
    'transaction_type': type,
    'quantity': type == 'assetConversion' ? 1000.0 : null,
    'unit': type == 'assetConversion' ? 'usd' : null,
    'unit_price': type == 'assetConversion' ? 16200 : null,
    if (version >= 7)
      'asset_definition_id': type == 'assetConversion' ? 'asset-usd' : null,
    if (version >= 4)
      'asset_name': type == 'assetConversion' ? 'US Dollar Cash' : null,
    if (version >= 5) 'asset_symbol': type == 'assetConversion' ? 'USD' : null,
    if (version >= 4) 'asset_action': type == 'assetConversion' ? 'buy' : null,
    if (version >= 8) 'fee_amount': type == 'assetConversion' ? 100000 : 0,
    if (version >= 8)
      'fee_treatment': type == 'assetConversion'
          ? 'capitalizeIntoCostBasis'
          : 'none',
    if (version >= 9) 'related_transaction_id': null,
    if (version >= 9) 'relation_type': 'none',
    if (version >= 10)
      'market_reference_unit_price': type == 'assetConversion' ? 16300 : null,
    if (version >= 10)
      'market_reference_currency_code': type == 'assetConversion'
          ? 'IDR'
          : null,
    if (version >= 10)
      'market_reference_unit': type == 'assetConversion' ? 'usd' : null,
    if (version >= 10)
      'market_reference_source': type == 'assetConversion' ? 'manual' : null,
    if (version >= 10)
      'market_reference_quoted_at': type == 'assetConversion'
          ? _timestamp
          : null,
    'created_at': _timestamp - 2000,
    'updated_at': _timestamp - 1000,
    'deleted_at': deletedAt,
    'version': 4,
    'device_id': 'historical-device',
    'sync_status': 'synced',
  };

  await database.insert(
    'transactions',
    transaction(
      id: 'ordinary-$version',
      title: 'Historical expense',
      type: 'expense',
      amount: 125000,
    ),
  );
  await database.insert(
    'transactions',
    transaction(
      id: 'deleted-$version',
      title: 'Deleted historical expense',
      type: 'expense',
      amount: 50000,
      deletedAt: _timestamp + 1000,
    ),
  );
  if (version >= 4) {
    await database.insert(
      'transactions',
      transaction(
        id: 'asset-$version',
        title: 'Historical USD buy',
        type: 'assetConversion',
        amount: 16200000,
      ),
    );
  }

  if (version >= 3) {
    final common = <String, Object?>{
      'created_at': _timestamp - 3000,
      'updated_at': _timestamp - 1000,
      'deleted_at': null,
      'version': 2,
      'device_id': 'historical-device',
      'sync_status': 'synced',
    };
    await database.insert('books', {
      'id': 'book-personal',
      'name': 'Personal',
      ...common,
    });
    await database.insert('accounts', {
      'id': 'account-cash',
      'book_id': 'book-personal',
      'name': 'Cash',
      'account_type': 'asset',
      ...common,
    });
    await database.insert('categories', {
      'id': 'category-food',
      'book_id': 'book-personal',
      'name': 'Food',
      'category_type': 'expense',
      ...common,
    });
    await database.insert('projects', {
      'id': 'project-life',
      'book_id': 'book-personal',
      'name': 'Life',
      'status': 'active',
      ...common,
    });
  }

  if (version >= 5) {
    await database.insert('asset_market_prices', {
      'asset_key': 'USD',
      'symbol': 'USD',
      'price_minor': 16450,
      'minor_unit_scale': 1,
      'currency_code': 'IDR',
      'unit': 'usd',
      'quoted_at': _timestamp,
      'source': 'Manual',
      'is_delayed': 0,
      'is_manual': 1,
      'updated_at': _timestamp,
    });
  }

  if (version >= 6) {
    await database.insert('asset_definitions', {
      'id': 'asset-usd',
      'display_name': 'US Dollar Cash',
      'asset_kind': 'foreignCurrency',
      'symbol': 'USD',
      'provider_code': 'alpha_vantage',
      'provider_symbol': 'USD/IDR',
      'exchange_code': null,
      'currency_code': 'IDR',
      'unit': 'usd',
      'lot_size': 1,
      'online_pricing_enabled': 1,
      'created_at': _timestamp - 3000,
      'updated_at': _timestamp - 1000,
      'deleted_at': null,
      'version': 3,
      'device_id': 'historical-device',
      'sync_status': 'synced',
    });
  }

  if (version >= 9) {
    await database.insert('transactions', {
      ...transaction(
        id: 'linked-fee',
        title: 'Fee - Buy USD',
        type: 'expense',
        amount: 100000,
      ),
      'related_transaction_id': 'asset-9',
      'relation_type': 'assetFeeExpense',
    });
  }
}

Future<int> _userVersion(Database database) async =>
    (await database.rawQuery('PRAGMA user_version')).single['user_version']
        as int;

Future<Set<String>> _columnNames(Database database, String table) async =>
    (await database.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toSet();

Future<Set<String>> _objectNames(Database database, String type) async =>
    (await database.rawQuery('SELECT name FROM sqlite_master WHERE type = ?', [
      type,
    ])).map((row) => row['name'] as String).toSet();

class _DatabaseFixture {
  const _DatabaseFixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_DatabaseFixture> create(String prefix) async {
    final directory = await Directory.systemTemp.createTemp('$prefix-');
    return _DatabaseFixture(directory, p.join(directory.path, 'test.db'));
  }

  Future<Database> openReadOnly() => databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );

  Future<void> dispose() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
