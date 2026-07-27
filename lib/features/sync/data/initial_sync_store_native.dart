import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/local_store_native.dart';
import '../domain/initial_sync_models.dart';
import '../domain/sync_models.dart';

class InitialSyncStoreAdapter {
  InitialSyncStoreAdapter(this.store);

  final LocalStore store;

  Future<InitialSyncManifest> captureUploadSnapshot(String bookId) =>
      store.db.transaction((txn) async {
        final bookRows = await txn.query(
          'books',
          where: 'id = ?',
          whereArgs: [bookId],
          limit: 1,
        );
        if (bookRows.isEmpty || bookRows.single['remote_linked_at'] == null) {
          throw const InitialSyncException(
            InitialSyncErrorCode.validation,
            'The local household is not linked to cloud sharing.',
          );
        }
        await txn.delete(
          'initial_sync_staging',
          where: 'book_id = ? AND direction = ?',
          whereArgs: [bookId, InitialSyncDirection.upload.name],
        );
        final counts = <String, int>{};
        for (final entityType in initialSyncEntityOrder) {
          final rows = await _rowsForBook(txn, entityType, bookId);
          counts[entityType] = rows.length;
          for (final row in rows) {
            await txn.insert('initial_sync_staging', {
              'book_id': bookId,
              'direction': InitialSyncDirection.upload.name,
              'entity_type': entityType,
              'entity_id': row['id'],
              'payload_json': jsonEncode(row),
            });
          }
        }
        final boundaryRows = await txn.rawQuery(
          'SELECT COALESCE(MAX(rowid), 0) AS boundary FROM sync_outbox '
          'WHERE book_id = ?',
          [bookId],
        );
        final boundary = (boundaryRows.single['boundary'] as num).toInt();
        final book = bookRows.single;
        final manifest = InitialSyncManifest(
          bookId: bookId,
          bookName: book['name'] as String,
          baseCurrencyCode: book['base_currency_code'] as String? ?? 'IDR',
          counts: counts,
          snapshotSequence: 0,
        );
        final now = DateTime.now().millisecondsSinceEpoch;
        await _upsertCursor(txn, {
          'book_id': bookId,
          'initialization_state': SyncInitializationState.uploading.name,
          'initialization_direction': InitialSyncDirection.upload.name,
          'started_at': now,
          'completed_at': null,
          'last_processed_entity': null,
          'last_processed_cursor': null,
          'uploaded_count': 0,
          'downloaded_count': 0,
          'last_error_code': null,
          'last_error_message': null,
          'initialization_session_id': null,
          'manifest_json': jsonEncode(manifest.toJson()),
          'snapshot_sequence': 0,
          'snapshot_outbox_rowid': boundary,
          'updated_at': now,
        });
        return manifest;
      });

  Future<List<Map<String, Object?>>> readUploadRows(
    String bookId,
    String entityType, {
    int limit = 100,
  }) async {
    _validateEntityType(entityType);
    final rows = await store.db.query(
      'initial_sync_staging',
      columns: ['payload_json'],
      where:
          'book_id = ? AND direction = ? AND entity_type = ? '
          'AND transferred_at IS NULL',
      whereArgs: [bookId, InitialSyncDirection.upload.name, entityType],
      orderBy: 'entity_id ASC',
      limit: limit.clamp(1, 100),
    );
    return rows
        .map(
          (row) => (jsonDecode(row['payload_json'] as String) as Map)
              .cast<String, Object?>(),
        )
        .toList();
  }

  Future<void> markUploadRowsTransferred(
    String bookId,
    String entityType,
    Iterable<String> entityIds,
  ) async {
    final ids = entityIds.toList();
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'initial_sync_staging',
          {'transferred_at': now},
          where:
              'book_id = ? AND direction = ? AND entity_type = ? '
              'AND entity_id = ? AND transferred_at IS NULL',
          whereArgs: [bookId, InitialSyncDirection.upload.name, entityType, id],
        );
      }
      await txn.rawUpdate(
        'UPDATE sync_cursors SET uploaded_count = uploaded_count + ?, '
        'last_processed_entity = ?, last_processed_cursor = ?, updated_at = ? '
        'WHERE book_id = ?',
        [ids.length, entityType, ids.last, now, bookId],
      );
    });
  }

  Future<void> startInitialization({
    required String bookId,
    required InitialSyncDirection direction,
    required String sessionId,
    required InitialSyncManifest manifest,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((txn) async {
      if (direction == InitialSyncDirection.download) {
        await txn.delete(
          'initial_sync_staging',
          where: 'book_id = ? AND direction = ?',
          whereArgs: [bookId, direction.name],
        );
      }
      await _upsertCursor(txn, {
        'book_id': bookId,
        'initialization_state': direction == InitialSyncDirection.upload
            ? SyncInitializationState.uploading.name
            : SyncInitializationState.downloading.name,
        'initialization_direction': direction.name,
        'initialization_session_id': sessionId,
        'started_at': now,
        'completed_at': null,
        'last_processed_entity': null,
        'last_processed_cursor': null,
        if (direction == InitialSyncDirection.download) 'downloaded_count': 0,
        'last_error_code': null,
        'last_error_message': null,
        'manifest_json': jsonEncode(manifest.toJson()),
        'snapshot_sequence': manifest.snapshotSequence,
        'updated_at': now,
      });
    });
  }

  Future<bool> targetHasFinancialData(String bookId) async {
    final count = await _financialRowCount(store.db, bookId);
    return count > 0;
  }

  Future<void> stageDownloadBatch(String bookId, InitialSyncBatch batch) async {
    _validateEntityType(batch.entityType);
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((txn) async {
      var inserted = 0;
      for (final row in batch.rows) {
        final id = row['id'] as String?;
        if (id == null ||
            (batch.entityType == 'books'
                ? id != bookId
                : row['book_id'] != bookId)) {
          throw const InitialSyncException(
            InitialSyncErrorCode.validation,
            'The downloaded snapshot contains another household.',
          );
        }
        final result = await txn.insert('initial_sync_staging', {
          'book_id': bookId,
          'direction': InitialSyncDirection.download.name,
          'entity_type': batch.entityType,
          'entity_id': id,
          'payload_json': jsonEncode(row),
          'transferred_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (result != 0) inserted++;
      }
      await txn.rawUpdate(
        'UPDATE sync_cursors SET downloaded_count = downloaded_count + ?, '
        'last_processed_entity = ?, last_processed_cursor = ?, updated_at = ? '
        'WHERE book_id = ?',
        [inserted, batch.entityType, batch.nextCursor, now, bookId],
      );
    });
  }

  Future<void> completeUpload(String bookId, int finalSequence) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((txn) async {
      final cursorRows = await txn.query(
        'sync_cursors',
        where: 'book_id = ?',
        whereArgs: [bookId],
        limit: 1,
      );
      if (cursorRows.isEmpty) {
        throw StateError('Initial upload state is missing.');
      }
      final boundary =
          (cursorRows.single['snapshot_outbox_rowid'] as num?)?.toInt() ?? 0;
      await txn.rawUpdate(
        "UPDATE sync_outbox SET status = 'completed', updated_at = ? "
        'WHERE book_id = ? AND rowid <= ? AND status != ?',
        [now, bookId, boundary, SyncOutboxStatus.conflict.name],
      );
      for (final entityType in initialSyncEntityOrder) {
        final table = _table(entityType);
        await txn.rawUpdate(
          "UPDATE $table SET sync_status = 'synced' WHERE "
          '${entityType == 'books' ? 'id' : 'book_id'} = ? '
          'AND NOT EXISTS (SELECT 1 FROM sync_outbox newer '
          "WHERE newer.book_id = ? AND newer.entity_type = ? "
          "AND newer.entity_id = $table.id AND newer.rowid > ? "
          "AND newer.status != 'completed')",
          [bookId, bookId, entityType, boundary],
        );
      }
      await txn.update(
        'sync_cursors',
        {
          'last_server_sequence': finalSequence,
          'initialization_state': SyncInitializationState.ready.name,
          'completed_at': now,
          'last_error_code': null,
          'last_error_message': null,
          'updated_at': now,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      await txn.delete(
        'initial_sync_staging',
        where: 'book_id = ? AND direction = ?',
        whereArgs: [bookId, InitialSyncDirection.upload.name],
      );
    });
  }

  Future<void> activateDownload({
    required String bookId,
    required InitialSyncManifest manifest,
    required String? authUserId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((txn) async {
      if (await _financialRowCount(txn, bookId) > 0) {
        throw const InitialSyncException(
          InitialSyncErrorCode.localTargetPopulated,
          'This device already contains independent data for that household.',
        );
      }
      final rowsByType = await _loadStagedRows(txn, bookId);
      _validateManifest(manifest, rowsByType);
      for (final entityType in initialSyncEntityOrder) {
        final table = _table(entityType);
        for (final source in rowsByType[entityType]!) {
          final saved = <String, Object?>{
            ...source,
            'sync_status': 'synced',
            if (entityType == 'books') 'remote_linked_at': now,
            if (entityType == 'household_members' &&
                source['id'] == manifest.householdMemberId)
              'auth_user_id': authUserId,
          };
          await txn.insert(
            table,
            saved,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await txn.update('local_session', {
        'active_book_id': bookId,
        'active_member_id': manifest.householdMemberId,
      }, where: 'id = 1');
      await txn.update(
        'sync_cursors',
        {
          'last_server_sequence': manifest.snapshotSequence,
          'initialization_state': SyncInitializationState.ready.name,
          'completed_at': now,
          'last_error_code': null,
          'last_error_message': null,
          'updated_at': now,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      await txn.delete(
        'initial_sync_staging',
        where: 'book_id = ? AND direction = ?',
        whereArgs: [bookId, InitialSyncDirection.download.name],
      );
    });
    store.setActiveBookId(bookId);
  }

  Future<void> recordFailure(
    String bookId, {
    required String code,
    required String message,
  }) => store.db.update(
    'sync_cursors',
    {
      'initialization_state': SyncInitializationState.failed.name,
      'last_error_code': code,
      'last_error_message': message,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'book_id = ?',
    whereArgs: [bookId],
  );

  Future<void> cancelInitialization(
    String bookId,
    InitialSyncDirection direction,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.db.transaction((txn) async {
      await txn.delete(
        'initial_sync_staging',
        where: 'book_id = ? AND direction = ?',
        whereArgs: [bookId, direction.name],
      );
      await txn.update(
        'sync_cursors',
        {
          'initialization_state': direction == InitialSyncDirection.upload
              ? SyncInitializationState.primaryUploadRequired.name
              : SyncInitializationState.secondaryDownloadRequired.name,
          'initialization_session_id': null,
          'started_at': null,
          'completed_at': null,
          'last_processed_entity': null,
          'last_processed_cursor': null,
          'uploaded_count': 0,
          'downloaded_count': 0,
          'last_error_code': null,
          'last_error_message': null,
          'manifest_json': null,
          'snapshot_sequence': 0,
          'snapshot_outbox_rowid': 0,
          'updated_at': now,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });
  }

  static Future<List<Map<String, Object?>>> _rowsForBook(
    DatabaseExecutor db,
    String entityType,
    String bookId,
  ) => db.query(
    _table(entityType),
    where: entityType == 'books' ? 'id = ?' : 'book_id = ?',
    whereArgs: [bookId],
    orderBy: 'id ASC',
  );

  static Future<int> _financialRowCount(
    DatabaseExecutor db,
    String bookId,
  ) async {
    var total = 0;
    for (final entityType in initialSyncEntityOrder.skip(1)) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM ${_table(entityType)} WHERE book_id = ?',
        [bookId],
      );
      total += (result.single['total'] as num).toInt();
    }
    return total;
  }

  static Future<Map<String, List<Map<String, Object?>>>> _loadStagedRows(
    DatabaseExecutor db,
    String bookId,
  ) async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final entityType in initialSyncEntityOrder) {
      final rows = await db.query(
        'initial_sync_staging',
        columns: ['payload_json'],
        where: 'book_id = ? AND direction = ? AND entity_type = ?',
        whereArgs: [bookId, InitialSyncDirection.download.name, entityType],
        orderBy: 'entity_id ASC',
      );
      result[entityType] = rows
          .map(
            (row) => (jsonDecode(row['payload_json'] as String) as Map)
                .cast<String, Object?>(),
          )
          .toList();
    }
    return result;
  }

  static void _validateManifest(
    InitialSyncManifest manifest,
    Map<String, List<Map<String, Object?>>> rowsByType,
  ) {
    for (final entityType in initialSyncEntityOrder) {
      final rows = rowsByType[entityType]!;
      if (rows.length != (manifest.counts[entityType] ?? 0)) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'Initial download is incomplete for $entityType.',
        );
      }
      final ids = <Object?>{};
      for (final row in rows) {
        if (!ids.add(row['id']) ||
            (entityType == 'books'
                ? row['id'] != manifest.bookId
                : row['book_id'] != manifest.bookId) ||
            ((row['version'] as num?)?.toInt() ?? 0) < 1) {
          throw const InitialSyncException(
            InitialSyncErrorCode.validation,
            'Initial download identity or version validation failed.',
          );
        }
      }
    }
    final memberIds = rowsByType['household_members']!
        .map((row) => row['id'])
        .toSet();
    final projectIds = rowsByType['projects']!.map((row) => row['id']).toSet();
    final assetIds = rowsByType['asset_definitions']!
        .map((row) => row['id'])
        .toSet();
    final transactionIds = rowsByType['transactions']!
        .map((row) => row['id'])
        .toSet();
    for (final account in rowsByType['accounts']!) {
      final owner = account['owner_member_id'];
      if (owner != null && !memberIds.contains(owner)) {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'An account owner is missing from the household snapshot.',
        );
      }
    }
    for (final transaction in rowsByType['transactions']!) {
      final member = transaction['entered_by_member_id'];
      final project = transaction['project_id'];
      final related = transaction['related_transaction_id'];
      final asset = transaction['asset_definition_id'];
      final validLegacyAsset =
          transaction['asset_name'] != null && transaction['unit'] != null;
      if (transaction['amount'] is! num ||
          (member != null && !memberIds.contains(member)) ||
          (project != null && !projectIds.contains(project)) ||
          (related != null && !transactionIds.contains(related)) ||
          (asset != null && !assetIds.contains(asset) && !validLegacyAsset)) {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'Transaction references or financial amounts are invalid.',
        );
      }
    }
  }

  static Future<void> _upsertCursor(
    DatabaseExecutor db,
    Map<String, Object?> fields,
  ) async {
    final bookId = fields['book_id'];
    final existing = await db.query(
      'sync_cursors',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    await db.insert('sync_cursors', {
      if (existing.isNotEmpty) ...existing.single,
      'last_server_sequence': 0,
      ...fields,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static String _table(String entityType) {
    _validateEntityType(entityType);
    return entityType;
  }

  static void _validateEntityType(String entityType) {
    if (!initialSyncEntityOrder.contains(entityType)) {
      throw ArgumentError.value(entityType, 'entityType');
    }
  }
}
