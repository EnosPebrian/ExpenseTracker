import 'sync_models.dart';

abstract interface class SyncRepository {
  Future<SyncCursor?> getCursor(String bookId);
  Future<void> setInitializationState(
    String bookId,
    SyncInitializationState state,
  );
  Future<List<SyncOperation>> getEligibleOperations(
    String bookId, {
    int limit = 50,
  });
  Future<int> pendingCount(String bookId);
  Future<void> recoverInterrupted(String bookId);
  Future<void> markSending(Iterable<String> operationIds);
  Future<void> markCompleted(String operationId, int? serverVersion);
  Future<void> scheduleRetry(
    String operationId, {
    required String errorCode,
    required String safeMessage,
    required DateTime nextAttemptAt,
  });
  Future<void> recordConflict(
    SyncOperation operation,
    PushOperationResult result,
  );
  Future<int> unresolvedConflictCount(String bookId);
  Future<void> applyRemoteBatch(String bookId, PullBatch batch);
}

abstract interface class SyncConflictRepository {
  Future<List<SyncConflict>> conflicts(String bookId);
  Future<bool> beginResolution(String conflictId, String operationId);
  Future<void> failResolution(String conflictId);
  Future<void> completeResolution(
    String conflictId, {
    required String resolution,
    required Map<String, Object?> canonicalPayload,
    required int serverSequence,
  });
}
