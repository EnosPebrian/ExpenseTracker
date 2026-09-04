import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/local_store_native.dart';
import '../domain/initial_sync_models.dart';
import '../domain/sync_models.dart';

class InitialSyncStoreAdapter {
  InitialSyncStoreAdapter(this.store);

  final LocalStore store;

  Future<bool> isIncrementallySyncReady(String bookId) async {
    final books = await store.db.query(
      'books',
      columns: ['remote_linked_at'],
      where: 'id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (books.isEmpty || books.single['remote_linked_at'] == null) return false;
    final cursor = await store.getSyncCursor(bookId);
    return cursor?['initialization_state'] ==
        SyncInitializationState.ready.name;
  }

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
        if (direction == InitialSyncDirection.download)
          'initial_sync_diagnostic_json': jsonEncode(
            InitialSyncDiagnosticSummary.forManifest(manifest).toJson(),
          ),
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
      var skipped = 0;
      for (final row in batch.rows) {
        final id = row['id'] as String?;
        if (id == null ||
            (batch.entityType == 'books'
                ? id != bookId
                : row['book_id'] != bookId)) {
          throw InitialSyncException(
            InitialSyncErrorCode.validation,
            'The downloaded snapshot contains another household.',
            entityType: batch.entityType,
            recordId: id,
            phase: 'validate',
          );
        }
        final existing = await txn.query(
          'initial_sync_staging',
          columns: const ['payload_json'],
          where:
              'book_id = ? AND direction = ? AND entity_type = ? '
              'AND entity_id = ?',
          whereArgs: [
            bookId,
            InitialSyncDirection.download.name,
            batch.entityType,
            id,
          ],
          limit: 1,
        );
        final encoded = jsonEncode(row);
        if (existing.isNotEmpty) {
          if (existing.single['payload_json'] != encoded) {
            throw InitialSyncException(
              InitialSyncErrorCode.validation,
              'A resumed snapshot record changed unexpectedly.',
              entityType: batch.entityType,
              recordId: id,
              phase: 'stage',
            );
          }
          skipped++;
          continue;
        }
        await txn.insert('initial_sync_staging', {
          'book_id': bookId,
          'direction': InitialSyncDirection.download.name,
          'entity_type': batch.entityType,
          'entity_id': id,
          'payload_json': encoded,
          'transferred_at': now,
        });
        inserted++;
      }
      final diagnostic = await _diagnostic(txn, bookId);
      final cursorRows = await txn.query(
        'sync_cursors',
        columns: const ['last_processed_entity', 'last_processed_cursor'],
        where: 'book_id = ?',
        whereArgs: [bookId],
        limit: 1,
      );
      final previousCursor =
          cursorRows.isNotEmpty &&
              cursorRows.single['last_processed_entity'] == batch.entityType
          ? cursorRows.single['last_processed_cursor'] as String?
          : null;
      final committedCursor =
          batch.nextCursor ?? (batch.rows.isEmpty ? previousCursor : null);
      final current = diagnostic.entities[batch.entityType]!;
      final updated = InitialSyncDiagnosticSummary({
        ...diagnostic.entities,
        batch.entityType: current.copyWith(
          fetched: current.fetched + batch.rows.length,
          decoded: current.decoded + inserted,
          skipped: current.skipped + skipped,
        ),
      });
      await txn.rawUpdate(
        'UPDATE sync_cursors SET downloaded_count = 0, '
        'initial_sync_diagnostic_json = ?, '
        'last_processed_entity = ?, last_processed_cursor = ?, updated_at = ? '
        'WHERE book_id = ?',
        [
          jsonEncode(updated.toJson()),
          batch.entityType,
          committedCursor,
          now,
          bookId,
        ],
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

  Future<bool> activateDownload({
    required String bookId,
    required InitialSyncManifest manifest,
    required String? authUserId,
    bool replaceExisting = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var alreadyMatched = false;
    await store.db.transaction((txn) async {
      if (!replaceExisting && await _financialRowCount(txn, bookId) > 0) {
        throw const InitialSyncException(
          InitialSyncErrorCode.localTargetPopulated,
          'This device already contains independent data for that household.',
        );
      }
      final rowsByType = await _loadStagedRows(txn, bookId);
      _validateManifest(manifest, rowsByType);
      final alreadyMatches =
          replaceExisting &&
          await _matchesHostedSnapshot(txn, bookId, rowsByType);
      alreadyMatched = alreadyMatches;
      if (replaceExisting && !alreadyMatches) {
        for (final table in const [
          'import_review_drafts',
          'import_review_sessions',
          'transfer_links',
          'transactions',
          'transaction_import_rules',
          'monthly_category_budgets',
          'asset_market_prices',
          'asset_definitions',
          'projects',
          'categories',
          'accounts',
          'household_members',
        ]) {
          await txn.delete(table, where: 'book_id = ?', whereArgs: [bookId]);
        }
        await txn.delete('books', where: 'id = ?', whereArgs: [bookId]);
        await txn.delete(
          'sync_outbox',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
        await txn.delete(
          'sync_conflicts',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
      }
      final diagnostic = await _diagnostic(txn, bookId);
      var finalDiagnostic = diagnostic;
      for (final entityType in initialSyncEntityOrder) {
        final table = _table(entityType);
        final localColumns = await _columnNames(txn, table);
        for (final source in rowsByType[entityType]!) {
          if (alreadyMatches) continue;
          final saved = <String, Object?>{
            for (final entry in source.entries)
              if (localColumns.contains(entry.key)) entry.key: entry.value,
            'sync_status': 'synced',
            if (entityType == 'books') 'remote_linked_at': now,
            if (entityType == 'household_members' &&
                source['id'] == manifest.householdMemberId)
              'auth_user_id': authUserId,
          };
          try {
            await txn.insert(
              table,
              saved,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (error) {
            throw InitialSyncException(
              InitialSyncErrorCode.validation,
              'The local database rejected a downloaded record.',
              entityType: entityType,
              recordId: source['id'] as String?,
              phase: 'persist',
              exceptionClass: error.runtimeType.toString(),
              lastCommittedCursor: null,
              committedRecords: 0,
            );
          }
        }
      }
      if (alreadyMatches) {
        await txn.update(
          'books',
          {'remote_linked_at': now, 'sync_status': 'synced'},
          where: 'id = ?',
          whereArgs: [bookId],
        );
        await txn.update(
          'household_members',
          {'auth_user_id': authUserId, 'sync_status': 'synced'},
          where: 'id = ? AND book_id = ?',
          whereArgs: [manifest.householdMemberId, bookId],
        );
        await txn.delete(
          'sync_outbox',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
        await txn.delete(
          'sync_conflicts',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
      }
      for (final entityType in initialSyncEntityOrder) {
        final localRows = await _rowsForBook(txn, entityType, bookId);
        final expected = manifest.counts[entityType] ?? 0;
        if (localRows.length != expected) {
          throw InitialSyncException(
            InitialSyncErrorCode.validation,
            'Downloaded records could not be verified locally.',
            entityType: entityType,
            phase: 'verify',
            exceptionClass: 'LocalVisibilityMismatch',
            committedRecords: 0,
          );
        }
        final current = finalDiagnostic.entities[entityType]!;
        finalDiagnostic = InitialSyncDiagnosticSummary({
          ...finalDiagnostic.entities,
          entityType: current.copyWith(
            persisted: expected,
            locallyQueryable: localRows.length,
          ),
        });
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
          'downloaded_count': manifest.totalCount,
          'initial_sync_diagnostic_json': jsonEncode(finalDiagnostic.toJson()),
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
    return alreadyMatched;
  }

  Future<InitialSyncDiagnosticSummary> getDiagnosticSummary(String bookId) =>
      _diagnostic(store.db, bookId);

  Future<void> recordFailure(
    String bookId, {
    required InitialSyncException error,
  }) async {
    await store.db.transaction((txn) async {
      var diagnostic = await _diagnostic(txn, bookId);
      final entityType = error.entityType;
      if (entityType != null && diagnostic.entities.containsKey(entityType)) {
        final current = diagnostic.entities[entityType]!;
        diagnostic = InitialSyncDiagnosticSummary({
          ...diagnostic.entities,
          entityType: current.copyWith(failed: current.failed + 1),
        });
      }
      await txn.update(
        'sync_cursors',
        {
          'initialization_state': SyncInitializationState.failed.name,
          'last_error_code': error.code.name,
          'last_error_message': error.safeMessage,
          'initial_sync_diagnostic_json': jsonEncode(diagnostic.toJson()),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });
  }

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
          'initial_sync_diagnostic_json': null,
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

  static Future<Set<String>> _columnNames(
    DatabaseExecutor db,
    String table,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.map((column) => column['name'] as String).toSet();
  }

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
        columns: ['entity_id', 'payload_json'],
        where: 'book_id = ? AND direction = ? AND entity_type = ?',
        whereArgs: [bookId, InitialSyncDirection.download.name, entityType],
        orderBy: 'entity_id ASC',
      );
      result[entityType] = [];
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['payload_json'] as String);
          if (decoded is! Map) throw const FormatException('Not an object');
          result[entityType]!.add(decoded.cast<String, Object?>());
        } catch (error) {
          throw InitialSyncException(
            InitialSyncErrorCode.validation,
            'A downloaded record could not be decoded.',
            entityType: entityType,
            recordId: row['entity_id'] as String?,
            phase: 'decode',
            exceptionClass: error.runtimeType.toString(),
            committedRecords: 0,
          );
        }
      }
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
          entityType: entityType,
          phase: 'validate',
          committedRecords: 0,
        );
      }
      final ids = <Object?>{};
      for (final row in rows) {
        if (!ids.add(row['id']) ||
            (entityType == 'books'
                ? row['id'] != manifest.bookId
                : row['book_id'] != manifest.bookId) ||
            ((row['version'] as num?)?.toInt() ?? 0) < 1) {
          throw InitialSyncException(
            InitialSyncErrorCode.validation,
            'Initial download identity or version validation failed.',
            entityType: entityType,
            recordId: row['id'] as String?,
            phase: 'validate',
            committedRecords: 0,
          );
        }
      }
    }
    final memberIds = rowsByType['household_members']!
        .map((row) => row['id'])
        .toSet();
    final projectIds = rowsByType['projects']!.map((row) => row['id']).toSet();
    final expenseCategoryIds = rowsByType['categories']!
        .where((row) => row['category_type'] == 'expense')
        .map((row) => row['id'])
        .toSet();
    final categoryIds = rowsByType['categories']!
        .map((row) => row['id'])
        .toSet();
    final categoryTypes = {
      for (final row in rowsByType['categories']!)
        row['id']: row['category_type'],
    };
    final accountIds = rowsByType['accounts']!.map((row) => row['id']).toSet();
    final accountsById = {
      for (final row in rowsByType['accounts']!) row['id']: row,
    };
    final assetIds = rowsByType['asset_definitions']!
        .map((row) => row['id'])
        .toSet();
    final transactionIds = rowsByType['transactions']!
        .map((row) => row['id'])
        .toSet();
    for (final account in rowsByType['accounts']!) {
      final owner = account['owner_member_id'];
      if (owner != null && !memberIds.contains(owner)) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'An account owner is missing from the household snapshot.',
          entityType: 'accounts',
          recordId: account['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
        );
      }
    }
    final budgetKeys = <String>{};
    for (final budget in rowsByType['monthly_category_budgets']!) {
      final key = '${budget['category_id']}:${budget['month_start']}';
      final monthStart = budget['month_start'];
      final parsedMonth = monthStart is String
          ? DateTime.tryParse(monthStart)
          : null;
      final note = budget['note'];
      if (!expenseCategoryIds.contains(budget['category_id']) ||
          monthStart is! String ||
          !RegExp(r'^\d{4}-\d{2}-01$').hasMatch(monthStart) ||
          parsedMonth == null ||
          parsedMonth.day != 1 ||
          budget['limit_minor'] is! num ||
          (budget['limit_minor'] as num).toInt() <= 0 ||
          budget['currency_code'] != manifest.baseCurrencyCode ||
          (note != null && (note is! String || note.length > 120)) ||
          (budget['deleted_at'] == null && !budgetKeys.add(key))) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'A monthly budget is invalid or references a missing category.',
          entityType: 'monthly_category_budgets',
          recordId: budget['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
        );
      }
    }
    final activeRuleKeys = <String>{};
    for (final rule in rowsByType['transaction_import_rules']!) {
      final semanticKey = [
        rule['transaction_type'],
        rule['match_field'],
        rule['match_operator'],
        rule['pattern_key'],
        rule['account_id'] ?? '',
      ].join('|');
      if (!categoryIds.contains(rule['category_id']) ||
          categoryTypes[rule['category_id']] != rule['transaction_type'] ||
          (rule['account_id'] != null &&
              !accountIds.contains(rule['account_id'])) ||
          (rule['deleted_at'] == null && !activeRuleKeys.add(semanticKey))) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'An import rule is invalid or references missing master data.',
          entityType: 'transaction_import_rules',
          recordId: rule['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
        );
      }
    }
    final sessionIds = <Object?>{};
    for (final session in rowsByType['import_review_sessions']!) {
      final validAccount =
          session['destination_account_id'] == null ||
          accountIds.contains(session['destination_account_id']);
      final validMember =
          session['created_by_member_id'] == null ||
          memberIds.contains(session['created_by_member_id']);
      if (!sessionIds.add(session['id']) || !validAccount || !validMember) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'An import review session references another household.',
          entityType: 'import_review_sessions',
          recordId: session['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
        );
      }
    }
    final draftIdentity = <String>{};
    for (final draft in rowsByType['import_review_drafts']!) {
      final key = '${draft['session_id']}:${draft['source_row_identity']}';
      if (!sessionIds.contains(draft['session_id']) ||
          !draftIdentity.add(key) ||
          (draft['category_id'] != null &&
              !categoryIds.contains(draft['category_id']))) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'An import review draft is invalid or belongs to another session.',
          entityType: 'import_review_drafts',
          recordId: draft['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
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
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'Transaction references or financial amounts are invalid.',
          entityType: 'transactions',
          recordId: transaction['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
        );
      }
    }
    final transactionsById = {
      for (final row in rowsByType['transactions']!) row['id']: row,
    };
    final activeLegIds = <Object?>{};
    for (final link in rowsByType['transfer_links']!) {
      final outgoing = transactionsById[link['outgoing_transaction_id']];
      final incoming = transactionsById[link['incoming_transaction_id']];
      final source = accountsById[link['source_account_id']];
      final destination = accountsById[link['destination_account_id']];
      final isActive = link['deleted_at'] == null;
      final amount = (link['amount'] as num?)?.toInt();
      final validActiveIdentity =
          !isActive ||
          (activeLegIds.add(link['outgoing_transaction_id']) &&
              activeLegIds.add(link['incoming_transaction_id']));
      if (outgoing == null ||
          incoming == null ||
          source == null ||
          destination == null ||
          link['outgoing_transaction_id'] == link['incoming_transaction_id'] ||
          link['source_account_id'] == link['destination_account_id'] ||
          amount == null ||
          amount <= 0 ||
          outgoing['transaction_type'] != 'expense' ||
          incoming['transaction_type'] != 'income' ||
          outgoing['amount'] != amount ||
          incoming['amount'] != amount ||
          outgoing['account'] != source['name'] ||
          incoming['account'] != destination['name'] ||
          source['currency_code'] != destination['currency_code'] ||
          source['currency_code'] != link['currency_code'] ||
          !validActiveIdentity) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'An internal transfer relation is invalid or incomplete.',
          entityType: 'transfer_links',
          recordId: link['id'] as String?,
          phase: 'validate',
          committedRecords: 0,
        );
      }
    }
  }

  static Future<InitialSyncDiagnosticSummary> _diagnostic(
    DatabaseExecutor db,
    String bookId,
  ) async {
    final rows = await db.query(
      'sync_cursors',
      columns: const ['initial_sync_diagnostic_json', 'manifest_json'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return InitialSyncDiagnosticSummary({
        for (final entityType in initialSyncEntityOrder)
          entityType: const InitialSyncEntityDiagnostic(),
      });
    }
    final encoded = rows.single['initial_sync_diagnostic_json'] as String?;
    if (encoded != null) {
      return InitialSyncDiagnosticSummary.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    }
    final manifestJson = rows.single['manifest_json'] as String?;
    if (manifestJson != null) {
      return InitialSyncDiagnosticSummary.forManifest(
        InitialSyncManifest.fromJson(
          (jsonDecode(manifestJson) as Map).cast<String, Object?>(),
        ),
      );
    }
    return InitialSyncDiagnosticSummary({
      for (final entityType in initialSyncEntityOrder)
        entityType: const InitialSyncEntityDiagnostic(),
    });
  }

  static Future<bool> _matchesHostedSnapshot(
    DatabaseExecutor db,
    String bookId,
    Map<String, List<Map<String, Object?>>> rowsByType,
  ) async {
    for (final entityType in initialSyncEntityOrder) {
      final localRows = await _rowsForBook(db, entityType, bookId);
      final hostedRows = rowsByType[entityType] ?? const [];
      if (localRows.length != hostedRows.length) return false;
      final localById = {for (final row in localRows) row['id'] as String: row};
      for (final hosted in hostedRows) {
        final local = localById[hosted['id']];
        if (local == null) return false;
        for (final entry in hosted.entries) {
          if (entry.key == 'sync_status' ||
              entry.key == 'remote_linked_at' ||
              entry.key == 'auth_user_id') {
            continue;
          }
          if (local[entry.key] != entry.value) return false;
        }
      }
    }
    return true;
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
