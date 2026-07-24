import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

class LocalStore {
  LocalStore({this.databasePath});
  static bool _ffiInitialized = false;

  final String? databasePath;
  Database? _database;

  Future<void> initialize() async {
    if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        !_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
    final resolvedDatabasePath =
        databasePath ?? p.join(await getDatabasesPath(), 'pilgrim_tracker.db');

    _database = await openDatabase(
      resolvedDatabasePath,
      version: 10,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            project_id TEXT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            account TEXT NOT NULL,
            transaction_date INTEGER NOT NULL,
            amount INTEGER NOT NULL,
            transaction_type TEXT NOT NULL,
            quantity REAL,
            unit TEXT,
            unit_price INTEGER,
asset_definition_id TEXT,
asset_name TEXT,
asset_symbol TEXT,
            asset_action TEXT,
            fee_amount INTEGER NOT NULL DEFAULT 0,
            fee_treatment TEXT NOT NULL DEFAULT 'none',
            related_transaction_id TEXT,
            relation_type TEXT NOT NULL DEFAULT 'none',
            market_reference_unit_price INTEGER,
            market_reference_currency_code TEXT,
            market_reference_unit TEXT,
            market_reference_source TEXT,
            market_reference_quoted_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            version INTEGER NOT NULL DEFAULT 1,
            device_id TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'local_only'
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_transactions_date ON transactions(transaction_date)',
        );
        await db.execute(
          'CREATE INDEX idx_transactions_sync ON transactions(sync_status)',
        );
        await db.execute(
          'CREATE INDEX idx_transactions_project '
          'ON transactions(project_id)',
        );
        await db.execute(
          'CREATE INDEX idx_transactions_asset '
          'ON transactions(asset_name, asset_action)',
        );
        await db.execute(
          'CREATE INDEX idx_transactions_asset_definition '
          'ON transactions(asset_definition_id)',
        );
        await db.execute(
          'CREATE INDEX idx_transactions_relation '
          'ON transactions(related_transaction_id, relation_type)',
        );
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS books (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL DEFAULT 1,
          device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
        );
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, account_type TEXT NOT NULL DEFAULT 'asset',
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
          version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
        );
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS categories (
          id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, category_type TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
          version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
        );
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS projects (
          id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active',
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
          version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
        );
        await db.execute('''
          CREATE TABLE IF NOT EXISTS asset_market_prices (
            asset_key TEXT PRIMARY KEY,
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
        await db.execute('''
  CREATE TABLE IF NOT EXISTS asset_definitions (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    asset_kind TEXT NOT NULL,
    symbol TEXT,
    provider_code TEXT,
    provider_symbol TEXT,
    exchange_code TEXT,
    currency_code TEXT NOT NULL,
    unit TEXT NOT NULL,
    lot_size INTEGER NOT NULL DEFAULT 1
      CHECK(lot_size > 0),
    online_pricing_enabled INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    version INTEGER NOT NULL DEFAULT 1,
    device_id TEXT NOT NULL,
    sync_status TEXT NOT NULL DEFAULT 'local_only'
  )
''');

        await db.execute(
          'CREATE INDEX idx_asset_definitions_name '
          'ON asset_definitions(display_name)',
        );

        await db.execute(
          'CREATE INDEX idx_asset_definitions_symbol '
          'ON asset_definitions(symbol)',
        );

        await db.execute(
          'CREATE INDEX idx_asset_definitions_sync '
          'ON asset_definitions(sync_status)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN project_id TEXT',
          );
          await db.execute(
            'CREATE INDEX idx_transactions_project ON transactions(project_id)',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            '''CREATE TABLE books (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL DEFAULT 1,
            device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
          );
          await db.execute(
            '''CREATE TABLE accounts (
            id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, account_type TEXT NOT NULL DEFAULT 'asset',
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
          );
          await db.execute(
            '''CREATE TABLE categories (
            id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, category_type TEXT NOT NULL,
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
          );
          await db.execute(
            '''CREATE TABLE projects (
            id TEXT PRIMARY KEY, book_id TEXT, name TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active',
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
            version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
          );
          await db.execute('CREATE INDEX idx_accounts_name ON accounts(name)');
          await db.execute(
            'CREATE INDEX idx_categories_type ON categories(category_type)',
          );
          await db.execute('CREATE INDEX idx_projects_name ON projects(name)');
        }

        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN asset_name TEXT',
          );

          await db.execute(
            'ALTER TABLE transactions ADD COLUMN asset_action TEXT',
          );

          await db.execute(
            'CREATE INDEX idx_transactions_asset '
            'ON transactions(asset_name, asset_action)',
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN asset_symbol TEXT',
          );

          await db.execute('''
            CREATE TABLE IF NOT EXISTS asset_market_prices (
              asset_key TEXT PRIMARY KEY,
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
        }
        if (oldVersion < 6) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_project '
            'ON transactions(project_id)',
          );

          await db.execute('''
    CREATE TABLE IF NOT EXISTS asset_definitions (
      id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      asset_kind TEXT NOT NULL,
      symbol TEXT,
      provider_code TEXT,
      provider_symbol TEXT,
      exchange_code TEXT,
      currency_code TEXT NOT NULL,
      unit TEXT NOT NULL,
      lot_size INTEGER NOT NULL DEFAULT 1
        CHECK(lot_size > 0),
      online_pricing_enabled INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1,
      device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'local_only'
    )
  ''');

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_asset_definitions_name '
            'ON asset_definitions(display_name)',
          );

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_asset_definitions_symbol '
            'ON asset_definitions(symbol)',
          );

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_asset_definitions_sync '
            'ON asset_definitions(sync_status)',
          );
        }
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN asset_definition_id TEXT',
          );

          await db.execute(
            'CREATE INDEX IF NOT EXISTS '
            'idx_transactions_asset_definition '
            'ON transactions(asset_definition_id)',
          );
        }
        if (oldVersion < 8) {
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN fee_amount INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE transactions '
            "ADD COLUMN fee_treatment TEXT NOT NULL DEFAULT 'none'",
          );
        }
        if (oldVersion < 9) {
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN related_transaction_id TEXT',
          );
          await db.execute(
            'ALTER TABLE transactions '
            "ADD COLUMN relation_type TEXT NOT NULL DEFAULT 'none'",
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_relation '
            'ON transactions(related_transaction_id, relation_type)',
          );
        }
        if (oldVersion < 10) {
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN market_reference_unit_price INTEGER',
          );
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN market_reference_currency_code TEXT',
          );
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN market_reference_unit TEXT',
          );
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN market_reference_source TEXT',
          );
          await db.execute(
            'ALTER TABLE transactions '
            'ADD COLUMN market_reference_quoted_at INTEGER',
          );
        }
      },
    );
  }

  Database get db {
    final value = _database;
    if (value == null) throw StateError('LocalStore has not been initialized');
    return value;
  }

  Future<List<Map<String, Object?>>> getTransactions() => db.query(
    'transactions',
    where: 'deleted_at IS NULL',
    orderBy: 'transaction_date DESC, created_at DESC',
  );

  Future<Map<String, Object?>?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async {
    final records = await db.query(
      'transactions',
      where:
          'related_transaction_id = ? AND relation_type = ?'
          '${includeDeleted ? '' : ' AND deleted_at IS NULL'}',
      whereArgs: [parentTransactionId, 'assetFeeExpense'],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    return records.isEmpty ? null : records.first;
  }

  Future<void> upsertTransaction(Map<String, Object?> record) => db.insert(
    'transactions',
    record,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> softDeleteTransaction(
    String id,
    int deletedAt, {
    int? version,
  }) => db.update(
    'transactions',
    {
      'deleted_at': deletedAt,
      'updated_at': deletedAt,
      ...?version == null ? null : {'version': version},
      'sync_status': 'pending',
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> saveAssetFeeChange({
    required Map<String, Object?> parent,
    Map<String, Object?>? linkedExpense,
    Map<String, Object?>? obsoleteLinkedExpense,
  }) {
    return db.transaction((transaction) async {
      Future<void> upsert(Map<String, Object?> record) => transaction.insert(
        'transactions',
        record,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await upsert(parent);
      if (linkedExpense != null) {
        await upsert(linkedExpense);
      }
      if (obsoleteLinkedExpense != null &&
          obsoleteLinkedExpense['id'] != linkedExpense?['id']) {
        await upsert(obsoleteLinkedExpense);
      }
    });
  }

  Future<List<Map<String, Object?>>> getAssetMarketPrices() {
    return db.query('asset_market_prices', orderBy: 'updated_at DESC');
  }

  Future<void> upsertAssetMarketPrice(Map<String, Object?> record) {
    return db.insert(
      'asset_market_prices',
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> getAssetDefinitions({
    bool includeDeleted = false,
  }) {
    return db.query(
      'asset_definitions',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'display_name COLLATE NOCASE',
    );
  }

  Future<Map<String, Object?>?> getAssetDefinitionById(String id) async {
    final rows = await db.query(
      'asset_definitions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<void> upsertAssetDefinition(Map<String, Object?> record) {
    return db.insert(
      'asset_definitions',
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDeleteAssetDefinition(String id, int deletedAt) async {
    await db.rawUpdate(
      '''
    UPDATE asset_definitions
    SET deleted_at = ?,
        updated_at = ?,
        version = version + 1,
        sync_status = ?
    WHERE id = ?
    ''',
      [deletedAt, deletedAt, 'pending', id],
    );
  }

  Future<void> ensureAssetDefinitionSeeds(
    List<Map<String, Object?>> records,
  ) async {
    await db.transaction((txn) async {
      for (final record in records) {
        await txn.insert(
          'asset_definitions',
          record,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> close() async => _database?.close();

  String _table(String entity) {
    if (!const {'accounts', 'categories', 'projects'}.contains(entity)) {
      throw ArgumentError.value(entity, 'entity');
    }
    return entity;
  }

  Future<List<String>> getMasterNames(
    String entity, {
    String? categoryType,
  }) async {
    final table = _table(entity);
    final rows = await db.query(
      table,
      columns: ['name'],
      where: categoryType == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND category_type = ?',
      whereArgs: categoryType == null ? null : [categoryType],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<void> saveMasterName(
    String entity,
    String name, {
    String? previousName,
    String? categoryType,
  }) async {
    final table = _table(entity);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (previousName != null) {
      final isCategory = entity == 'categories';

      if (isCategory && categoryType == null) {
        throw ArgumentError.value(
          categoryType,
          'categoryType',
          'Category type is required when renaming a category.',
        );
      }

      final where = isCategory
          ? 'name = ? AND deleted_at IS NULL '
                'AND category_type = ?'
          : 'name = ? AND deleted_at IS NULL';

      final whereArgs = <Object?>[previousName, if (isCategory) categoryType];

      await db.rawUpdate(
        '''
      UPDATE $table
      SET name = ?,
          updated_at = ?,
          version = version + 1,
          sync_status = ?
      WHERE $where
    ''',
        [name, now, 'pending', ...whereArgs],
      );

      return;
    }
    final record = <String, Object?>{
      'id': const Uuid().v4(),
      'name': name,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'local-device',
      'sync_status': 'pending',
    };
    if (entity == 'accounts') record['account_type'] = 'asset';
    if (entity == 'projects') record['status'] = 'active';
    if (entity == 'categories') {
      record['category_type'] = categoryType ?? 'expense';
    }
    await db.insert(table, record, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> ensureMasterSeeds(
    String entity,
    List<String> names, {
    String? categoryType,
  }) async {
    if ((await getMasterNames(entity, categoryType: categoryType)).isNotEmpty) {
      return;
    }
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final name in names) {
        final record = <String, Object?>{
          'id': const Uuid().v4(),
          'name': name,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'local_only',
        };
        if (entity == 'accounts') record['account_type'] = 'asset';
        if (entity == 'projects') record['status'] = 'active';
        if (entity == 'categories') {
          record['category_type'] = categoryType ?? 'expense';
        }
        await txn.insert(_table(entity), record);
      }
    });
  }
}
