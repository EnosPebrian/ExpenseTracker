import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TransferLinkSchemaNative {
  const TransferLinkSchemaNative._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transfer_links (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        outgoing_transaction_id TEXT NOT NULL,
        incoming_transaction_id TEXT NOT NULL,
        source_account_id TEXT NOT NULL,
        destination_account_id TEXT NOT NULL,
        currency_code TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only',
        CHECK(outgoing_transaction_id <> incoming_transaction_id),
        CHECK(source_account_id <> destination_account_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfer_links_book '
      'ON transfer_links(book_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfer_links_outgoing '
      'ON transfer_links(outgoing_transaction_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfer_links_incoming '
      'ON transfer_links(incoming_transaction_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfer_links_updated '
      'ON transfer_links(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfer_links_sync '
      'ON transfer_links(sync_status)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_transfer_links_active_outgoing '
      'ON transfer_links(outgoing_transaction_id) WHERE deleted_at IS NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_transfer_links_active_incoming '
      'ON transfer_links(incoming_transaction_id) WHERE deleted_at IS NULL',
    );
  }
}
