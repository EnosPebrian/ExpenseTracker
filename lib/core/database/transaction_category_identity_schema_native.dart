import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite v26 transaction category identity migration.
abstract final class TransactionCategoryIdentitySchemaNative {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_category_id '
      'ON transactions(category_id)',
    );
  }

  static Future<void> upgradeToV26(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(transactions)'))
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('category_id')) {
      await db.execute('ALTER TABLE transactions ADD COLUMN category_id TEXT');
    }

    // Historical names are linked only when one category in the same household
    // and of the matching financial type is an unambiguous match. Archived
    // categories intentionally participate because transaction names are
    // historical snapshots.
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
    await create(db);
  }
}
