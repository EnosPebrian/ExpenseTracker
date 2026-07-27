import 'dart:convert';

import '../../../core/database/local_store.dart';
import '../domain/sync_models.dart';
import '../domain/sync_repository.dart';

class LocalSyncRepository implements SyncRepository {
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
  ) => store.recordSyncConflict({
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
  });

  @override
  Future<int> unresolvedConflictCount(String bookId) =>
      store.getUnresolvedSyncConflictCount(bookId);

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
