import 'dart:convert';

import '../../../core/database/local_store.dart';
import '../domain/sync_models.dart';
import '../domain/sync_repository.dart';

class LocalSyncRepository implements SyncRepository, SyncConflictRepository {
  LocalSyncRepository(this.store);

  final LocalStore store;

  @override
  Future<SyncCursor?> getCursor(String bookId) async {
    final record = await store.getSyncCursor(bookId);
    return record == null ? null : SyncCursor.fromRecord(record);
  }

  @override
  Future<void> setInitializationState(
    String bookId,
    SyncInitializationState state,
  ) => store.setSyncInitializationState(bookId, state.name);

  @override
  Future<List<SyncOperation>> getEligibleOperations(
    String bookId, {
    int limit = 50,
  }) async => (await store.getEligibleSyncOperations(
    bookId,
    limit: limit,
  )).map(SyncOperation.fromRecord).toList();

  @override
  Future<int> pendingCount(String bookId) => store.getPendingSyncCount(bookId);

  @override
  Future<void> recoverInterrupted(String bookId) =>
      store.recoverInterruptedSyncOperations(bookId);

  @override
  Future<void> markSending(Iterable<String> operationIds) =>
      store.markSyncOperationsSending(operationIds.toList());

  @override
  Future<void> markCompleted(String operationId, int? serverVersion) =>
      store.completeSyncOperation(operationId, serverVersion: serverVersion);

  @override
  Future<void> scheduleRetry(
    String operationId, {
    required String errorCode,
    required String safeMessage,
    required DateTime nextAttemptAt,
  }) => store.scheduleSyncRetry(
    operationId,
    errorCode: errorCode,
    safeMessage: safeMessage,
    nextAttemptAt: nextAttemptAt.millisecondsSinceEpoch,
  );

  @override
  Future<void> recordConflict(
    SyncOperation operation,
    PushOperationResult result,
  ) {
    final local = operation.payload ?? const <String, Object?>{};
    final server = result.serverPayload ?? const <String, Object?>{};
    final changed = <String>{...local.keys, ...server.keys}
      ..removeWhere(
        (field) =>
            const {
              'version',
              'updated_at',
              'device_id',
              'sync_status',
            }.contains(field) ||
            local[field] == server[field],
      );
    final type = _classify(operation, server, changed);
    return store.recordSyncConflict({
      'book_id': operation.bookId,
      'entity_type': operation.entityType,
      'entity_id': operation.entityId,
      'operation_id': operation.operationId,
      'base_version': operation.baseVersion,
      'server_version': result.serverVersion ?? 0,
      'local_payload_json': operation.payload == null
          ? null
          : jsonEncode(operation.payload),
      'server_payload_json': result.serverPayload == null
          ? null
          : jsonEncode(result.serverPayload),
      'conflict_type': type.name,
      'changed_local_fields_json': jsonEncode(changed.toList()..sort()),
      'changed_server_fields_json': jsonEncode(changed.toList()..sort()),
      'resolution_status': 'unresolved',
    });
  }

  SyncConflictType _classify(
    SyncOperation operation,
    Map<String, Object?> server,
    Set<String> changed,
  ) {
    final localDeleted =
        operation.operationType == SyncOperationType.delete ||
        operation.payload?['deleted_at'] != null;
    final serverDeleted = server['deleted_at'] != null;
    if (localDeleted && !serverDeleted) {
      return SyncConflictType.deleteVersusUpdate;
    }
    if (!localDeleted && serverDeleted) {
      return SyncConflictType.updateVersusDelete;
    }
    if (changed.contains('related_transaction_id') ||
        changed.contains('relation_type')) {
      return SyncConflictType.linkedTransactionConflict;
    }
    if (operation.entityType == 'transfer_links') {
      return SyncConflictType.linkedTransactionConflict;
    }
    if (operation.entityType == 'transactions' &&
        changed.any(
          const {
            'quantity',
            'unit_price',
            'asset_action',
            'fee_amount',
            'fee_treatment',
          }.contains,
        )) {
      return SyncConflictType.assetTradeConflict;
    }
    if (changed.contains('owner_member_id')) {
      return SyncConflictType.ownershipConflict;
    }
    if (changed.contains('opening_balance') ||
        changed.contains('opening_balance_date')) {
      return SyncConflictType.openingBalanceConflict;
    }
    return operation.entityType == 'transactions'
        ? SyncConflictType.generalEntityConflict
        : SyncConflictType.versionConflict;
  }

  @override
  Future<int> unresolvedConflictCount(String bookId) =>
      store.getUnresolvedSyncConflictCount(bookId);

  @override
  Future<List<SyncConflict>> conflicts(String bookId) async =>
      (await store.getSyncConflicts(
        bookId,
      )).map(SyncConflict.fromRecord).toList();

  @override
  Future<bool> beginResolution(String conflictId, String operationId) =>
      store.beginSyncConflictResolution(conflictId, operationId);

  @override
  Future<void> failResolution(String conflictId) =>
      store.failSyncConflictResolution(conflictId);

  @override
  Future<void> completeResolution(
    String conflictId, {
    required String resolution,
    required Map<String, Object?> canonicalPayload,
    required int serverSequence,
  }) => store.completeSyncConflictResolution(
    conflictId,
    resolution: resolution,
    canonicalPayload: canonicalPayload,
    serverSequence: serverSequence,
  );

  @override
  Future<void> applyRemoteBatch(String bookId, PullBatch batch) =>
      store.applyRemoteSyncBatch(
        bookId,
        changes: [
          for (final change in batch.changes)
            {
              'sequence': change.sequence,
              'entity_type': change.entityType,
              'entity_id': change.entityId,
              'operation_type': change.operationType.name,
              'payload': change.payload,
            },
        ],
        finalSequence: batch.finalSequence,
      );
}
