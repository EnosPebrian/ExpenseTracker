import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite v28 additive brokerage attribution on authoritative transactions.
abstract final class BrokerageSchemaNative {
  static Future<void> upgradeToV28(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'transactions')) return;
    final columns = (await db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((row) => row['name'] as String).toSet();
    if (!columns.contains('brokerage_account_id')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN brokerage_account_id TEXT',
      );
    }
    if (!columns.contains('brokerage_activity_type')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN brokerage_activity_type TEXT',
      );
    }
    if (!columns.contains('split_numerator')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN split_numerator INTEGER '
        'CHECK(split_numerator IS NULL OR split_numerator > 0)',
      );
    }
    if (!columns.contains('split_denominator')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN split_denominator INTEGER '
        'CHECK(split_denominator IS NULL OR split_denominator > 0)',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_brokerage_account '
      'ON transactions(brokerage_account_id)',
    );
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async =>
      (await db.query(
        'sqlite_master',
        columns: const ['name'],
        where: 'type = ? AND name = ?',
        whereArgs: ['table', table],
        limit: 1,
      )).isNotEmpty;
}
