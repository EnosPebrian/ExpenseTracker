import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TransactionImportRuleSchemaNative {
  const TransactionImportRuleSchemaNative._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_import_rules (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
        enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0, 1)),
        priority INTEGER NOT NULL DEFAULT 0,
        transaction_type TEXT NOT NULL CHECK(transaction_type IN ('expense', 'income')),
        match_field TEXT NOT NULL CHECK(match_field IN ('description', 'reference', 'merchantHint', 'descriptionOrReference')),
        match_operator TEXT NOT NULL CHECK(match_operator IN ('contains', 'equals', 'startsWith')),
        pattern TEXT NOT NULL CHECK(length(pattern) BETWEEN 1 AND 160),
        pattern_key TEXT NOT NULL,
        account_id TEXT,
        category_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only',
        FOREIGN KEY(book_id) REFERENCES books(id),
        FOREIGN KEY(account_id) REFERENCES accounts(id),
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_rules_book_priority ON transaction_import_rules(book_id, enabled, priority DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_rules_updated ON transaction_import_rules(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_rules_book_type ON transaction_import_rules(book_id, transaction_type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_rules_book_category ON transaction_import_rules(book_id, category_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_rules_book_account ON transaction_import_rules(book_id, account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_rules_sync ON transaction_import_rules(sync_status)',
    );
    await db.execute(
      '''CREATE UNIQUE INDEX IF NOT EXISTS uq_import_rules_active_semantic
      ON transaction_import_rules(book_id, transaction_type, match_field, match_operator, pattern_key, IFNULL(account_id, ''))
      WHERE deleted_at IS NULL''',
    );
  }

  static Future<void> upgradeToV22(DatabaseExecutor db) => create(db);
}
