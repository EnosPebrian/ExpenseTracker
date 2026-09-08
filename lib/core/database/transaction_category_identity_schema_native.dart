import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite v26 transaction category identity migration.
abstract final class TransactionCategoryIdentitySchemaNative {
  static Future<void> create(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'transactions') ||
        !await _columnExists(db, 'transactions', 'category_id')) {
      return;
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_category_id '
      'ON transactions(category_id)',
    );
  }

  static Future<void> upgradeToV26(DatabaseExecutor db) async {
    // Historical migration tests intentionally contain only the tables owned by
    // that old milestone. Real v25 databases are complete; partial fixtures must
    // still traverse the current upgrade chain safely.
    if (!await _tableExists(db, 'transactions')) return;
    final columns = (await db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((row) => row['name'] as String).toSet();
    if (!columns.contains('category_id')) {
      await db.execute('ALTER TABLE transactions ADD COLUMN category_id TEXT');
    }

    // Historical names are linked only when one category in the same household
    // and of the matching financial type is an unambiguous match. Archived
    // categories intentionally participate because transaction names are
    // historical snapshots.
    final transactionColumns = (await db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((row) => row['name'] as String).toSet();
    final categoryColumns = await _tableExists(db, 'categories')
        ? (await db.rawQuery(
            'PRAGMA table_info(categories)',
          )).map((row) => row['name'] as String).toSet()
        : const <String>{};
    if (transactionColumns.containsAll(const {
          'book_id',
          'transaction_type',
          'category',
          'category_id',
        }) &&
        categoryColumns.containsAll(const {
          'id',
          'book_id',
          'category_type',
          'name',
        })) {
      await db.execute('''
      UPDATE transactions
      SET category_id = (
        SELECT c.id
        FROM categories c
        WHERE c.book_id = transactions.book_id
          AND c.category_type = transactions.transaction_type
          AND lower(trim(c.name)) = lower(trim(transactions.category))
        LIMIT 1
      )
      WHERE category_id IS NULL
        AND transaction_type IN ('expense', 'income')
        AND (
          SELECT count(*)
          FROM categories c
          WHERE c.book_id = transactions.book_id
            AND c.category_type = transactions.transaction_type
            AND lower(trim(c.name)) = lower(trim(transactions.category))
        ) = 1
    ''');
    }
    await create(db);
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async =>
      (await db.query(
        'sqlite_master',
        columns: const ['name'],
        where: 'type = ? AND name = ?',
        whereArgs: ['table', table],
        limit: 1,
      )).isNotEmpty;

  static Future<bool> _columnExists(
    DatabaseExecutor db,
    String table,
    String column,
  ) async => (await db.rawQuery(
    'PRAGMA table_info($table)',
  )).any((row) => row['name'] == column);
}
