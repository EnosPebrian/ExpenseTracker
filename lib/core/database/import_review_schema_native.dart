import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ImportReviewSchemaNative {
  const ImportReviewSchemaNative._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_review_sessions (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        source_type TEXT NOT NULL CHECK(source_type IN ('csv', 'receipt', 'invoice', 'bankStatement')),
        title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 160),
        source_fingerprint TEXT NOT NULL,
        destination_account_id TEXT,
        state TEXT NOT NULL CHECK(state IN ('pendingReview', 'readyToCommit', 'completed', 'discarded')),
        created_by_member_id TEXT,
        summary_json TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only',
        FOREIGN KEY(book_id) REFERENCES books(id),
        FOREIGN KEY(destination_account_id) REFERENCES accounts(id),
        FOREIGN KEY(created_by_member_id) REFERENCES household_members(id)
      )
    ''');
    await _createDraftTable(db, 'import_review_drafts', ifNotExists: true);
    await _createIndexes(db);
  }

  static Future<void> upgradeToV25(DatabaseExecutor db) async {
    await _createDraftTable(db, 'import_review_drafts_v25');
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS draft_count FROM import_review_drafts',
    );
    final oldCount = (countRows.single['draft_count'] as num).toInt();
    if (oldCount > 0) {
      await db.execute('''
      INSERT INTO import_review_drafts_v25 (
        id, session_id, book_id, source_row_identity, source_row_key,
        deterministic_transaction_id, deterministic_transaction_account_id,
        source_index, transaction_date, description, amount_minor,
        currency_code, transaction_type, category_name, category_id,
        category_provenance, reference_text, note_text, merchant_hint,
        included, user_edited_fields_json, warnings_json, created_at,
        updated_at, deleted_at, version, device_id, sync_status
      )
      SELECT
        draft.id, draft.session_id, draft.book_id, draft.source_row_identity,
        CASE session.source_type
          WHEN 'csv' THEN CAST(draft.source_index AS TEXT)
          WHEN 'receipt' THEN 'receipt'
          WHEN 'invoice' THEN 'receipt'
          ELSE NULL
        END,
        draft.deterministic_transaction_id, session.destination_account_id,
        draft.source_index, draft.transaction_date, draft.description,
        draft.amount_minor, draft.currency_code, draft.transaction_type,
        draft.category_name, draft.category_id, draft.category_provenance,
        draft.reference_text, draft.note_text, draft.merchant_hint,
        draft.included, draft.user_edited_fields_json, draft.warnings_json,
        draft.created_at, draft.updated_at, draft.deleted_at, draft.version,
        draft.device_id, draft.sync_status
      FROM import_review_drafts draft
      JOIN import_review_sessions session ON session.id = draft.session_id
    ''');
    }
    await db.execute('DROP TABLE import_review_drafts');
    await db.execute(
      'ALTER TABLE import_review_drafts_v25 RENAME TO import_review_drafts',
    );
    await _createIndexes(db);
  }

  static Future<void> _createDraftTable(
    DatabaseExecutor db,
    String tableName, {
    bool ifNotExists = false,
  }) => db.execute('''
      CREATE TABLE ${ifNotExists ? 'IF NOT EXISTS ' : ''}$tableName (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        source_row_identity TEXT NOT NULL,
        source_row_key TEXT,
        deterministic_transaction_id TEXT,
        deterministic_transaction_account_id TEXT,
        source_index INTEGER NOT NULL,
        transaction_date INTEGER NOT NULL,
        description TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        currency_code TEXT NOT NULL,
        transaction_type TEXT NOT NULL CHECK(transaction_type IN ('expense', 'income')),
        category_name TEXT NOT NULL DEFAULT '',
        category_id TEXT,
        category_provenance TEXT NOT NULL CHECK(category_provenance IN ('unresolved', 'source', 'rule', 'manual')),
        reference_text TEXT NOT NULL DEFAULT '',
        note_text TEXT NOT NULL DEFAULT '',
        merchant_hint TEXT NOT NULL DEFAULT '',
        included INTEGER NOT NULL DEFAULT 1 CHECK(included IN (0, 1)),
        user_edited_fields_json TEXT NOT NULL DEFAULT '[]',
        warnings_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'local_only',
        FOREIGN KEY(session_id) REFERENCES import_review_sessions(id),
        FOREIGN KEY(book_id) REFERENCES books(id),
        FOREIGN KEY(category_id) REFERENCES categories(id),
        FOREIGN KEY(deterministic_transaction_account_id) REFERENCES accounts(id),
        CHECK((deterministic_transaction_id IS NULL) = (deterministic_transaction_account_id IS NULL)),
        UNIQUE(session_id, source_row_identity),
        UNIQUE(session_id, deterministic_transaction_id)
      )
    ''');

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    for (final statement in const [
      'CREATE INDEX IF NOT EXISTS idx_import_review_sessions_book ON import_review_sessions(book_id)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_sessions_state ON import_review_sessions(book_id, state, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_sessions_updated ON import_review_sessions(updated_at)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_sessions_sync ON import_review_sessions(sync_status)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_drafts_session ON import_review_drafts(session_id, deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_drafts_book ON import_review_drafts(book_id)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_drafts_transaction ON import_review_drafts(deterministic_transaction_id)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_drafts_updated ON import_review_drafts(updated_at)',
      'CREATE INDEX IF NOT EXISTS idx_import_review_drafts_sync ON import_review_drafts(sync_status)',
    ]) {
      await db.execute(statement);
    }
  }
}
