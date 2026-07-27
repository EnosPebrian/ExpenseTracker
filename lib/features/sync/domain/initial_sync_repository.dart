import 'initial_sync_models.dart';
import 'sync_models.dart';

abstract interface class InitialSyncRepository {
  Future<SyncCursor?> getCursor(String bookId);
  Future<void> prepareSecondary(String bookId);
  Future<int> unresolvedConflictCount(String bookId);
  Future<InitialSyncManifest> captureUploadSnapshot(String bookId);
  Future<List<Map<String, Object?>>> readUploadRows(
    String bookId,
    String entityType, {
    int limit = 100,
  });
  Future<void> markUploadRowsTransferred(
    String bookId,
    String entityType,
    Iterable<String> entityIds,
  );
  Future<void> startInitialization({
    required String bookId,
    required InitialSyncDirection direction,
    required String sessionId,
    required InitialSyncManifest manifest,
  });
  Future<bool> targetHasFinancialData(String bookId);
  Future<void> stageDownloadBatch(String bookId, InitialSyncBatch batch);
  Future<void> completeUpload(String bookId, int finalSequence);
  Future<void> activateDownload({
    required String bookId,
    required InitialSyncManifest manifest,
    required String? authUserId,
  });
  Future<void> recordFailure(
    String bookId, {
    required String code,
    required String message,
  });
  Future<void> cancelInitialization(
    String bookId,
    InitialSyncDirection direction,
  );
}
