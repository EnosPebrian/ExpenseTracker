import 'dart:convert';

import '../../../core/database/local_store_web.dart';
import '../domain/initial_sync_models.dart';
import '../domain/sync_models.dart';

class InitialSyncStoreAdapter {
  InitialSyncStoreAdapter(this.store);

  final LocalStore store;
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
    for (final row in batch.rows) {
      final id = row['id'];
      if (id == null ||
          (batch.entityType == 'books'
              ? id != bookId
              : row['book_id'] != bookId)) {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'The downloaded snapshot contains another household.',
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
      }
    }
    final cursor = await store.getSyncCursor(bookId);
    await store.updateInitialSyncCursor({
      'book_id': bookId,
      'downloaded_count':
          ((cursor?['downloaded_count'] as num?)?.toInt() ?? 0) + inserted,
      'last_processed_entity': batch.entityType,
      'last_processed_cursor': batch.nextCursor,
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

  Future<void> activateDownload({
    required String bookId,
    required InitialSyncManifest manifest,
    required String? authUserId,
  }) async {
    if (await targetHasFinancialData(bookId)) {
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
    await store.applyRemoteSyncBatch(
      bookId,
      changes: rows,
      finalSequence: manifest.snapshotSequence,
    );
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
  }

  Future<void> recordFailure(
    String bookId, {
    required String code,
    required String message,
  }) => store.updateInitialSyncCursor({
    'book_id': bookId,
    'initialization_state': SyncInitializationState.failed.name,
    'last_error_code': code,
    'last_error_message': message,
  });

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
      'last_error_code': null,
      'last_error_message': null,
      'manifest_json': null,
      'snapshot_sequence': 0,
      'snapshot_outbox_rowid': 0,
    });
  }
}
