import '../domain/initial_sync_models.dart';
import '../domain/initial_sync_repository.dart';
import '../domain/sync_models.dart';
import 'initial_sync_store.dart';
import 'local_sync_repository.dart';

class LocalInitialSyncRepository implements InitialSyncRepository {
  LocalInitialSyncRepository({
    required this.syncRepository,
    required this.store,
  });

  final LocalSyncRepository syncRepository;
  final InitialSyncStoreAdapter store;

  @override
  Future<SyncCursor?> getCursor(String bookId) =>
      syncRepository.getCursor(bookId);
  @override
  Future<void> prepareSecondary(String bookId) =>
      syncRepository.setInitializationState(
        bookId,
        SyncInitializationState.secondaryDownloadRequired,
      );
  @override
  Future<int> unresolvedConflictCount(String bookId) =>
      syncRepository.unresolvedConflictCount(bookId);
  @override
  Future<InitialSyncManifest> captureUploadSnapshot(String bookId) =>
      store.captureUploadSnapshot(bookId);
  @override
  Future<List<Map<String, Object?>>> readUploadRows(
    String bookId,
    String entityType, {
    int limit = 100,
  }) => store.readUploadRows(bookId, entityType, limit: limit);
  @override
  Future<void> markUploadRowsTransferred(
    String bookId,
    String entityType,
    Iterable<String> entityIds,
  ) => store.markUploadRowsTransferred(bookId, entityType, entityIds);
  @override
  Future<void> startInitialization({
    required String bookId,
    required InitialSyncDirection direction,
    required String sessionId,
    required InitialSyncManifest manifest,
  }) => store.startInitialization(
    bookId: bookId,
    direction: direction,
    sessionId: sessionId,
    manifest: manifest,
  );
  @override
  Future<bool> targetHasFinancialData(String bookId) =>
      store.targetHasFinancialData(bookId);
  @override
  Future<void> stageDownloadBatch(String bookId, InitialSyncBatch batch) =>
      store.stageDownloadBatch(bookId, batch);
  @override
  Future<void> completeUpload(String bookId, int finalSequence) =>
      store.completeUpload(bookId, finalSequence);
  @override
  Future<void> activateDownload({
    required String bookId,
    required InitialSyncManifest manifest,
    required String? authUserId,
  }) => store.activateDownload(
    bookId: bookId,
    manifest: manifest,
    authUserId: authUserId,
  );
  @override
  Future<InitialSyncDiagnosticSummary> getDiagnosticSummary(String bookId) =>
      store.getDiagnosticSummary(bookId);
  @override
  Future<void> recordFailure(
    String bookId, {
    required InitialSyncException error,
  }) => store.recordFailure(bookId, error: error);
  @override
  Future<void> cancelInitialization(
    String bookId,
    InitialSyncDirection direction,
  ) => store.cancelInitialization(bookId, direction);
}
