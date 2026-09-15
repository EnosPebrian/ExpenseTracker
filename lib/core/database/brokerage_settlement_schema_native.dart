import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BrokerageSettlementSchemaNative {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS brokerage_settlements (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        brokerage_account_id TEXT NOT NULL,
        statement_date INTEGER NOT NULL,
        settlement_type TEXT NOT NULL CHECK(settlement_type IN ('BUY_SETTLEMENT', 'SELL_SETTLEMENT')),
        amount INTEGER NOT NULL CHECK(amount > 0),
        currency_code TEXT NOT NULL,
        source_fingerprint TEXT NOT NULL,
        source_row_identity TEXT NOT NULL,
        source_row_fingerprint TEXT NOT NULL,
        reference TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        trade_ids_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'local_only',
        UNIQUE(book_id, brokerage_account_id, source_fingerprint, source_row_identity, source_row_fingerprint)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_brokerage_settlements_book ON brokerage_settlements(book_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_brokerage_settlements_updated ON brokerage_settlements(updated_at)',
    );
  }
}
