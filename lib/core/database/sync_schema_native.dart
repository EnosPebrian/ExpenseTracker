import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../master_data/default_asset_definition_ids.dart';

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
        conflict_type TEXT NOT NULL DEFAULT 'versionConflict',
        changed_local_fields_json TEXT NOT NULL DEFAULT '[]',
        changed_server_fields_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        resolution_status TEXT NOT NULL DEFAULT 'unresolved',
        resolved_at INTEGER,
        resolution TEXT,
        resolution_operation_id TEXT
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
        initial_sync_diagnostic_json TEXT,
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

  static Future<void> upgradeToV16(Database db) async {
    final columns = (await db.rawQuery(
      'PRAGMA table_info(sync_conflicts)',
    )).map((row) => row['name']).toSet();
    Future<void> add(String name, String definition) async {
      if (!columns.contains(name)) {
        await db.execute('ALTER TABLE sync_conflicts ADD COLUMN $definition');
      }
    }

    await add(
      'conflict_type',
      "conflict_type TEXT NOT NULL DEFAULT 'versionConflict'",
    );
    await add(
      'changed_local_fields_json',
      "changed_local_fields_json TEXT NOT NULL DEFAULT '[]'",
    );
    await add(
      'changed_server_fields_json',
      "changed_server_fields_json TEXT NOT NULL DEFAULT '[]'",
    );
    await add(
      'resolution_status',
      "resolution_status TEXT NOT NULL DEFAULT 'unresolved'",
    );
    await add('resolution_operation_id', 'resolution_operation_id TEXT');
  }

  static Future<void> upgradeToV17(Database db) async {
    if (!await _tableExists(db, 'asset_definitions')) return;
    for (final replacement in legacyDefaultAssetIdReplacements.entries) {
      final legacyId = replacement.key;
      final uuid = replacement.value;
      final targetExists =
          ((await db.rawQuery(
                'SELECT COUNT(*) AS total FROM asset_definitions WHERE id = ?',
                [uuid],
              )).single['total']
              as int) !=
          0;
      final legacyExists =
          ((await db.rawQuery(
                'SELECT COUNT(*) AS total FROM asset_definitions WHERE id = ?',
                [legacyId],
              )).single['total']
              as int) !=
          0;
      if (!legacyExists || targetExists) continue;

      await db.update(
        'transactions',
        {'asset_definition_id': uuid},
        where: 'asset_definition_id = ?',
        whereArgs: [legacyId],
      );
      if (await _tableExists(db, 'asset_market_prices')) {
        await db.update(
          'asset_market_prices',
          {'asset_key': uuid},
          where: 'asset_key = ?',
          whereArgs: [legacyId],
        );
      }
      await _replaceSyncReferences(db, legacyId, uuid);
      await db.update(
        'asset_definitions',
        {'id': uuid},
        where: 'id = ?',
        whereArgs: [legacyId],
      );
    }
  }

  static Future<void> upgradeToV18(Database db) async {
    if (!await _tableExists(db, 'projects') ||
        !await _tableExists(db, 'transactions') ||
        !await _columnExists(db, 'transactions', 'project_id')) {
      return;
    }
    final projects = await db.query(
      'projects',
      columns: const ['id', 'book_id', 'name'],
      where: 'deleted_at IS NULL',
    );
    final candidates = <String, List<String>>{};
    for (final project in projects) {
      final id = project['id'] as String?;
      final name = project['name'] as String?;
      if (id == null || name == null) continue;
      final key = _projectMigrationKey(
        project['book_id'] as String?,
        _legacyProjectId(name),
      );
      candidates.putIfAbsent(key, () => <String>[]).add(id);
    }
    final replacements = <String, String>{};
    for (final entry in candidates.entries) {
      if (entry.value.length == 1) replacements[entry.key] = entry.value.single;
    }
    if (replacements.isEmpty) return;

    for (final entry in replacements.entries) {
      final separator = entry.key.indexOf('\u0000');
      final bookId = entry.key.substring(0, separator);
      final legacyId = entry.key.substring(separator + 1);
      await db.update(
        'transactions',
        {'project_id': entry.value},
        where: 'book_id = ? AND project_id = ?',
        whereArgs: [bookId, legacyId],
      );
    }
    await _replaceLegacyProjectPayloads(db, replacements);
  }

  static Future<void> upgradeToV19(Database db) async {
    if (!await _columnExists(
      db,
      'sync_cursors',
      'initial_sync_diagnostic_json',
    )) {
      await db.execute(
        'ALTER TABLE sync_cursors ADD COLUMN '
        'initial_sync_diagnostic_json TEXT',
      );
    }
    await db.rawUpdate(
      "UPDATE sync_cursors SET downloaded_count = 0 "
      "WHERE initialization_direction = 'download' "
      "AND initialization_state != 'ready'",
    );
  }

  static String _legacyProjectId(String name) =>
      name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');

  static String _projectMigrationKey(String? bookId, String legacyId) =>
      '${bookId ?? ''}\u0000$legacyId';

  static Future<void> _replaceLegacyProjectPayloads(
    Database db,
    Map<String, String> replacements,
  ) async {
    for (final tableAndColumns in const <String, List<String>>{
      'sync_outbox': ['payload_json'],
      'initial_sync_staging': ['payload_json'],
      'sync_conflicts': ['local_payload_json', 'server_payload_json'],
    }.entries) {
      if (!await _tableExists(db, tableAndColumns.key)) continue;
      final rows = await db.rawQuery(
        'SELECT rowid AS migration_rowid, * FROM ${tableAndColumns.key}',
      );
      for (final row in rows) {
        if (row['entity_type'] != 'transactions') continue;
        final updates = <String, Object?>{};
        for (final column in tableAndColumns.value) {
          final encoded = row[column] as String?;
          if (encoded == null) continue;
          Object? decoded;
          try {
            decoded = jsonDecode(encoded);
          } on FormatException {
            continue;
          }
          if (decoded is! Map<String, dynamic>) continue;
          final legacyId = decoded['project_id'] as String?;
          if (legacyId == null) continue;
          final bookId =
              decoded['book_id'] as String? ?? row['book_id'] as String?;
          final replacement =
              replacements[_projectMigrationKey(bookId, legacyId)];
          if (replacement == null) continue;
          decoded['project_id'] = replacement;
          updates[column] = jsonEncode(decoded);
        }
        if (updates.isNotEmpty) {
          await db.update(
            tableAndColumns.key,
            updates,
            where: 'rowid = ?',
            whereArgs: [row['migration_rowid']],
          );
        }
      }
    }
  }

  static Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _columnExists(
    Database db,
    String table,
    String column,
  ) async {
    if (!await _tableExists(db, table)) return false;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.any((row) => row['name'] == column);
  }

  static Future<void> _replaceSyncReferences(
    Database db,
    String legacyId,
    String uuid,
  ) async {
    await _replacePayloads(
      db,
      table: 'sync_outbox',
      payloadColumns: const ['payload_json'],
      legacyId: legacyId,
      uuid: uuid,
    );
    await _replacePayloads(
      db,
      table: 'initial_sync_staging',
      payloadColumns: const ['payload_json'],
      legacyId: legacyId,
      uuid: uuid,
    );
    await _replacePayloads(
      db,
      table: 'sync_conflicts',
      payloadColumns: const ['local_payload_json', 'server_payload_json'],
      legacyId: legacyId,
      uuid: uuid,
    );
  }

  static Future<void> _replacePayloads(
    Database db, {
    required String table,
    required List<String> payloadColumns,
    required String legacyId,
    required String uuid,
  }) async {
    final rows = await db.query(table);
    for (final row in rows) {
      final updates = <String, Object?>{};
      if (row['entity_type'] == 'asset_definitions' &&
          row['entity_id'] == legacyId) {
        updates['entity_id'] = uuid;
      }
      for (final column in payloadColumns) {
        final encoded = row[column] as String?;
        if (encoded == null) continue;
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) continue;
        var changed = false;
        for (final key in const ['id', 'asset_definition_id', 'asset_key']) {
          if (decoded[key] == legacyId) {
            decoded[key] = uuid;
            changed = true;
          }
        }
        if (changed) updates[column] = jsonEncode(decoded);
      }
      if (updates.isEmpty) continue;
      final keyColumn = table == 'sync_outbox'
          ? 'operation_id'
          : table == 'sync_conflicts'
          ? 'id'
          : null;
      if (keyColumn != null) {
        await db.update(
          table,
          updates,
          where: '$keyColumn = ?',
          whereArgs: [row[keyColumn]],
        );
      } else {
        await db.update(
          table,
          updates,
          where:
              'book_id = ? AND direction = ? AND entity_type = ? '
              'AND entity_id = ?',
          whereArgs: [
            row['book_id'],
            row['direction'],
            row['entity_type'],
            row['entity_id'],
          ],
        );
      }
    }
  }
}
