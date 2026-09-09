import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite v27 durable transaction note/reference migration.
abstract final class TransactionMetadataSchemaNative {
  static Future<void> upgradeToV27(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'transactions')) return;
    final columns = (await db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((row) => row['name'] as String).toSet();
    if (!columns.contains('note')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN note TEXT '
        'CHECK(note IS NULL OR length(note) <= 4000)',
      );
    }
    if (!columns.contains('reference')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN reference TEXT '
        'CHECK(reference IS NULL OR length(reference) <= 256)',
      );
    }
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
