import 'initial_sync_models.dart';

abstract interface class InitialSyncTransport {
  bool get isConfigured;
  bool get isAuthenticated;

  Future<InitialSyncManifest> inspect(String bookId);
  Future<InitialSyncSession> beginUpload(InitialSyncManifest localManifest);
  Future<int> uploadBatch({
    required String sessionId,
    required String entityType,
    required List<Map<String, Object?>> rows,
  });
  Future<int> completeUpload(String sessionId);
  Future<InitialSyncSession> beginDownload(String bookId);
  Future<InitialSyncBatch> downloadBatch({
    required String sessionId,
    required String entityType,
    String? afterEntityId,
    int limit = 100,
  });
  Future<void> cancel(String sessionId);
}

/// Optional capability for consumers that must inspect the authoritative
/// household without creating an initial-sync session or writing remote state.
abstract interface class ReadOnlyHouseholdSnapshotTransport {
  Future<Map<String, List<Map<String, Object?>>>> readHouseholdSnapshot(
    String bookId,
  );
}

class UnavailableInitialSyncTransport implements InitialSyncTransport {
  const UnavailableInitialSyncTransport({this.configured = false});

  final bool configured;

  @override
  bool get isConfigured => configured;
  @override
  bool get isAuthenticated => false;

  Never _unavailable() => throw InitialSyncException(
    configured
        ? InitialSyncErrorCode.signedOut
        : InitialSyncErrorCode.notConfigured,
    configured
        ? 'Sign in is required before initial synchronization.'
        : 'Cloud sharing is not configured.',
  );

  @override
  Future<InitialSyncManifest> inspect(String bookId) async => _unavailable();
  @override
  Future<InitialSyncSession> beginUpload(
    InitialSyncManifest localManifest,
  ) async => _unavailable();
  @override
  Future<int> uploadBatch({
    required String sessionId,
    required String entityType,
    required List<Map<String, Object?>> rows,
  }) async => _unavailable();
  @override
  Future<int> completeUpload(String sessionId) async => _unavailable();
  @override
  Future<InitialSyncSession> beginDownload(String bookId) async =>
      _unavailable();
  @override
  Future<InitialSyncBatch> downloadBatch({
    required String sessionId,
    required String entityType,
    String? afterEntityId,
    int limit = 100,
  }) async => _unavailable();
  @override
  Future<void> cancel(String sessionId) async => _unavailable();
}
