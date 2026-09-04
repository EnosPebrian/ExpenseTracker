import 'dart:convert';

import '../../../core/database/local_store_web.dart';
import '../domain/initial_sync_models.dart';
import '../domain/sync_models.dart';

class InitialSyncStoreAdapter {
  InitialSyncStoreAdapter(this.store);

  final LocalStore store;

  Future<bool> isIncrementallySyncReady(String bookId) async {
    final books = await store.getFinancialBooks();
    final linked = books.any(
      (book) => book['id'] == bookId && book['remote_linked_at'] != null,
    );
    if (!linked) return false;
    final cursor = await store.getSyncCursor(bookId);
    return cursor?['initialization_state'] ==
        SyncInitializationState.ready.name;
  }

  static final Map<String, Map<String, Map<String, Object?>>> _staging = {};

  String _scope(String bookId, InitialSyncDirection direction) =>
      '$bookId:${direction.name}';

  Future<InitialSyncManifest> captureUploadSnapshot(String bookId) async {
    final bookRows = await store.getInitialSyncEntityRecords('books', bookId);
    if (bookRows.isEmpty || bookRows.single['remote_linked_at'] == null) {
      throw const InitialSyncException(
        InitialSyncErrorCode.validation,
        'The local household is not linked to cloud sharing.',
      );
    }
    final staged = <String, Map<String, Object?>>{};
    final counts = <String, int>{};
    for (final entityType in initialSyncEntityOrder) {
      final rows = await store.getInitialSyncEntityRecords(entityType, bookId);
      counts[entityType] = rows.length;
      for (final row in rows) {
        staged['$entityType:${row['id']}'] = {
          'entity_type': entityType,
          'entity_id': row['id'],
          'payload': Map<String, Object?>.of(row),
          'transferred': false,
        };
      }
    }
    _staging[_scope(bookId, InitialSyncDirection.upload)] = staged;
    final book = bookRows.single;
    final manifest = InitialSyncManifest(
      bookId: bookId,
      bookName: book['name'] as String,
      baseCurrencyCode: book['base_currency_code'] as String? ?? 'IDR',
      counts: counts,
      snapshotSequence: 0,
    );
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'initialization_state': SyncInitializationState.uploading.name,
      'initialization_direction': InitialSyncDirection.upload.name,
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'uploaded_count': 0,
      'downloaded_count': 0,
      'manifest_json': jsonEncode(manifest.toJson()),
      'snapshot_outbox_rowid': store.initialSyncOutboxBoundary,
    });
    return manifest;
  }

  Future<List<Map<String, Object?>>> readUploadRows(
    String bookId,
    String entityType, {
    int limit = 100,
  }) async =>
      (_staging[_scope(bookId, InitialSyncDirection.upload)]?.values ??
              const <Map<String, Object?>>[])
          .where(
            (row) =>
                row['entity_type'] == entityType && row['transferred'] == false,
          )
          .take(limit.clamp(1, 100))
          .map((row) => (row['payload'] as Map).cast<String, Object?>())
          .toList();

  Future<void> markUploadRowsTransferred(
    String bookId,
    String entityType,
    Iterable<String> entityIds,
  ) async {
    final ids = entityIds.toList();
    final staged = _staging[_scope(bookId, InitialSyncDirection.upload)]!;
    for (final id in ids) {
      final key = '$entityType:$id';
      staged[key] = {...staged[key]!, 'transferred': true};
    }
    final cursor = await store.getSyncCursor(bookId);
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'uploaded_count':
          ((cursor?['uploaded_count'] as num?)?.toInt() ?? 0) + ids.length,
      'last_processed_entity': entityType,
      'last_processed_cursor': ids.isEmpty ? null : ids.last,
    });
  }

  Future<void> startInitialization({
    required String bookId,
    required InitialSyncDirection direction,
    required String sessionId,
    required InitialSyncManifest manifest,
  }) async {
    if (direction == InitialSyncDirection.download) {
      _staging[_scope(bookId, direction)] = {};
    }
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'initialization_state': direction == InitialSyncDirection.upload
          ? SyncInitializationState.uploading.name
          : SyncInitializationState.downloading.name,
      'initialization_direction': direction.name,
      'initialization_session_id': sessionId,
      'started_at': DateTime.now().millisecondsSinceEpoch,
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
    });
  }

  Future<bool> targetHasFinancialData(String bookId) async {
    for (final entityType in initialSyncEntityOrder.skip(1)) {
      if ((await store.getInitialSyncEntityRecords(
        entityType,
        bookId,
      )).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> stageDownloadBatch(String bookId, InitialSyncBatch batch) async {
    final staged = _staging.putIfAbsent(
      _scope(bookId, InitialSyncDirection.download),
      () => {},
    );
    var inserted = 0;
    var skipped = 0;
    for (final row in batch.rows) {
      final id = row['id'];
      if (id == null ||
          (batch.entityType == 'books'
              ? id != bookId
              : row['book_id'] != bookId)) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'The downloaded snapshot contains another household.',
          entityType: batch.entityType,
          recordId: id?.toString(),
          phase: 'validate',
        );
      }
      final key = '${batch.entityType}:$id';
      if (!staged.containsKey(key)) {
        staged[key] = {
          'entity_type': batch.entityType,
          'entity_id': id,
          'payload': Map<String, Object?>.of(row),
        };
        inserted++;
      } else {
        final existing = staged[key]!['payload'];
        if (jsonEncode(existing) != jsonEncode(row)) {
          throw InitialSyncException(
            InitialSyncErrorCode.validation,
            'A resumed snapshot record changed unexpectedly.',
            entityType: batch.entityType,
            recordId: id.toString(),
            phase: 'stage',
          );
        }
        skipped++;
      }
    }
    final cursor = await store.getSyncCursor(bookId);
    final diagnostic = _diagnosticFromCursor(cursor);
    final current = diagnostic.entities[batch.entityType]!;
    final updated = InitialSyncDiagnosticSummary({
      ...diagnostic.entities,
      batch.entityType: current.copyWith(
        fetched: current.fetched + batch.rows.length,
        decoded: current.decoded + inserted,
        skipped: current.skipped + skipped,
      ),
    });
    Object? previousCursor;
    if (batch.rows.isEmpty &&
        cursor != null &&
        cursor['last_processed_entity'] == batch.entityType) {
      previousCursor = cursor['last_processed_cursor'];
    }
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'downloaded_count': 0,
      'initial_sync_diagnostic_json': jsonEncode(updated.toJson()),
      'last_processed_entity': batch.entityType,
      'last_processed_cursor': batch.nextCursor ?? previousCursor,
    });
  }

  Future<void> completeUpload(String bookId, int finalSequence) async {
    final cursor = await store.getSyncCursor(bookId);
    await store.completeInitialSyncUpload(
      bookId,
      (cursor?['snapshot_outbox_rowid'] as num?)?.toInt() ?? 0,
      finalSequence,
    );
    _staging.remove(_scope(bookId, InitialSyncDirection.upload));
  }

  Future<bool> activateDownload({
    required String bookId,
    required InitialSyncManifest manifest,
    required String? authUserId,
    bool replaceExisting = false,
  }) async {
    if (!replaceExisting && await targetHasFinancialData(bookId)) {
      throw const InitialSyncException(
        InitialSyncErrorCode.localTargetPopulated,
        'This device already contains independent data for that household.',
      );
    }
    final staged =
        _staging[_scope(bookId, InitialSyncDirection.download)] ?? {};
    final rows = <Map<String, Object?>>[];
    for (final entityType in initialSyncEntityOrder) {
      final matching = staged.values
          .where((row) => row['entity_type'] == entityType)
          .toList();
      if (matching.length != (manifest.counts[entityType] ?? 0)) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'Initial download is incomplete for $entityType.',
        );
      }
      for (final stagedRow in matching) {
        final payload = (stagedRow['payload'] as Map).cast<String, Object?>();
        final version = (payload['version'] as num?)?.toInt() ?? 0;
        if (version < 1) {
          throw const InitialSyncException(
            InitialSyncErrorCode.validation,
            'Initial download contains an invalid canonical version.',
          );
        }
        rows.add({
          'entity_type': entityType,
          'entity_id': payload['id'],
          'payload': {
            ...payload,
            if (entityType == 'books')
              'remote_linked_at': DateTime.now().millisecondsSinceEpoch,
            if (entityType == 'household_members' &&
                payload['id'] == manifest.householdMemberId)
              'auth_user_id': authUserId,
          },
        });
      }
    }
    _validateTransferLinks(rows);
    _validateImportReviewRows(rows);
    await store.applyRemoteSyncBatch(
      bookId,
      changes: rows,
      finalSequence: manifest.snapshotSequence,
      replaceExisting: replaceExisting,
    );
    var diagnostic = await getDiagnosticSummary(bookId);
    for (final entityType in initialSyncEntityOrder) {
      final local = await store.getInitialSyncEntityRecords(entityType, bookId);
      final expected = manifest.counts[entityType] ?? 0;
      if (local.length != expected) {
        throw InitialSyncException(
          InitialSyncErrorCode.validation,
          'Downloaded records could not be verified locally.',
          entityType: entityType,
          phase: 'verify',
          exceptionClass: 'LocalVisibilityMismatch',
          committedRecords: 0,
        );
      }
      final current = diagnostic.entities[entityType]!;
      diagnostic = InitialSyncDiagnosticSummary({
        ...diagnostic.entities,
        entityType: current.copyWith(
          persisted: expected,
          locallyQueryable: local.length,
        ),
      });
    }
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'downloaded_count': manifest.totalCount,
      'initialization_state': SyncInitializationState.ready.name,
      'last_error_code': null,
      'last_error_message': null,
      'initial_sync_diagnostic_json': jsonEncode(diagnostic.toJson()),
    });
    final session = await store.getLocalSession();
    await store.saveLocalSession(
      activeProfileId: session?['active_profile_id'] as String?,
      onboardingCompleted:
          (session?['onboarding_completed'] as num?)?.toInt() == 1,
      activeBookId: bookId,
      activeMemberId: manifest.householdMemberId,
    );
    store.setActiveBookId(bookId);
    _staging.remove(_scope(bookId, InitialSyncDirection.download));
    return false;
  }

  static void _validateTransferLinks(List<Map<String, Object?>> rows) {
    final payloadsByType = <String, List<Map<String, Object?>>>{
      for (final entityType in initialSyncEntityOrder) entityType: [],
    };
    for (final row in rows) {
      final entityType = row['entity_type'] as String;
      payloadsByType[entityType]!.add(
        (row['payload'] as Map).cast<String, Object?>(),
      );
    }
    final transactionsById = {
      for (final row in payloadsByType['transactions']!) row['id']: row,
    };
    final accountsById = {
      for (final row in payloadsByType['accounts']!) row['id']: row,
    };
    final activeLegIds = <Object?>{};
    for (final link in payloadsByType['transfer_links']!) {
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

  static void _validateImportReviewRows(List<Map<String, Object?>> rows) {
    final payloadsByType = <String, List<Map<String, Object?>>>{
      for (final entityType in initialSyncEntityOrder) entityType: [],
    };
    for (final row in rows) {
      payloadsByType[row['entity_type'] as String]!.add(
        (row['payload'] as Map).cast<String, Object?>(),
      );
    }
    final sessionIds = payloadsByType['import_review_sessions']!
        .map((row) => row['id'])
        .toSet();
    final identities = <String>{};
    for (final draft in payloadsByType['import_review_drafts']!) {
      final identity = '${draft['session_id']}:${draft['source_row_identity']}';
      if (!sessionIds.contains(draft['session_id']) ||
          !identities.add(identity)) {
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
  }

  Future<InitialSyncDiagnosticSummary> getDiagnosticSummary(
    String bookId,
  ) async => _diagnosticFromCursor(await store.getSyncCursor(bookId));

  Future<void> recordFailure(
    String bookId, {
    required InitialSyncException error,
  }) async {
    final cursor = await store.getSyncCursor(bookId);
    var diagnostic = _diagnosticFromCursor(cursor);
    final entityType = error.entityType;
    if (entityType != null && diagnostic.entities.containsKey(entityType)) {
      final current = diagnostic.entities[entityType]!;
      diagnostic = InitialSyncDiagnosticSummary({
        ...diagnostic.entities,
        entityType: current.copyWith(failed: current.failed + 1),
      });
    }
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'initialization_state': SyncInitializationState.failed.name,
      'last_error_code': error.code.name,
      'last_error_message': error.safeMessage,
      'initial_sync_diagnostic_json': jsonEncode(diagnostic.toJson()),
    });
  }

  Future<void> cancelInitialization(
    String bookId,
    InitialSyncDirection direction,
  ) async {
    _staging.remove(_scope(bookId, direction));
    await store.updateInitialSyncCursor({
      'book_id': bookId,
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
    });
  }

  static InitialSyncDiagnosticSummary _diagnosticFromCursor(
    Map<String, Object?>? cursor,
  ) {
    final encoded = cursor?['initial_sync_diagnostic_json'] as String?;
    if (encoded != null) {
      return InitialSyncDiagnosticSummary.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    }
    final manifest = cursor?['manifest_json'] as String?;
    if (manifest != null) {
      return InitialSyncDiagnosticSummary.forManifest(
        InitialSyncManifest.fromJson(
          (jsonDecode(manifest) as Map).cast<String, Object?>(),
        ),
      );
    }
    return InitialSyncDiagnosticSummary({
      for (final entityType in initialSyncEntityOrder)
        entityType: const InitialSyncEntityDiagnostic(),
    });
  }
}
