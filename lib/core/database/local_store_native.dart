import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'household_schema_native.dart';
import 'sync_schema_native.dart';

class LocalStore {
  LocalStore({this.databasePath});
  static const schemaVersion = 15;
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
    final resolvedDatabasePath =
        databasePath ?? p.join(await getDatabasesPath(), 'pilgrim_tracker.db');

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
        await db.execute('''
          CREATE TABLE IF NOT EXISTS asset_market_prices (
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
      },
    );
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
    return db.insert(
      'asset_market_prices',
      _withActiveBook(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<void> _enqueueSyncOperation(
    DatabaseExecutor executor,
    String entityType,
    Map<String, Object?> record, {
    String? operationType,
  }) async {
    final bookId = entityType == 'books'
        ? record['id'] as String?
        : record['book_id'] as String?;
    final entityId = record['id'] as String?;
    if (bookId == null || entityId == null) return;
    final linked = await executor.query(
      'books',
      columns: ['id'],
      where: 'id = ? AND remote_linked_at IS NOT NULL',
      whereArgs: [bookId],
      limit: 1,
    );
    if (linked.isEmpty) return;
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
        final saved = <String, Object?>{
          if (existing.isNotEmpty) ...existing.first,
          ...payload,
          'sync_status': 'synced',
        };
        await txn.insert(
          table,
          saved,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
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

  String _syncTable(String entityType) {
    if (!const {
      'books',
      'household_members',
      'accounts',
      'categories',
      'projects',
      'transactions',
      'asset_definitions',
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
