import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BackupSchemaNative {
  const BackupSchemaNative._();

  static Future<void> upgradeToV20(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'asset_market_prices'",
    );
    if (tables.isEmpty) {
      await _createMarketPrices(db);
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info(asset_market_prices)');
    final columnNames = columns.map((column) => column['name']).toSet();
    final primaryKeyColumns = columns
        .where((column) => (column['pk'] as num?)?.toInt() != 0)
        .map((column) => column['name'])
        .toSet();
    if (primaryKeyColumns.containsAll(const ['book_id', 'asset_key'])) return;

    final fallbackBook = await db.rawQuery(
      'SELECT id FROM books WHERE deleted_at IS NULL ORDER BY created_at LIMIT 1',
    );
    final fallbackBookId = fallbackBook.isEmpty
        ? 'legacy-default-book'
        : fallbackBook.first['id'] as String;

    await db.execute(
      'ALTER TABLE asset_market_prices RENAME TO asset_market_prices_v19',
    );
    await _createMarketPrices(db);
    String existingOr(String name, String fallback) =>
        columnNames.contains(name) ? name : fallback;
    final bookExpression = columnNames.contains('book_id')
        ? 'COALESCE(book_id, ?)'
        : '?';
    await db.rawInsert(
      '''
      INSERT INTO asset_market_prices (
        asset_key, book_id, symbol, price_minor, minor_unit_scale,
        currency_code, unit, quoted_at, source, is_delayed, is_manual,
        updated_at
      )
      SELECT asset_key, $bookExpression,
        ${existingOr('symbol', 'asset_key')},
        ${existingOr('price_minor', '0')},
        ${existingOr('minor_unit_scale', '1')},
        ${existingOr('currency_code', "'IDR'")},
        ${existingOr('unit', "''")},
        ${existingOr('quoted_at', '0')},
        ${existingOr('source', "'legacy'")},
        ${existingOr('is_delayed', '0')},
        ${existingOr('is_manual', '0')},
        ${existingOr('updated_at', existingOr('quoted_at', '0'))}
      FROM asset_market_prices_v19
      ''',
      [fallbackBookId],
    );
    await db.execute('DROP TABLE asset_market_prices_v19');
  }

  static Future<void> _createMarketPrices(DatabaseExecutor db) => db.execute('''
    CREATE TABLE asset_market_prices (
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
}
