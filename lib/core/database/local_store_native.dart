import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'household_schema_native.dart';
import 'import_review_schema_native.dart';
import 'backup_schema_native.dart';
import 'budget_schema_native.dart';
import 'native_database_path.dart';
import 'sync_schema_native.dart';
import 'transaction_import_rule_schema_native.dart';
import 'transaction_category_identity_schema_native.dart';
import 'transfer_link_schema_native.dart';

class LocalStore {
  LocalStore({this.databasePath});
  static const schemaVersion = 26;
  static bool _ffiInitialized = false;

  final String? databasePath;
  Database? _database;
  String? _activeBookId;

  String? get activeBookId => _activeBookId;
  void setActiveBookId(String? value) => _activeBookId = value;
  void Function()? onSyncMutation;

  Future<void> initialize() async {
    if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        !_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
    final resolvedDatabasePath = databasePath ?? await _defaultDatabasePath();

    _database = await openDatabase(
      resolvedDatabasePath,
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            book_id TEXT,
            entered_by_member_id TEXT,
            project_id TEXT,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            category_id TEXT,
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
        await TransactionCategoryIdentitySchemaNative.create(db);
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS books (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL,
          base_currency_code TEXT NOT NULL DEFAULT 'IDR',
          remote_linked_at INTEGER,
          updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL DEFAULT 1,
          device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only')''',
        );
        await db.execute(
          '''CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY, book_id TEXT, owner_member_id TEXT, name TEXT NOT NULL, account_type TEXT NOT NULL DEFAULT 'asset',
          currency_code TEXT NOT NULL DEFAULT 'IDR', opening_balance INTEGER NOT NULL DEFAULT 0,
          opening_balance_date INTEGER,
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
        await db.execute('CREATE INDEX idx_accounts_name ON accounts(name)');
        await db.execute(
          'CREATE INDEX idx_categories_type ON categories(category_type)',
        );
        await db.execute('CREATE INDEX idx_projects_name ON projects(name)');
        await _createProfileTables(db);
        await HouseholdSchemaNative.createMembersTable(db);
        await SyncSchemaNative.create(db);
        await BudgetSchemaNative.create(db);
        await TransactionImportRuleSchemaNative.create(db);
        await TransferLinkSchemaNative.create(db);
        await ImportReviewSchemaNative.create(db);
        await db.execute('''
          CREATE TABLE IF NOT EXISTS asset_market_prices (
            asset_key TEXT NOT NULL,
            book_id TEXT NOT NULL,
            symbol TEXT,
            price_minor INTEGER NOT NULL,
            minor_unit_scale INTEGER NOT NULL DEFAULT 1,
            currency_code TEXT NOT NULL,
            unit TEXT NOT NULL,
            quoted_at INTEGER NOT NULL,
            source TEXT NOT NULL,
            is_delayed INTEGER NOT NULL DEFAULT 0,
            is_manual INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (book_id, asset_key)
          )
          ''');
        await db.execute('''
  CREATE TABLE IF NOT EXISTS asset_definitions (
    id TEXT PRIMARY KEY,
    book_id TEXT,
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
        if (oldVersion < 11) {
          await _upgradeAccounts(db);
          await _createProfileTables(db);

          final now = DateTime.now().millisecondsSinceEpoch;
          const profileId = 'legacy-local-profile';
          await db.insert('local_profiles', {
            'id': profileId,
            'display_name': 'Local User',
            'default_currency_code': 'IDR',
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('local_session', {
            'id': 1,
            'active_profile_id': profileId,
            'onboarding_completed': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (oldVersion < 12) {
          await HouseholdSchemaNative.upgradeToV12(db);
        }
        if (oldVersion < 13) {
          await HouseholdSchemaNative.upgradeToV13(db);
        }
        if (oldVersion < 14) {
          await SyncSchemaNative.upgradeToV14(db);
        }
        if (oldVersion < 15) {
          await SyncSchemaNative.upgradeToV15(db);
        }
        if (oldVersion < 16) {
          await SyncSchemaNative.upgradeToV16(db);
        }
        if (oldVersion < 17) {
          await SyncSchemaNative.upgradeToV17(db);
        }
        if (oldVersion < 18) {
          await SyncSchemaNative.upgradeToV18(db);
        }
        if (oldVersion < 19) {
          await SyncSchemaNative.upgradeToV19(db);
        }
        if (oldVersion < 20) {
          await BackupSchemaNative.upgradeToV20(db);
        }
        if (oldVersion < 21) {
          await BudgetSchemaNative.upgradeToV21(db);
        }
        if (oldVersion < 22) {
          await TransactionImportRuleSchemaNative.upgradeToV22(db);
        }
        if (oldVersion < 23) {
          await TransferLinkSchemaNative.create(db);
        }
        if (oldVersion < 24) {
          await ImportReviewSchemaNative.create(db);
        }
        if (oldVersion < 25) {
          await ImportReviewSchemaNative.upgradeToV25(db);
        }
        if (oldVersion < 26) {
          await TransactionCategoryIdentitySchemaNative.upgradeToV26(db);
        }
      },
    );
  }

  Future<String> _defaultDatabasePath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return NativeDatabasePath.resolve();
    }
    return p.join(await getDatabasesPath(), 'pilgrim_tracker.db');
  }

  static Future<void> _createProfileTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        default_currency_code TEXT NOT NULL DEFAULT 'IDR',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_session (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        active_profile_id TEXT,
        active_book_id TEXT,
        active_member_id TEXT,
        onboarding_completed INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _upgradeAccounts(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'accounts'",
    );
    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          book_id TEXT,
          name TEXT NOT NULL,
          account_type TEXT NOT NULL DEFAULT 'asset',
          currency_code TEXT NOT NULL DEFAULT 'IDR',
          opening_balance INTEGER NOT NULL DEFAULT 0,
          opening_balance_date INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER,
          version INTEGER NOT NULL DEFAULT 1,
          device_id TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'local_only'
        )
      ''');
    } else {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(accounts)',
      )).map((row) => row['name'] as String).toSet();
      if (!columns.contains('currency_code')) {
        await db.execute(
          "ALTER TABLE accounts ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'IDR'",
        );
      }
      if (!columns.contains('opening_balance')) {
        await db.execute(
          'ALTER TABLE accounts ADD COLUMN opening_balance INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!columns.contains('opening_balance_date')) {
        await db.execute(
          'ALTER TABLE accounts ADD COLUMN opening_balance_date INTEGER',
        );
      }
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounts_name ON accounts(name)',
    );
  }

  Database get db {
    final value = _database;
    if (value == null) throw StateError('LocalStore has not been initialized');
    return value;
  }

  Future<int> getSchemaVersion() => db.getVersion();

  Future<List<Map<String, Object?>>> getTransactions({
    bool includeDeleted = false,
    String? bookId,
  }) {
    final scope = bookId ?? _activeBookId;
    return db.query(
      'transactions',
      where: _scopedWhere(scope, includeDeleted: includeDeleted),
      whereArgs: scope == null ? null : [scope],
      orderBy: 'transaction_date DESC, created_at DESC',
    );
  }

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

  Future<void> upsertTransaction(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    await db.transaction((txn) async {
      await _validateTransactionCategory(txn, prepared);
      await txn.insert(
        'transactions',
        prepared,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(txn, 'transactions', prepared);
      }
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> insertTransactionsAtomic(
    List<Map<String, Object?>> records,
  ) async {
    if (records.isEmpty) return;
    await db.transaction((transaction) async {
      for (final record in records) {
        final prepared = _withActiveBook(record);
        await _validateTransactionCategory(transaction, prepared);
        await transaction.insert(
          'transactions',
          prepared,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await _enqueueSyncOperation(transaction, 'transactions', prepared);
      }
    });
    onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getTransferLinks({
    bool includeDeleted = false,
    String? bookId,
  }) {
    final scope = bookId ?? _activeBookId;
    return db.query(
      'transfer_links',
      where: _scopedWhere(scope, includeDeleted: includeDeleted),
      whereArgs: scope == null ? null : [scope],
      orderBy: 'updated_at DESC',
    );
  }

  Future<void> saveInternalTransferAtomic({
    required List<Map<String, Object?>> transactions,
    required Map<String, Object?> link,
    bool enqueueSync = true,
    Map<String, int> expectedTransactionVersions = const {},
    Set<String> requireNewTransactionIds = const {},
  }) async {
    await db.transaction((txn) async {
      for (final entry in expectedTransactionVersions.entries) {
        final rows = await txn.query(
          'transactions',
          columns: const ['version'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (rows.length != 1 ||
            (rows.single['version'] as num).toInt() != entry.value) {
          throw StateError('This transfer candidate changed. Review again.');
        }
      }
      for (final id in requireNewTransactionIds) {
        final rows = await txn.query(
          'transactions',
          columns: const ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          throw StateError('This transfer candidate changed. Review again.');
        }
      }
      for (final record in transactions) {
        final prepared = _withActiveBook(record);
        await txn.insert(
          'transactions',
          prepared,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (enqueueSync) {
          await _enqueueSyncOperation(
            txn,
            'transactions',
            prepared,
            operationType: prepared['deleted_at'] == null ? 'upsert' : 'delete',
          );
        }
      }
      final preparedLink = _withActiveBook(link);
      final existingLink = await txn.query(
        'transfer_links',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [preparedLink['id']],
        limit: 1,
      );
      if (existingLink.isEmpty) {
        await txn.insert(
          'transfer_links',
          preparedLink,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        await txn.update(
          'transfer_links',
          preparedLink,
          where: 'id = ?',
          whereArgs: [preparedLink['id']],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await _validateInternalTransfersInDatabase(
        txn,
        preparedLink['book_id'] as String,
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(
          txn,
          'transfer_links',
          preparedLink,
          operationType: preparedLink['deleted_at'] == null
              ? 'upsert'
              : 'delete',
        );
      }
    });
    if (enqueueSync) {
      onSyncMutation?.call();
    }
  }

  Future<void> softDeleteTransaction(
    String id,
    int deletedAt, {
    int? version,
  }) async {
    await db.transaction((txn) async {
      await txn.update(
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
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await _enqueueSyncOperation(
          txn,
          'transactions',
          rows.first,
          operationType: 'delete',
        );
      }
    });
    onSyncMutation?.call();
  }

  Future<void> saveAssetFeeChange({
    required Map<String, Object?> parent,
    Map<String, Object?>? linkedExpense,
    Map<String, Object?>? obsoleteLinkedExpense,
  }) async {
    await db.transaction((transaction) async {
      Future<void> upsert(Map<String, Object?> record) => transaction.insert(
        'transactions',
        _withActiveBook(record),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await upsert(parent);
      await _enqueueSyncOperation(
        transaction,
        'transactions',
        _withActiveBook(parent),
        operationType: parent['deleted_at'] == null ? 'upsert' : 'delete',
      );
      if (linkedExpense != null) {
        await upsert(linkedExpense);
        await _enqueueSyncOperation(
          transaction,
          'transactions',
          _withActiveBook(linkedExpense),
        );
      }
      if (obsoleteLinkedExpense != null &&
          obsoleteLinkedExpense['id'] != linkedExpense?['id']) {
        await upsert(obsoleteLinkedExpense);
        await _enqueueSyncOperation(
          transaction,
          'transactions',
          _withActiveBook(obsoleteLinkedExpense),
          operationType: obsoleteLinkedExpense['deleted_at'] == null
              ? 'upsert'
              : 'delete',
        );
      }
    });
    onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getAssetMarketPrices({String? bookId}) {
    final scope = bookId ?? _activeBookId;
    return db.query(
      'asset_market_prices',
      where: scope == null ? null : 'book_id = ?',
      whereArgs: scope == null ? null : [scope],
      orderBy: 'updated_at DESC',
    );
  }

  Future<void> upsertAssetMarketPrice(Map<String, Object?> record) {
    final scoped = _withActiveBook(record);
    return db.insert('asset_market_prices', {
      ...scoped,
      'book_id': scoped['book_id'] ?? 'legacy-default-book',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getAssetDefinitions({
    bool includeDeleted = false,
    String? bookId,
  }) {
    final scope = bookId ?? _activeBookId;
    return db.query(
      'asset_definitions',
      where: _scopedWhere(scope, includeDeleted: includeDeleted),
      whereArgs: scope == null ? null : [scope],
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

  Future<void> upsertAssetDefinition(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    await db.transaction((txn) async {
      await txn.insert(
        'asset_definitions',
        prepared,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(txn, 'asset_definitions', prepared);
      }
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> softDeleteAssetDefinition(String id, int deletedAt) async {
    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE asset_definitions
        SET deleted_at = ?, updated_at = ?, version = version + 1,
            sync_status = ? WHERE id = ?
        ''',
        [deletedAt, deletedAt, 'pending', id],
      );
      final rows = await txn.query(
        'asset_definitions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await _enqueueSyncOperation(
          txn,
          'asset_definitions',
          rows.first,
          operationType: 'delete',
        );
      }
    });
    onSyncMutation?.call();
  }

  Future<void> ensureAssetDefinitionSeeds(
    List<Map<String, Object?>> records,
  ) async {
    await db.transaction((txn) async {
      for (final record in records) {
        final prepared = _withActiveBook(record);
        final existing = await txn.query(
          'asset_definitions',
          columns: ['book_id'],
          where: 'id = ?',
          whereArgs: [prepared['id']],
          limit: 1,
        );
        if (existing.isNotEmpty &&
            existing.first['book_id'] != prepared['book_id']) {
          final activeBookId = prepared['book_id'];
          final equivalentInActiveBook = activeBookId == null
              ? const <Map<String, Object?>>[]
              : await txn.query(
                  'asset_definitions',
                  where: 'book_id = ?',
                  whereArgs: [activeBookId],
                );
          if (equivalentInActiveBook.any(
            (candidate) => _sameAssetDefinitionSeed(candidate, prepared),
          )) {
            continue;
          }
          if (existing.first['book_id'] == null && activeBookId != null) {
            await txn.update(
              'asset_definitions',
              {'book_id': activeBookId},
              where: 'id = ? AND book_id IS NULL',
              whereArgs: [prepared['id']],
            );
            continue;
          }
          prepared['id'] = const Uuid().v4();
        }
        await txn.insert(
          'asset_definitions',
          prepared,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> createHouseholdBackupSnapshot(
    String bookId,
  ) {
    return db.transaction((txn) async {
      Future<List<Map<String, Object?>>> scoped(
        String table, {
        String orderBy = 'id',
        String extraWhere = '',
      }) {
        final where = extraWhere.isEmpty
            ? 'book_id = ?'
            : 'book_id = ? AND $extraWhere';
        return txn.query(
          table,
          where: where,
          whereArgs: [bookId],
          orderBy: orderBy,
        );
      }

      final household = await txn.query(
        'books',
        where: 'id = ?',
        whereArgs: [bookId],
        limit: 1,
      );
      if (household.isEmpty) {
        throw StateError('The selected household no longer exists.');
      }
      return {
        'household': household,
        'members': await scoped('household_members'),
        'accounts': await scoped('accounts'),
        'categories': await scoped('categories'),
        'projects': await scoped('projects'),
        'transactions': await scoped(
          'transactions',
          orderBy: 'transaction_date, created_at, id',
        ),
        'transfer_links': await scoped('transfer_links'),
        'asset_definitions': await scoped('asset_definitions'),
        'budgets': await scoped(
          'monthly_category_budgets',
          orderBy: 'month_start, category_id, id',
        ),
        'transaction_import_rules': await scoped(
          'transaction_import_rules',
          orderBy: 'priority DESC, name, id',
        ),
        'manual_market_prices': await scoped(
          'asset_market_prices',
          orderBy: 'asset_key',
          extraWhere: 'is_manual = 1',
        ),
      };
    });
  }

  Future<void> activateHouseholdBackupSnapshot(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) async {
    final households = snapshot['household'] ?? const [];
    if (households.length != 1) {
      throw StateError('A restore must contain exactly one household.');
    }
    final restoredBookId = households.single['id'] as String;
    final members = snapshot['members'] ?? const [];
    final activeMember = members.cast<Map<String, Object?>>().firstWhere(
      (member) => member['deleted_at'] == null && member['role'] == 'owner',
      orElse: () => members.cast<Map<String, Object?>>().firstWhere(
        (member) => member['deleted_at'] == null,
        orElse: () => throw StateError(
          'The restored household needs at least one active member.',
        ),
      ),
    );

    await db.transaction((txn) async {
      if (replaceBookId != null) {
        if (replaceBookId != restoredBookId) {
          throw StateError('Replacement requires a matching household ID.');
        }
        for (final table in const [
          'transfer_links',
          'transactions',
          'transaction_import_rules',
          'monthly_category_budgets',
          'asset_market_prices',
          'asset_definitions',
          'projects',
          'categories',
          'accounts',
          'household_members',
        ]) {
          await txn.delete(
            table,
            where: 'book_id = ?',
            whereArgs: [replaceBookId],
          );
        }
        for (final table in const [
          'sync_outbox',
          'sync_conflicts',
          'sync_cursors',
          'initial_sync_staging',
        ]) {
          await txn.delete(
            table,
            where: 'book_id = ?',
            whereArgs: [replaceBookId],
          );
        }
        await txn.delete('books', where: 'id = ?', whereArgs: [replaceBookId]);
      }

      Future<void> insertAll(String table, String key) async {
        for (final record in snapshot[key] ?? const []) {
          if (idempotent) {
            final existing = key == 'manual_market_prices'
                ? await txn.query(
                    table,
                    where: 'book_id = ? AND asset_key = ?',
                    whereArgs: [record['book_id'], record['asset_key']],
                    limit: 1,
                  )
                : await txn.query(
                    table,
                    where: 'id = ?',
                    whereArgs: [record['id']],
                    limit: 1,
                  );
            if (existing.isNotEmpty) {
              if (!_backupRecordsEqual(existing.single, record)) {
                throw StateError(
                  'Restore conflict for $key record ${record['id'] ?? record['asset_key']}.',
                );
              }
              continue;
            }
          }
          await txn.insert(
            table,
            record,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      await insertAll('books', 'household');
      await insertAll('household_members', 'members');
      await insertAll('accounts', 'accounts');
      await insertAll('categories', 'categories');
      await insertAll('monthly_category_budgets', 'budgets');
      await insertAll('transaction_import_rules', 'transaction_import_rules');
      await insertAll('projects', 'projects');
      await insertAll('asset_definitions', 'asset_definitions');
      await insertAll('asset_market_prices', 'manual_market_prices');
      await insertAll('transactions', 'transactions');
      await insertAll('transfer_links', 'transfer_links');

      final session = await txn.query(
        'local_session',
        where: 'id = 1',
        limit: 1,
      );
      await txn.insert('local_session', {
        'id': 1,
        'active_profile_id': session.isEmpty
            ? null
            : session.first['active_profile_id'],
        'active_book_id': restoredBookId,
        'active_member_id': activeMember['id'],
        'onboarding_completed': session.isEmpty
            ? 1
            : session.first['onboarding_completed'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    setActiveBookId(restoredBookId);
  }

  Future<int> recoverHouseholdBackupRecords(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) async {
    const tables = <String, String>{
      'accounts': 'accounts',
      'categories': 'categories',
      'projects': 'projects',
      'asset_definitions': 'asset_definitions',
      'budgets': 'monthly_category_budgets',
      'transaction_import_rules': 'transaction_import_rules',
      'transactions': 'transactions',
      'transfer_links': 'transfer_links',
    };
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final book = await txn.query(
        'books',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [bookId],
        limit: 1,
      );
      if (book.isEmpty) {
        throw StateError('The active household is unavailable.');
      }

      Future<bool> exists(String table, String id) async => (await txn.query(
        table,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty;

      Future<bool> available(String table, Object? id) async {
        if (id == null) return true;
        return (await txn.query(
          table,
          columns: ['id'],
          where: 'id = ? AND book_id = ?',
          whereArgs: [id, bookId],
          limit: 1,
        )).isNotEmpty;
      }

      final plannedAccountNames = {
        for (final row in records['accounts'] ?? const [])
          (row['name'] as String).trim().toLowerCase(),
      };
      final currentAccounts = await txn.query(
        'accounts',
        columns: ['name'],
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      final availableAccountNames = {
        ...plannedAccountNames,
        for (final row in currentAccounts)
          (row['name'] as String).trim().toLowerCase(),
      };

      for (final entry in records.entries) {
        final table = tables[entry.key];
        if (table == null) throw StateError('Unsupported recovery entity.');
        for (final source in entry.value) {
          final id = source['id'];
          if (id is! String || id.isEmpty || source['book_id'] != bookId) {
            throw StateError('Recovery record identity is invalid.');
          }
          if (source['deleted_at'] != null || await exists(table, id)) {
            throw StateError('Recovery record is no longer missing.');
          }
        }
      }

      for (final source in records['accounts'] ?? const []) {
        if (!await available('household_members', source['owner_member_id'])) {
          throw StateError('A recovered account references a missing member.');
        }
      }
      for (final source in records['budgets'] ?? const []) {
        if (!await available('categories', source['category_id']) &&
            !(records['categories'] ?? const []).any(
              (row) => row['id'] == source['category_id'],
            )) {
          throw StateError('A recovered budget references a missing category.');
        }
        final collision = await txn.query(
          'monthly_category_budgets',
          columns: ['id'],
          where:
              'book_id = ? AND category_id = ? AND month_start = ? '
              'AND deleted_at IS NULL',
          whereArgs: [bookId, source['category_id'], source['month_start']],
          limit: 1,
        );
        if (collision.isNotEmpty) {
          throw StateError(
            'A current budget already uses this category and month.',
          );
        }
      }
      for (final source in records['transaction_import_rules'] ?? const []) {
        if (!await available('categories', source['category_id']) &&
            !(records['categories'] ?? const []).any(
              (row) => row['id'] == source['category_id'],
            )) {
          throw StateError(
            'A recovered import rule references a missing category.',
          );
        }
        if (!await available('accounts', source['account_id']) &&
            !(records['accounts'] ?? const []).any(
              (row) => row['id'] == source['account_id'],
            )) {
          throw StateError(
            'A recovered import rule references a missing account.',
          );
        }
      }
      for (final source in records['transactions'] ?? const []) {
        final account = (source['account'] as String? ?? '')
            .trim()
            .toLowerCase();
        if (account.isNotEmpty && !availableAccountNames.contains(account)) {
          throw StateError(
            'A recovered transaction references a missing account.',
          );
        }
        for (final dependency in <(String, Object?)>[
          ('household_members', source['entered_by_member_id']),
          ('projects', source['project_id']),
          ('asset_definitions', source['asset_definition_id']),
          ('transactions', source['related_transaction_id']),
        ]) {
          final plannedKey = switch (dependency.$1) {
            'projects' => 'projects',
            'asset_definitions' => 'asset_definitions',
            'transactions' => 'transactions',
            _ => null,
          };
          final planned =
              plannedKey != null &&
              (records[plannedKey] ?? const []).any(
                (row) => row['id'] == dependency.$2,
              );
          if (!planned && !await available(dependency.$1, dependency.$2)) {
            throw StateError('A recovered transaction dependency is missing.');
          }
        }
      }
      for (final source in records['transfer_links'] ?? const []) {
        for (final dependency in <(String, Object?)>[
          ('transactions', source['outgoing_transaction_id']),
          ('transactions', source['incoming_transaction_id']),
          ('accounts', source['source_account_id']),
          ('accounts', source['destination_account_id']),
        ]) {
          final plannedKey = dependency.$1;
          final planned = (records[plannedKey] ?? const []).any(
            (row) => row['id'] == dependency.$2,
          );
          if (!planned && !await available(dependency.$1, dependency.$2)) {
            throw StateError(
              'A recovered internal transfer dependency is missing.',
            );
          }
        }
      }

      for (final key in const [
        'categories',
        'projects',
        'accounts',
        'asset_definitions',
        'budgets',
        'transaction_import_rules',
        'transactions',
        'transfer_links',
      ]) {
        final table = tables[key]!;
        final entityType = key == 'budgets' ? 'monthly_category_budgets' : key;
        for (final source in records[key] ?? const []) {
          final saved = <String, Object?>{
            ...source,
            'book_id': bookId,
            'updated_at': now,
            'version': 1,
            'device_id': 'backup-recovery',
            'sync_status': enqueueSync ? 'pending' : 'local_only',
          };
          await txn.insert(
            table,
            saved,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          if (enqueueSync) await _enqueueSyncOperation(txn, entityType, saved);
        }
      }
    });
    if (enqueueSync && records.values.any((rows) => rows.isNotEmpty)) {
      onSyncMutation?.call();
    }
    return getPendingSyncCount(bookId);
  }

  Future<void> close() async => _database?.close();

  Future<List<Map<String, Object?>>> getAccounts({
    bool includeDeleted = false,
    String? bookId,
  }) {
    final scope = bookId ?? _activeBookId;
    return db.query(
      'accounts',
      where: _scopedWhere(scope, includeDeleted: includeDeleted),
      whereArgs: scope == null ? null : [scope],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<void> upsertAccount(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    final name = (record['name'] as String).trim();
    final id = record['id'] as String;
    final bookId = prepared['book_id'] as String?;
    await db.transaction((txn) async {
      final duplicate = await txn.query(
        'accounts',
        columns: ['id'],
        where: bookId == null
            ? 'name = ? COLLATE NOCASE AND deleted_at IS NULL AND id != ?'
            : 'book_id = ? AND name = ? COLLATE NOCASE '
                  'AND deleted_at IS NULL AND id != ?',
        whereArgs: bookId == null ? [name, id] : [bookId, name, id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) throw StateError('$name already exists.');
      final saved = {...prepared, 'name': name};
      await txn.insert(
        'accounts',
        saved,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) await _enqueueSyncOperation(txn, 'accounts', saved);
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> ensureAccountSeeds(
    List<String> names, {
    String currencyCode = 'IDR',
  }) async {
    if ((await getAccounts()).isNotEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final name in names) {
        await txn.insert('accounts', {
          'id': const Uuid().v4(),
          'book_id': _activeBookId,
          'name': name,
          'account_type': 'asset',
          'currency_code': currencyCode.trim().toUpperCase(),
          'opening_balance': 0,
          'opening_balance_date': null,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'local_only',
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> getLocalProfiles() {
    return db.query('local_profiles', orderBy: 'created_at ASC');
  }

  Future<Map<String, Object?>?> getActiveLocalProfile() async {
    final session = await getLocalSession();
    final activeId = session?['active_profile_id'] as String?;
    if (activeId != null) {
      final rows = await db.query(
        'local_profiles',
        where: 'id = ?',
        whereArgs: [activeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }
    final profiles = await getLocalProfiles();
    return profiles.isEmpty ? null : profiles.first;
  }

  Future<void> upsertLocalProfile(Map<String, Object?> record) {
    return db.insert(
      'local_profiles',
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getLocalSession() async {
    final rows = await db.query('local_session', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveLocalSession({
    required String? activeProfileId,
    required bool onboardingCompleted,
    String? activeBookId,
    String? activeMemberId,
  }) {
    return db.insert('local_session', {
      'id': 1,
      'active_profile_id': activeProfileId,
      'active_book_id': activeBookId,
      'active_member_id': activeMemberId,
      'onboarding_completed': onboardingCompleted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getFinancialBooks({
    bool includeDeleted = false,
  }) => db.query(
    'books',
    where: includeDeleted ? null : 'deleted_at IS NULL',
    orderBy: 'created_at ASC',
  );

  Future<void> upsertFinancialBook(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    await db.transaction((txn) async {
      await txn.insert(
        'books',
        record,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) await _enqueueSyncOperation(txn, 'books', record);
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getHouseholdMembers({
    String? bookId,
    bool includeDeleted = false,
  }) {
    final scope = bookId ?? _activeBookId;
    return db.query(
      'household_members',
      where: _scopedWhere(scope, includeDeleted: includeDeleted),
      whereArgs: scope == null ? null : [scope],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> upsertHouseholdMember(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    final bookId = prepared['book_id'] as String?;
    if (bookId == null) throw StateError('An active household is required.');
    final name = (prepared['display_name'] as String).trim();
    if (name.isEmpty) throw StateError('Member name cannot be empty.');
    await db.transaction((txn) async {
      final duplicate = await txn.query(
        'household_members',
        columns: ['id'],
        where:
            'book_id = ? AND display_name = ? COLLATE NOCASE '
            'AND deleted_at IS NULL AND id != ?',
        whereArgs: [bookId, name, prepared['id']],
        limit: 1,
      );
      if (duplicate.isNotEmpty) throw StateError('$name already exists.');
      final saved = {...prepared, 'display_name': name};
      await txn.insert(
        'household_members',
        saved,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(txn, 'household_members', saved);
      }
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> softDeleteHouseholdMember(String id) async {
    final references = await db.query(
      'accounts',
      columns: ['id'],
      where: 'owner_member_id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (references.isNotEmpty) {
      throw StateError('Move this member\'s accounts to Joint before removal.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE household_members SET deleted_at = ?, updated_at = ?, '
        "version = version + 1, sync_status = 'pending' WHERE id = ?",
        [now, now, id],
      );
      final rows = await txn.query(
        'household_members',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await _enqueueSyncOperation(
          txn,
          'household_members',
          rows.first,
          operationType: 'delete',
        );
      }
    });
    onSyncMutation?.call();
  }

  Future<void> ensureHouseholdForProfile(Map<String, Object?> profile) async {
    final currentSession = await getLocalSession();
    var bookId = currentSession?['active_book_id'] as String?;
    var memberId = currentSession?['active_member_id'] as String?;
    final books = await getFinancialBooks();
    if (bookId == null || !books.any((book) => book['id'] == bookId)) {
      if (books.isNotEmpty) {
        bookId = books.first['id'] as String;
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        bookId = const Uuid().v4();
        await upsertFinancialBook({
          'id': bookId,
          'name': 'My Household',
          'base_currency_code':
              profile['default_currency_code'] as String? ?? 'IDR',
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'local_only',
        });
      }
    }
    setActiveBookId(bookId);
    final members = await getHouseholdMembers(bookId: bookId);
    if (memberId == null ||
        !members.any((member) => member['id'] == memberId)) {
      if (members.isNotEmpty) {
        memberId = members.first['id'] as String;
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        memberId = const Uuid().v4();
        await upsertHouseholdMember({
          'id': memberId,
          'book_id': bookId,
          'display_name': profile['display_name'] as String,
          'role': 'owner',
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'local_only',
        });
      }
    }
    await saveLocalSession(
      activeProfileId: profile['id'] as String,
      onboardingCompleted:
          (currentSession?['onboarding_completed'] as num?)?.toInt() == 1,
      activeBookId: bookId,
      activeMemberId: memberId,
    );
  }

  String? _scopedWhere(String? bookId, {required bool includeDeleted}) {
    if (bookId == null) return includeDeleted ? null : 'deleted_at IS NULL';
    return includeDeleted
        ? 'book_id = ?'
        : 'book_id = ? AND deleted_at IS NULL';
  }

  Map<String, Object?> _withActiveBook(Map<String, Object?> record) => {
    ...record,
    if (record['book_id'] == null && _activeBookId != null)
      'book_id': _activeBookId,
  };

  bool _sameAssetDefinitionSeed(
    Map<String, Object?> existing,
    Map<String, Object?> seed,
  ) {
    for (final field in const [
      'display_name',
      'asset_kind',
      'symbol',
      'provider_code',
      'provider_symbol',
      'exchange_code',
      'currency_code',
      'unit',
      'lot_size',
      'online_pricing_enabled',
    ]) {
      if (existing[field] != seed[field]) return false;
    }
    return existing['deleted_at'] == null;
  }

  Future<void> _enqueueSyncOperation(
    DatabaseExecutor executor,
    String entityType,
    Map<String, Object?> record, {
    String? operationType,
    bool knownLinked = false,
  }) async {
    final bookId = entityType == 'books'
        ? record['id'] as String?
        : record['book_id'] as String?;
    final entityId = record['id'] as String?;
    if (bookId == null || entityId == null) return;
    if (!knownLinked) {
      final linked = await executor.query(
        'books',
        columns: ['id'],
        where: 'id = ? AND remote_linked_at IS NOT NULL',
        whereArgs: [bookId],
        limit: 1,
      );
      if (linked.isEmpty) return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final version = (record['version'] as num?)?.toInt() ?? 1;
    await executor.insert('sync_outbox', {
      'operation_id': const Uuid().v4(),
      'book_id': bookId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation_type':
          operationType ?? (record['deleted_at'] == null ? 'upsert' : 'delete'),
      'base_version': version > 0 ? version - 1 : 0,
      'payload_json': jsonEncode(record),
      'created_at': now,
      'updated_at': now,
      'attempt_count': 0,
      'status': 'pending',
    });
  }

  Future<Map<String, Object?>?> getSyncCursor(String bookId) async {
    final rows = await db.query(
      'sync_cursors',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setSyncInitializationState(String bookId, String state) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''
      INSERT INTO sync_cursors(
        book_id, last_server_sequence, initialization_state, updated_at
      ) VALUES (?, 0, ?, ?)
      ON CONFLICT(book_id) DO UPDATE SET
        initialization_state = excluded.initialization_state,
        updated_at = excluded.updated_at
    ''',
      [bookId, state, now],
    );
  }

  Future<List<Map<String, Object?>>> getEligibleSyncOperations(
    String bookId, {
    int limit = 50,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.query(
      'sync_outbox',
      where:
          'book_id = ? AND status IN (?, ?) '
          'AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [bookId, 'pending', 'retry', now],
      orderBy: 'created_at ASC',
      limit: limit.clamp(1, 100),
    );
  }

  Future<int> getPendingSyncCount(String bookId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_outbox '
      "WHERE book_id = ? AND status != 'completed'",
      [bookId],
    );
    return (rows.single['total'] as num).toInt();
  }

  Future<Map<String, int>> getSyncOutboxStatusCounts(String bookId) async {
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS total FROM sync_outbox '
      'WHERE book_id = ? GROUP BY status',
      [bookId],
    );
    return {
      for (final row in rows)
        row['status'] as String: (row['total'] as num).toInt(),
    };
  }

  Future<void> recoverInterruptedSyncOperations(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'sync_outbox',
      {
        'status': 'retry',
        'updated_at': now,
        'next_attempt_at': now,
        'last_error_code': 'interrupted',
        'last_error_message': 'Previous synchronization was interrupted.',
      },
      where: 'book_id = ? AND status = ?',
      whereArgs: [bookId, 'sending'],
    );
  }

  Future<void> markSyncOperationsSending(List<String> operationIds) async {
    if (operationIds.isEmpty) return;
    final placeholders = List.filled(operationIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE sync_outbox SET status = ?, updated_at = ? '
      'WHERE operation_id IN ($placeholders)',
      ['sending', DateTime.now().millisecondsSinceEpoch, ...operationIds],
    );
  }

  Future<void> completeSyncOperation(
    String operationId, {
    int? serverVersion,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_outbox',
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final operation = rows.first;
      await txn.update(
        'sync_outbox',
        {'status': 'completed', 'updated_at': now, 'next_attempt_at': null},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      final newer = await txn.query(
        'sync_outbox',
        columns: ['operation_id'],
        where:
            'entity_type = ? AND entity_id = ? AND operation_id != ? '
            "AND status != 'completed' AND created_at >= ?",
        whereArgs: [
          operation['entity_type'],
          operation['entity_id'],
          operationId,
          operation['created_at'],
        ],
        limit: 1,
      );
      if (newer.isEmpty) {
        final table = _syncTable(operation['entity_type'] as String);
        await txn.rawUpdate(
          'UPDATE $table SET sync_status = ?'
          '${serverVersion == null ? '' : ', version = MAX(version, ?)'} '
          'WHERE id = ?',
          ['synced', ?serverVersion, operation['entity_id']],
        );
      }
    });
  }

  Future<void> scheduleSyncRetry(
    String operationId, {
    required String errorCode,
    required String safeMessage,
    required int nextAttemptAt,
  }) async {
    final terminal =
        errorCode == 'unauthorized' ||
        errorCode.toLowerCase().contains('validation');
    await db.rawUpdate(
      'UPDATE sync_outbox SET status = ?, attempt_count = attempt_count + 1, '
      'next_attempt_at = ?, last_error_code = ?, last_error_message = ?, '
      'updated_at = ? WHERE operation_id = ?',
      [
        terminal ? 'conflict' : 'retry',
        nextAttemptAt,
        errorCode,
        safeMessage,
        DateTime.now().millisecondsSinceEpoch,
        operationId,
      ],
    );
  }

  Future<void> recordSyncConflict(Map<String, Object?> record) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert('sync_conflicts', {
        'id': const Uuid().v4(),
        ...record,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'sync_outbox',
        {
          'status': 'conflict',
          'updated_at': now,
          'last_error_code': 'version_conflict',
          'last_error_message': 'A newer server version needs review.',
        },
        where: 'operation_id = ?',
        whereArgs: [record['operation_id']],
      );
    });
  }

  Future<int> getUnresolvedSyncConflictCount(String bookId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_conflicts '
      'WHERE book_id = ? AND resolved_at IS NULL',
      [bookId],
    );
    return (rows.single['total'] as num).toInt();
  }

  Future<List<Map<String, Object?>>> getSyncConflicts(String bookId) =>
      db.query(
        'sync_conflicts',
        where: 'book_id = ? AND resolution_status != ?',
        whereArgs: [bookId, 'resolved'],
        orderBy: 'created_at ASC',
      );

  Future<bool> beginSyncConflictResolution(
    String id,
    String operationId,
  ) async {
    final changed = await db.update(
      'sync_conflicts',
      {
        'resolution_status': 'resolving',
        'resolution_operation_id': operationId,
      },
      where: 'id = ? AND resolution_status IN (?, ?)',
      whereArgs: [id, 'unresolved', 'resolutionFailed'],
    );
    return changed == 1;
  }

  Future<void> failSyncConflictResolution(String id) => db.update(
    'sync_conflicts',
    {'resolution_status': 'resolutionFailed'},
    where: 'id = ? AND resolution_status = ?',
    whereArgs: [id, 'resolving'],
  );

  Future<void> completeSyncConflictResolution(
    String id, {
    required String resolution,
    required Map<String, Object?> canonicalPayload,
    required int serverSequence,
  }) async {
    await db.transaction((txn) async {
      final conflicts = await txn.query(
        'sync_conflicts',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (conflicts.isEmpty ||
          conflicts.first['resolution_status'] != 'resolving') {
        throw StateError('Conflict is no longer resolving.');
      }
      final conflict = conflicts.first;
      final table = _syncTable(conflict['entity_type'] as String);
      final resolvedRecord = <String, Object?>{
        ...canonicalPayload,
        'sync_status': 'synced',
      };
      if (conflict['entity_type'] == 'transfer_links') {
        final existing = await txn.query(
          table,
          columns: const ['id'],
          where: 'id = ?',
          whereArgs: [canonicalPayload['id']],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert(
            table,
            resolvedRecord,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          await txn.update(
            table,
            resolvedRecord,
            where: 'id = ?',
            whereArgs: [canonicalPayload['id']],
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      } else {
        await txn.insert(
          table,
          resolvedRecord,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _validateInternalTransfersInDatabase(
        txn,
        conflict['book_id'] as String,
      );
      await txn.update(
        'sync_outbox',
        {
          'status': 'completed',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'operation_id = ?',
        whereArgs: [conflict['operation_id']],
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'sync_conflicts',
        {
          'resolution_status': 'resolved',
          'resolution': resolution,
          'resolved_at': now,
        },
        where: 'id = ? AND resolution_status = ?',
        whereArgs: [id, 'resolving'],
      );
      await txn.rawInsert(
        '''INSERT INTO sync_cursors(book_id,last_server_sequence,initialization_state,updated_at)
        VALUES (?,?,'ready',?) ON CONFLICT(book_id) DO UPDATE SET
        last_server_sequence = MAX(last_server_sequence, excluded.last_server_sequence), updated_at = excluded.updated_at''',
        [conflict['book_id'], serverSequence, now],
      );
    });
  }

  Future<void> applyRemoteSyncBatch(
    String bookId, {
    required List<Map<String, Object?>> changes,
    required int finalSequence,
  }) async {
    await db.transaction((txn) async {
      for (final change in changes) {
        final entityType = change['entity_type'] as String;
        final table = _syncTable(entityType);
        final payload = Map<String, Object?>.of(
          (change['payload'] as Map).cast<String, Object?>(),
        );
        if (payload['id'] != change['entity_id']) {
          throw StateError('Remote entity identity mismatch.');
        }
        if ((entityType == 'books' && payload['id'] != bookId) ||
            (entityType != 'books' && payload['book_id'] != bookId)) {
          throw StateError('Remote book scope mismatch.');
        }
        final existing = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [payload['id']],
          limit: 1,
        );
        if (entityType == 'transactions' &&
            !payload.containsKey('category_id') &&
            existing.isNotEmpty &&
            payload.containsKey('category') &&
            payload['category'] != existing.first['category']) {
          payload['category_id'] = null;
        }
        final saved = <String, Object?>{
          if (existing.isNotEmpty) ...existing.first,
          ...payload,
          'sync_status': 'synced',
        };
        if (entityType == 'transfer_links') {
          if (existing.isEmpty) {
            await txn.insert(
              table,
              saved,
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
          } else {
            await txn.update(
              table,
              saved,
              where: 'id = ?',
              whereArgs: [payload['id']],
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
          }
        } else {
          await txn.insert(
            table,
            saved,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await _validateTransactionCategoriesInBook(txn, bookId);
      await _validateInternalTransfersInDatabase(txn, bookId);
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.rawInsert(
        '''
        INSERT INTO sync_cursors(
          book_id, last_server_sequence, initialization_state, updated_at
        ) VALUES (?, ?, 'ready', ?)
        ON CONFLICT(book_id) DO UPDATE SET
          last_server_sequence = excluded.last_server_sequence,
          updated_at = excluded.updated_at
      ''',
        [bookId, finalSequence, now],
      );
    });
  }

  Future<void> _validateInternalTransfersInDatabase(
    DatabaseExecutor executor,
    String bookId,
  ) async {
    final links = await executor.query(
      'transfer_links',
      where: 'book_id = ? AND deleted_at IS NULL',
      whereArgs: [bookId],
    );
    if (links.isEmpty) return;
    final transactions = {
      for (final row in await executor.query(
        'transactions',
        where: 'book_id = ?',
        whereArgs: [bookId],
      ))
        row['id']: row,
    };
    final accounts = {
      for (final row in await executor.query(
        'accounts',
        where: 'book_id = ?',
        whereArgs: [bookId],
      ))
        row['id']: row,
    };
    final legIds = <Object?>{};
    for (final link in links) {
      final outgoing = transactions[link['outgoing_transaction_id']];
      final incoming = transactions[link['incoming_transaction_id']];
      final source = accounts[link['source_account_id']];
      final destination = accounts[link['destination_account_id']];
      final amount = (link['amount'] as num?)?.toInt();
      final validIdentity =
          legIds.add(link['outgoing_transaction_id']) &&
          legIds.add(link['incoming_transaction_id']);
      if (outgoing == null ||
          incoming == null ||
          source == null ||
          destination == null ||
          outgoing['deleted_at'] != null ||
          incoming['deleted_at'] != null ||
          source['deleted_at'] != null ||
          destination['deleted_at'] != null ||
          outgoing['transaction_type'] != 'expense' ||
          incoming['transaction_type'] != 'income' ||
          amount == null ||
          amount <= 0 ||
          outgoing['amount'] != amount ||
          incoming['amount'] != amount ||
          outgoing['account'] != source['name'] ||
          incoming['account'] != destination['name'] ||
          source['currency_code'] != destination['currency_code'] ||
          source['currency_code'] != link['currency_code'] ||
          link['source_account_id'] == link['destination_account_id'] ||
          link['outgoing_transaction_id'] == link['incoming_transaction_id'] ||
          !validIdentity) {
        throw StateError(
          'Remote internal transfer ${link['id']} is invalid or incomplete.',
        );
      }
    }
  }

  Future<void> _validateTransactionCategory(
    DatabaseExecutor executor,
    Map<String, Object?> transaction,
  ) async {
    final categoryId = transaction['category_id'] as String?;
    if (categoryId == null) return;
    final bookId = transaction['book_id'] as String?;
    final type = transaction['transaction_type'] as String?;
    if (bookId == null || (type != 'expense' && type != 'income')) {
      throw StateError('The transaction category is invalid.');
    }
    final category = await executor.query(
      'categories',
      columns: const ['id'],
      where: 'id = ? AND book_id = ? AND category_type = ?',
      whereArgs: [categoryId, bookId, type],
      limit: 1,
    );
    if (category.isEmpty) {
      throw StateError(
        'The transaction category belongs to another household or type.',
      );
    }
  }

  Future<void> _validateTransactionCategoriesInBook(
    DatabaseExecutor executor,
    String bookId,
  ) async {
    final invalid = await executor.rawQuery(
      '''SELECT t.id FROM transactions t
         LEFT JOIN categories c ON c.id = t.category_id
         WHERE t.book_id = ? AND t.category_id IS NOT NULL
           AND (c.id IS NULL OR c.book_id <> t.book_id
                OR c.category_type <> t.transaction_type)
         LIMIT 1''',
      [bookId],
    );
    if (invalid.isNotEmpty) {
      throw StateError(
        'A transaction category belongs to another household or type.',
      );
    }
  }

  String _syncTable(String entityType) {
    if (!const {
      'books',
      'household_members',
      'accounts',
      'categories',
      'projects',
      'transactions',
      'asset_definitions',
      'monthly_category_budgets',
      'transaction_import_rules',
      'transfer_links',
      'import_review_sessions',
      'import_review_drafts',
    }.contains(entityType)) {
      throw ArgumentError.value(entityType, 'entityType');
    }
    return entityType;
  }

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
    if (entity == 'accounts') {
      final accounts = await getAccounts();
      return accounts.map((row) => row['name'] as String).toList();
    }
    final table = _table(entity);
    final whereArgs = <Object?>[];
    if (_activeBookId case final activeBookId?) {
      whereArgs.add(activeBookId);
    }
    if (categoryType != null) whereArgs.add(categoryType);
    final rows = await db.query(
      table,
      columns: ['name'],
      where: [
        if (_activeBookId != null) 'book_id = ?',
        'deleted_at IS NULL',
        if (categoryType != null) 'category_type = ?',
      ].join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<List<Map<String, Object?>>> getProjectRecords() async {
    final whereArgs = <Object?>[];
    if (_activeBookId case final activeBookId?) whereArgs.add(activeBookId);
    return db.query(
      'projects',
      columns: const ['id', 'name'],
      where: [
        if (_activeBookId != null) 'book_id = ?',
        'deleted_at IS NULL',
      ].join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getCategoryRecords({
    bool includeDeleted = false,
    String? categoryType,
    String? bookId,
  }) {
    final scope = bookId ?? _activeBookId;
    final where = <String>[];
    final whereArgs = <Object?>[];
    if (scope != null) {
      where.add('book_id = ?');
      whereArgs.add(scope);
    }
    if (!includeDeleted) where.add('deleted_at IS NULL');
    if (categoryType != null) {
      where.add('category_type = ?');
      whereArgs.add(categoryType);
    }
    return db.query(
      'categories',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getBudgetCopyCategoryRecords(
    Iterable<String> categoryIds,
  ) {
    final ids = categoryIds.toSet().toList();
    if (ids.isEmpty) return Future.value(const []);
    return db.query(
      'categories',
      where: 'id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: ids,
    );
  }

  Future<List<Map<String, Object?>>> getMonthlyCategoryBudgets({
    bool includeDeleted = false,
    String? bookId,
    String? monthStart,
  }) {
    final scope = bookId ?? _activeBookId;
    final where = <String>[];
    final whereArgs = <Object?>[];
    if (scope != null) {
      where.add('book_id = ?');
      whereArgs.add(scope);
    }
    if (!includeDeleted) where.add('deleted_at IS NULL');
    if (monthStart != null) {
      where.add('month_start = ?');
      whereArgs.add(monthStart);
    }
    return db.query(
      'monthly_category_budgets',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'month_start, category_id, id',
    );
  }

  Future<Map<String, Object?>> upsertMonthlyCategoryBudget(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    final bookId = prepared['book_id'] as String?;
    final note = prepared['note'] as String?;
    final monthStart = prepared['month_start'] as String;
    final parsedMonth = DateTime.tryParse(monthStart);
    if (bookId == null || (prepared['limit_minor'] as num).toInt() <= 0) {
      throw StateError('A positive household budget is required.');
    }
    if (note != null && note.length > 120) {
      throw StateError('A budget note cannot exceed 120 characters.');
    }
    if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(monthStart) ||
        parsedMonth == null ||
        parsedMonth.day != 1) {
      throw StateError('A budget month must use YYYY-MM-01.');
    }
    late Map<String, Object?> saved;
    await db.transaction((txn) async {
      final book = await txn.query(
        'books',
        columns: ['base_currency_code'],
        where: 'id = ?',
        whereArgs: [bookId],
        limit: 1,
      );
      if (book.isEmpty ||
          prepared['currency_code'] != book.single['base_currency_code']) {
        throw StateError('Budgets must use the household base currency.');
      }
      final sameId = await txn.query(
        'monthly_category_budgets',
        where: 'id = ?',
        whereArgs: [prepared['id']],
        limit: 1,
      );
      if (sameId.isNotEmpty &&
          (sameId.single['book_id'] != bookId ||
              sameId.single['category_id'] != prepared['category_id'] ||
              sameId.single['month_start'] != prepared['month_start'] ||
              sameId.single['currency_code'] != prepared['currency_code'])) {
        throw StateError('Budget identity fields cannot be changed.');
      }
      final category = await txn.query(
        'categories',
        where: 'id = ? AND book_id = ? AND category_type = ?',
        whereArgs: [prepared['category_id'], bookId, 'expense'],
        limit: 1,
      );
      if (category.isEmpty ||
          (sameId.isEmpty && category.single['deleted_at'] != null)) {
        throw StateError('The budget category is invalid for this household.');
      }
      final duplicate = await txn.query(
        'monthly_category_budgets',
        where:
            'book_id = ? AND category_id = ? AND month_start = ? '
            'AND deleted_at IS NULL AND id <> ?',
        whereArgs: [
          bookId,
          prepared['category_id'],
          prepared['month_start'],
          prepared['id'],
        ],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError(
          'A budget already exists for this category and month.',
        );
      }
      final deletedMatch = sameId.isNotEmpty
          ? const <Map<String, Object?>>[]
          : await txn.query(
              'monthly_category_budgets',
              where:
                  'book_id = ? AND category_id = ? AND month_start = ? '
                  'AND deleted_at IS NOT NULL',
              whereArgs: [
                bookId,
                prepared['category_id'],
                prepared['month_start'],
              ],
              orderBy: 'updated_at DESC',
              limit: 1,
            );
      if (deletedMatch.isEmpty) {
        saved = prepared;
      } else {
        final deleted = deletedMatch.first;
        final requestedVersion = (prepared['version'] as num).toInt();
        final restoredVersion = (deleted['version'] as num).toInt() + 1;
        saved = {
          ...prepared,
          'id': deleted['id'],
          'created_at': deleted['created_at'],
          'deleted_at': null,
          'version': requestedVersion > restoredVersion
              ? requestedVersion
              : restoredVersion,
        };
      }
      await txn.insert(
        'monthly_category_budgets',
        saved,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(txn, 'monthly_category_budgets', saved);
      }
    });
    if (enqueueSync) onSyncMutation?.call();
    return saved;
  }

  Future<List<Map<String, Object?>>> copyMonthlyCategoryBudgets(
    List<Map<String, Object?>> records,
  ) async {
    if (records.isEmpty) return const [];
    final copied = <Map<String, Object?>>[];
    await db.transaction((txn) async {
      for (final record in records) {
        var prepared = _withActiveBook(record);
        final bookId = prepared['book_id'] as String?;
        final note = prepared['note'] as String?;
        final monthStart = prepared['month_start'] as String;
        final parsedMonth = DateTime.tryParse(monthStart);
        if (bookId == null || (prepared['limit_minor'] as num).toInt() <= 0) {
          throw StateError('A positive household budget is required.');
        }
        if (note != null && note.length > 120) {
          throw StateError('A budget note cannot exceed 120 characters.');
        }
        if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(monthStart) ||
            parsedMonth == null ||
            parsedMonth.day != 1) {
          throw StateError('A budget month must use YYYY-MM-01.');
        }
        final book = await txn.query(
          'books',
          columns: ['base_currency_code'],
          where: 'id = ?',
          whereArgs: [bookId],
          limit: 1,
        );
        if (book.isEmpty ||
            prepared['currency_code'] != book.single['base_currency_code']) {
          throw StateError('Budgets must use the household base currency.');
        }
        final sameId = await txn.query(
          'monthly_category_budgets',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [prepared['id']],
          limit: 1,
        );
        if (sameId.isNotEmpty) {
          throw StateError('A generated budget identity already exists.');
        }
        final category = await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [prepared['category_id']],
          limit: 1,
        );
        if (category.isEmpty) {
          throw StateError('A copied budget references a missing category.');
        }
        if (category.single['book_id'] != bookId) {
          throw StateError('A copied budget references another household.');
        }
        if (category.single['category_type'] != 'expense' ||
            category.single['deleted_at'] != null) {
          throw StateError('A copied budget category is unavailable.');
        }
        final duplicate = await txn.query(
          'monthly_category_budgets',
          columns: ['id'],
          where:
              'book_id = ? AND category_id = ? AND month_start = ? '
              'AND deleted_at IS NULL',
          whereArgs: [bookId, prepared['category_id'], monthStart],
          limit: 1,
        );
        if (duplicate.isNotEmpty) continue;
        final deletedMatch = await txn.query(
          'monthly_category_budgets',
          where:
              'book_id = ? AND category_id = ? AND month_start = ? '
              'AND deleted_at IS NOT NULL',
          whereArgs: [bookId, prepared['category_id'], monthStart],
          orderBy: 'updated_at DESC',
          limit: 1,
        );
        if (deletedMatch.isNotEmpty) {
          final deleted = deletedMatch.first;
          prepared = {
            ...prepared,
            'id': deleted['id'],
            'created_at': deleted['created_at'],
            'deleted_at': null,
            'version': (deleted['version'] as num).toInt() + 1,
          };
        }
        await txn.insert(
          'monthly_category_budgets',
          prepared,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueueSyncOperation(txn, 'monthly_category_budgets', prepared);
        copied.add(Map<String, Object?>.of(prepared));
      }
    });
    if (copied.isNotEmpty) onSyncMutation?.call();
    return copied;
  }

  Future<void> softDeleteMonthlyCategoryBudget(String id, int deletedAt) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'monthly_category_budgets',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final saved = <String, Object?>{
        ...rows.single,
        'deleted_at': deletedAt,
        'updated_at': deletedAt,
        'version': (rows.single['version'] as num).toInt() + 1,
        'sync_status': 'pending',
      };
      await txn.update(
        'monthly_category_budgets',
        saved,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _enqueueSyncOperation(
        txn,
        'monthly_category_budgets',
        saved,
        operationType: 'delete',
      );
    });
    onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getImportReviewSessions({
    bool includeDeleted = false,
    String? bookId,
    String? state,
  }) {
    final scope = bookId ?? _activeBookId;
    final where = <String>[];
    final args = <Object?>[];
    if (scope != null) {
      where.add('book_id = ?');
      args.add(scope);
    }
    if (!includeDeleted) where.add('deleted_at IS NULL');
    if (state != null) {
      where.add('state = ?');
      args.add(state);
    }
    return db.query(
      'import_review_sessions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC, id',
    );
  }

  Future<List<Map<String, Object?>>> getImportReviewDrafts({
    required String sessionId,
    bool includeDeleted = false,
  }) => db.query(
    'import_review_drafts',
    where: 'session_id = ?${includeDeleted ? '' : ' AND deleted_at IS NULL'}',
    whereArgs: [sessionId],
    orderBy: 'source_index, id',
  );

  Future<List<Map<String, Object?>>> getAllImportReviewDrafts({
    required String bookId,
    bool includeDeleted = false,
  }) => db.query(
    'import_review_drafts',
    where: 'book_id = ?${includeDeleted ? '' : ' AND deleted_at IS NULL'}',
    whereArgs: [bookId],
    orderBy: 'session_id, source_index, id',
  );

  Future<void> saveImportReviewSessionAtomic({
    required Map<String, Object?> session,
    required List<Map<String, Object?>> drafts,
    bool enqueueSync = true,
  }) async {
    final preparedSession = _withActiveBook(session);
    final bookId = preparedSession['book_id'] as String?;
    if (bookId == null) {
      throw StateError('An import session requires a household.');
    }
    await db.transaction((txn) async {
      final linked =
          enqueueSync &&
          (await txn.query(
            'books',
            columns: ['id'],
            where: 'id = ? AND remote_linked_at IS NOT NULL',
            whereArgs: [bookId],
            limit: 1,
          )).isNotEmpty;
      final existing = await txn.query(
        'import_review_sessions',
        where: 'id = ?',
        whereArgs: [preparedSession['id']],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final current = existing.single;
        if (current['book_id'] != bookId ||
            current['source_fingerprint'] !=
                preparedSession['source_fingerprint']) {
          throw StateError('Import session identity cannot change.');
        }
        final previousState = current['state'] as String;
        final nextState = preparedSession['state'] as String;
        final validTransition =
            previousState == nextState ||
            (previousState == 'pendingReview' &&
                (nextState == 'readyToCommit' || nextState == 'discarded')) ||
            (previousState == 'readyToCommit' && nextState == 'completed');
        if (!validTransition) {
          throw StateError('Invalid import review lifecycle transition.');
        }
      }
      final memberId = preparedSession['created_by_member_id'] as String?;
      if (memberId != null) {
        final member = await txn.query(
          'household_members',
          columns: ['id'],
          where: 'id = ? AND book_id = ? AND deleted_at IS NULL',
          whereArgs: [memberId, bookId],
          limit: 1,
        );
        if (member.isEmpty) {
          throw StateError('The import creator is unavailable.');
        }
      }
      final accountId = preparedSession['destination_account_id'] as String?;
      if (accountId != null) {
        final account = await txn.query(
          'accounts',
          columns: ['id'],
          where: 'id = ? AND book_id = ? AND deleted_at IS NULL',
          whereArgs: [accountId, bookId],
          limit: 1,
        );
        if (account.isEmpty) {
          throw StateError('The import account is unavailable.');
        }
      }
      final categoryIds = drafts
          .map((draft) => draft['category_id'] as String?)
          .whereType<String>()
          .toSet();
      final categories = <String, String>{};
      final categoryList = categoryIds.toList();
      for (var offset = 0; offset < categoryList.length; offset += 900) {
        final end = offset + 900 < categoryList.length
            ? offset + 900
            : categoryList.length;
        final chunk = categoryList.sublist(offset, end);
        final rows = await txn.query(
          'categories',
          columns: ['id', 'category_type'],
          where:
              'book_id = ? AND deleted_at IS NULL AND id IN (${List.filled(chunk.length, '?').join(', ')})',
          whereArgs: [bookId, ...chunk],
        );
        for (final row in rows) {
          categories[row['id']! as String] = row['category_type']! as String;
        }
      }
      await txn.insert(
        'import_review_sessions',
        preparedSession,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (linked) {
        await _enqueueSyncOperation(
          txn,
          'import_review_sessions',
          preparedSession,
          knownLinked: true,
        );
      }
      for (final draft in drafts) {
        final preparedDraft = _withActiveBook(draft);
        if (preparedDraft['book_id'] != bookId ||
            preparedDraft['session_id'] != preparedSession['id']) {
          throw StateError(
            'An import draft must belong to its session household.',
          );
        }
        final categoryId = preparedDraft['category_id'] as String?;
        if (categoryId != null &&
            categories[categoryId] != preparedDraft['transaction_type']) {
          throw StateError('The import category is unavailable.');
        }
        final transactionId =
            preparedDraft['deterministic_transaction_id'] as String?;
        final identityAccountId =
            preparedDraft['deterministic_transaction_account_id'] as String?;
        if ((transactionId == null) != (identityAccountId == null)) {
          throw StateError(
            'Import transaction identity and account binding must be resolved together.',
          );
        }
        if (identityAccountId != null) {
          if (identityAccountId != accountId) {
            throw StateError(
              'The import identity account must match the session account.',
            );
          }
          final identityAccount = await txn.query(
            'accounts',
            columns: ['id'],
            where: 'id = ? AND book_id = ? AND deleted_at IS NULL',
            whereArgs: [identityAccountId, bookId],
            limit: 1,
          );
          if (identityAccount.isEmpty) {
            throw StateError(
              'The import identity account belongs to another household.',
            );
          }
        }
        final existingDraft = await txn.query(
          'import_review_drafts',
          where: 'id = ?',
          whereArgs: [preparedDraft['id']],
          limit: 1,
        );
        if (existingDraft.isNotEmpty) {
          final currentDraft = existingDraft.single;
          if (currentDraft['session_id'] != preparedDraft['session_id'] ||
              currentDraft['book_id'] != preparedDraft['book_id'] ||
              currentDraft['source_row_identity'] !=
                  preparedDraft['source_row_identity'] ||
              currentDraft['source_row_key'] !=
                  preparedDraft['source_row_key']) {
            throw StateError('Import draft source identity cannot change.');
          }
          if (existing.single['state'] == 'completed' &&
              (currentDraft['deterministic_transaction_id'] != transactionId ||
                  currentDraft['deterministic_transaction_account_id'] !=
                      identityAccountId)) {
            throw StateError(
              'A completed import transaction identity cannot change.',
            );
          }
        }
        await txn.insert(
          'import_review_drafts',
          preparedDraft,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (linked) {
          await _enqueueSyncOperation(
            txn,
            'import_review_drafts',
            preparedDraft,
            knownLinked: true,
          );
        }
      }
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> discardImportReviewSession(
    String sessionId,
    int discardedAt, {
    bool enqueueSync = true,
  }) async {
    await db.transaction((txn) async {
      final sessions = await txn.query(
        'import_review_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (sessions.isEmpty || sessions.single['deleted_at'] != null) return;
      if (sessions.single['state'] != 'pendingReview') {
        throw StateError('Only a pending import can be discarded.');
      }
      final session = <String, Object?>{
        ...sessions.single,
        'state': 'discarded',
        'deleted_at': discardedAt,
        'updated_at': discardedAt,
        'version': (sessions.single['version'] as num).toInt() + 1,
        'sync_status': 'pending',
      };
      final linked =
          enqueueSync &&
          (await txn.query(
            'books',
            columns: ['id'],
            where: 'id = ? AND remote_linked_at IS NOT NULL',
            whereArgs: [session['book_id']],
            limit: 1,
          )).isNotEmpty;
      await txn.update(
        'import_review_sessions',
        session,
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      final rows = await txn.query(
        'import_review_drafts',
        where: 'session_id = ? AND deleted_at IS NULL',
        whereArgs: [sessionId],
      );
      for (final row in rows) {
        final draft = <String, Object?>{
          ...row,
          'deleted_at': discardedAt,
          'updated_at': discardedAt,
          'version': (row['version'] as num).toInt() + 1,
          'sync_status': 'pending',
        };
        await txn.update(
          'import_review_drafts',
          draft,
          where: 'id = ?',
          whereArgs: [draft['id']],
        );
        if (linked) {
          await _enqueueSyncOperation(
            txn,
            'import_review_drafts',
            draft,
            operationType: 'delete',
            knownLinked: true,
          );
        }
      }
      if (linked) {
        await _enqueueSyncOperation(
          txn,
          'import_review_sessions',
          session,
          operationType: 'delete',
          knownLinked: true,
        );
      }
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getTransactionImportRules({
    bool includeDeleted = false,
    bool activeOnly = false,
    String? bookId,
  }) {
    final scope = bookId ?? _activeBookId;
    final where = <String>[];
    final args = <Object?>[];
    if (scope != null) {
      where.add('book_id = ?');
      args.add(scope);
    }
    if (!includeDeleted) where.add('deleted_at IS NULL');
    if (activeOnly) where.add('enabled = 1');
    return db.query(
      'transaction_import_rules',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'priority DESC, name COLLATE NOCASE, id',
    );
  }

  Future<Map<String, Object?>> upsertTransactionImportRule(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    final bookId = prepared['book_id'] as String?;
    if (bookId == null || (prepared['pattern_key'] as String).isEmpty) {
      throw StateError('An import rule requires a household and pattern.');
    }
    late Map<String, Object?> saved;
    await db.transaction((txn) async {
      final category = await txn.query(
        'categories',
        where: 'id = ? AND book_id = ? AND category_type = ?',
        whereArgs: [
          prepared['category_id'],
          bookId,
          prepared['transaction_type'],
        ],
        limit: 1,
      );
      if (category.isEmpty) {
        throw StateError(
          'The import rule category belongs to another household or type.',
        );
      }
      final accountId = prepared['account_id'] as String?;
      if (accountId != null) {
        final account = await txn.query(
          'accounts',
          where: 'id = ? AND book_id = ?',
          whereArgs: [accountId, bookId],
          limit: 1,
        );
        if (account.isEmpty) {
          throw StateError(
            'The import rule account belongs to another household.',
          );
        }
      }
      final sameId = await txn.query(
        'transaction_import_rules',
        where: 'id = ?',
        whereArgs: [prepared['id']],
        limit: 1,
      );
      if (sameId.isNotEmpty && sameId.single['book_id'] != bookId) {
        throw StateError('An import rule cannot move between households.');
      }
      final semanticWhere =
          '''book_id = ? AND transaction_type = ? AND match_field = ?
        AND match_operator = ? AND pattern_key = ?
        AND IFNULL(account_id, '') = IFNULL(?, '')''';
      final semanticArgs = <Object?>[
        bookId,
        prepared['transaction_type'],
        prepared['match_field'],
        prepared['match_operator'],
        prepared['pattern_key'],
        accountId,
      ];
      final duplicate = await txn.query(
        'transaction_import_rules',
        where: '$semanticWhere AND deleted_at IS NULL AND id <> ?',
        whereArgs: [...semanticArgs, prepared['id']],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError(
          'An active import rule with this match already exists.',
        );
      }
      final deletedMatch = sameId.isNotEmpty
          ? const <Map<String, Object?>>[]
          : await txn.query(
              'transaction_import_rules',
              where: '$semanticWhere AND deleted_at IS NOT NULL',
              whereArgs: semanticArgs,
              orderBy: 'updated_at DESC',
              limit: 1,
            );
      saved = deletedMatch.isEmpty
          ? prepared
          : {
              ...prepared,
              'id': deletedMatch.single['id'],
              'created_at': deletedMatch.single['created_at'],
              'deleted_at': null,
              'version': (deletedMatch.single['version'] as num).toInt() + 1,
            };
      await txn.insert(
        'transaction_import_rules',
        saved,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(txn, 'transaction_import_rules', saved);
      }
    });
    if (enqueueSync) onSyncMutation?.call();
    return saved;
  }

  Future<void> softDeleteTransactionImportRule(
    String id,
    int deletedAt, {
    bool enqueueSync = true,
  }) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transaction_import_rules',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['deleted_at'] != null) return;
      final saved = <String, Object?>{
        ...rows.single,
        'deleted_at': deletedAt,
        'updated_at': deletedAt,
        'version': (rows.single['version'] as num).toInt() + 1,
        'sync_status': 'pending',
      };
      await txn.update(
        'transaction_import_rules',
        saved,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (enqueueSync) {
        await _enqueueSyncOperation(
          txn,
          'transaction_import_rules',
          saved,
          operationType: 'delete',
        );
      }
    });
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> saveMasterName(
    String entity,
    String name, {
    String? previousName,
    String? categoryType,
  }) async {
    if (entity == 'accounts') {
      final existing = await getAccounts();
      if (previousName != null) {
        final row = existing.firstWhere(
          (item) => item['name'] == previousName,
          orElse: () => const <String, Object?>{},
        );
        if (row.isNotEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          await upsertAccount({
            ...row,
            'name': name,
            'updated_at': now,
            'version': (row['version'] as num).toInt() + 1,
            'sync_status': 'pending',
          });
          return;
        }
      }
      final now = DateTime.now();
      await upsertAccount({
        'id': const Uuid().v4(),
        'name': name,
        'account_type': 'asset',
        'currency_code': 'IDR',
        'opening_balance': 0,
        'opening_balance_date': null,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'version': 1,
        'device_id': 'local-device',
        'sync_status': 'pending',
      });
      return;
    }
    final table = _table(entity);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      Map<String, Object?>? saved;
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
            ? '${_activeBookId == null ? '' : 'book_id = ? AND '}'
                  'name = ? AND deleted_at IS NULL AND category_type = ?'
            : '${_activeBookId == null ? '' : 'book_id = ? AND '}'
                  'name = ? AND deleted_at IS NULL';
        final whereArgs = <Object?>[
          if (_activeBookId != null) _activeBookId,
          previousName,
          if (isCategory) categoryType,
        ];
        final existingRows = await txn.query(
          table,
          where: where,
          whereArgs: whereArgs,
          limit: 1,
        );
        await txn.rawUpdate(
          'UPDATE $table SET name = ?, updated_at = ?, '
          "version = version + 1, sync_status = 'pending' WHERE $where",
          [name, now, ...whereArgs],
        );
        if (existingRows.isNotEmpty) {
          saved = {
            ...existingRows.first,
            'name': name,
            'updated_at': now,
            'version':
                ((existingRows.first['version'] as num?)?.toInt() ?? 0) + 1,
            'sync_status': 'pending',
          };
        }
      } else {
        saved = <String, Object?>{
          'id': const Uuid().v4(),
          'book_id': _activeBookId,
          'name': name,
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'pending',
          if (entity == 'projects') 'status': 'active',
          if (entity == 'categories')
            'category_type': categoryType ?? 'expense',
        };
        await txn.insert(
          table,
          saved,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      if (saved != null) await _enqueueSyncOperation(txn, entity, saved);
    });
    onSyncMutation?.call();
  }

  Future<void> ensureMasterSeeds(
    String entity,
    List<String> names, {
    String? categoryType,
  }) async {
    if (entity == 'accounts') {
      await ensureAccountSeeds(names);
      return;
    }
    if ((await getMasterNames(entity, categoryType: categoryType)).isNotEmpty) {
      return;
    }
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final name in names) {
        final record = <String, Object?>{
          'id': const Uuid().v4(),
          'book_id': _activeBookId,
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

bool _backupRecordsEqual(
  Map<String, Object?> stored,
  Map<String, Object?> incoming,
) {
  for (final entry in incoming.entries) {
    final left = stored[entry.key];
    final right = entry.value;
    if (left is num && right is bool) {
      if (left != (right ? 1 : 0)) return false;
    } else if (left is bool && right is num) {
      if ((left ? 1 : 0) != right) return false;
    } else if (left != right) {
      return false;
    }
  }
  return true;
}
