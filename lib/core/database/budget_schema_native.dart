import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BudgetSchemaNative {
  const BudgetSchemaNative._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS monthly_category_budgets (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        month_start TEXT NOT NULL,
        limit_minor INTEGER NOT NULL CHECK(limit_minor > 0),
        currency_code TEXT NOT NULL,
        note TEXT CHECK(note IS NULL OR length(note) <= 120),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only',
        FOREIGN KEY(book_id) REFERENCES books(id),
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_monthly_budgets_book_month '
      'ON monthly_category_budgets(book_id, month_start)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_monthly_budgets_book_category '
      'ON monthly_category_budgets(book_id, category_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_monthly_budgets_updated '
      'ON monthly_category_budgets(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_monthly_budgets_sync '
      'ON monthly_category_budgets(sync_status)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_monthly_budgets_active '
      'ON monthly_category_budgets(book_id, category_id, month_start) '
      'WHERE deleted_at IS NULL',
    );
  }

  static Future<void> upgradeToV21(DatabaseExecutor db) => create(db);
}
