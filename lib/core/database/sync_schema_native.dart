import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SyncSchemaNative {
  const SyncSchemaNative._();

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        operation_id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation_type TEXT NOT NULL CHECK(operation_type IN ('upsert', 'delete')),
        base_version INTEGER NOT NULL,
        payload_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER,
        last_error_code TEXT,
        last_error_message TEXT,
        status TEXT NOT NULL CHECK(status IN ('pending', 'sending', 'retry', 'conflict', 'completed'))
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_book_status_created '
      'ON sync_outbox(book_id, status, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_entity '
      'ON sync_outbox(entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_next_attempt '
      'ON sync_outbox(next_attempt_at)',
    );
    await _createCursorTable(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS initial_sync_staging (
        book_id TEXT NOT NULL,
        direction TEXT NOT NULL CHECK(direction IN ('upload', 'download')),
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        transferred_at INTEGER,
        PRIMARY KEY(book_id, direction, entity_type, entity_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_initial_sync_staging_progress '
      'ON initial_sync_staging('
      'book_id, direction, entity_type, transferred_at, entity_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        base_version INTEGER NOT NULL,
        server_version INTEGER NOT NULL,
        local_payload_json TEXT,
        server_payload_json TEXT,
        created_at INTEGER NOT NULL,
        resolved_at INTEGER,
        resolution TEXT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_conflicts_operation '
      'ON sync_conflicts(operation_id) WHERE resolved_at IS NULL',
    );
  }

  static Future<void> _createCursorTable(DatabaseExecutor db) => db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        book_id TEXT PRIMARY KEY,
        last_server_sequence INTEGER NOT NULL DEFAULT 0,
        initialization_state TEXT NOT NULL DEFAULT 'notInitialized'
          CHECK(initialization_state IN (
            'notInitialized', 'primaryUploadRequired',
            'secondaryDownloadRequired', 'uploading', 'downloading',
            'ready', 'failed'
          )),
        started_at INTEGER,
        completed_at INTEGER,
        last_processed_entity TEXT,
        last_processed_cursor TEXT,
        uploaded_count INTEGER NOT NULL DEFAULT 0,
        downloaded_count INTEGER NOT NULL DEFAULT 0,
        last_error_code TEXT,
        last_error_message TEXT,
        initialization_direction TEXT
          CHECK(initialization_direction IN ('upload', 'download')),
        initialization_session_id TEXT,
        manifest_json TEXT,
        snapshot_sequence INTEGER NOT NULL DEFAULT 0,
        snapshot_outbox_rowid INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

  static Future<void> upgradeToV14(Database db) async {
    await create(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO sync_cursors(
        book_id, last_server_sequence, initialization_state, updated_at
      )
      SELECT id, 0, 'primaryUploadRequired', ?
      FROM books WHERE remote_linked_at IS NOT NULL
    ''',
      [now],
    );
  }

  static Future<void> upgradeToV15(Database db) async {
    await db.execute('ALTER TABLE sync_cursors RENAME TO sync_cursors_v14');
    await _createCursorTable(db);
    await db.execute('''
      INSERT INTO sync_cursors(
        book_id, last_server_sequence, initialization_state, updated_at
      )
      SELECT book_id, last_server_sequence, initialization_state, updated_at
      FROM sync_cursors_v14
    ''');
    await db.execute('DROP TABLE sync_cursors_v14');
    await create(db);
  }
}
