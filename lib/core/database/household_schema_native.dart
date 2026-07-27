import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class HouseholdSchemaNative {
  static const migratedBookId = 'legacy-default-book';
  static const migratedOwnerMemberId = 'legacy-owner-member';

  static Future<void> createMembersTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS household_members (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        auth_user_id TEXT,
        role TEXT NOT NULL DEFAULT 'member',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only'
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_household_members_name '
      'ON household_members(book_id, display_name COLLATE NOCASE) '
      'WHERE deleted_at IS NULL',
    );
  }

  static Future<void> upgradeToV12(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_currency_code TEXT NOT NULL DEFAULT 'IDR',
        remote_linked_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only'
      )
    ''');
    await _addColumnIfMissing(
      db,
      'books',
      'base_currency_code',
      "TEXT NOT NULL DEFAULT 'IDR'",
    );
    await _addColumnIfMissing(db, 'accounts', 'owner_member_id', 'TEXT');
    await _addColumnIfMissing(db, 'transactions', 'book_id', 'TEXT');
    await _addColumnIfMissing(
      db,
      'transactions',
      'entered_by_member_id',
      'TEXT',
    );
    await _addColumnIfMissing(db, 'asset_definitions', 'book_id', 'TEXT');
    await _addColumnIfMissing(db, 'asset_market_prices', 'book_id', 'TEXT');
    await _addColumnIfMissing(db, 'local_session', 'active_book_id', 'TEXT');
    await _addColumnIfMissing(db, 'local_session', 'active_member_id', 'TEXT');
    await createMembersTable(db);

    final now = DateTime.now().millisecondsSinceEpoch;
    final profiles = await db.query(
      'local_profiles',
      orderBy: 'created_at ASC',
    );
    final profile = profiles.isEmpty ? null : profiles.first;
    final currency = profile?['default_currency_code'] as String? ?? 'IDR';
    final displayName = profile?['display_name'] as String? ?? 'Local User';

    final books = await db.query('books', orderBy: 'created_at ASC');
    final bookId = books.isEmpty ? migratedBookId : books.first['id'] as String;
    if (books.isEmpty) {
      await db.insert('books', {
        'id': bookId,
        'name': 'My Household',
        'base_currency_code': currency,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'local-device',
        'sync_status': 'local_only',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update(
        'books',
        {'base_currency_code': currency},
        where: 'id = ?',
        whereArgs: [bookId],
      );
    }
    await db.insert('household_members', {
      'id': migratedOwnerMemberId,
      'book_id': bookId,
      'display_name': displayName,
      'role': 'owner',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'local-device',
      'sync_status': 'local_only',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    for (final table in [
      'accounts',
      'categories',
      'projects',
      'transactions',
      'asset_definitions',
      'asset_market_prices',
    ]) {
      if (await _tableExists(db, table)) {
        await db.rawUpdate(
          'UPDATE $table SET book_id = ? WHERE book_id IS NULL',
          [bookId],
        );
      }
    }
    await db.rawUpdate(
      'UPDATE local_session SET active_book_id = ?, '
      'active_member_id = ? WHERE id = 1',
      [bookId, migratedOwnerMemberId],
    );
  }

  static Future<void> upgradeToV13(Database db) async {
    await _addColumnIfMissing(db, 'books', 'remote_linked_at', 'INTEGER');
    await _addColumnIfMissing(db, 'household_members', 'auth_user_id', 'TEXT');
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    if (!await _tableExists(db, table)) return;
    final columns = (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toSet();
    if (!columns.contains(column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }
}
