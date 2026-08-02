import 'sync_models.dart';

enum SyncTransportErrorKind {
  network,
  authentication,
  authorization,
  validation,
}

class SyncTransportException implements Exception {
  const SyncTransportException(this.kind, this.safeMessage);

  final SyncTransportErrorKind kind;
  final String safeMessage;
}

abstract interface class SyncTransport {
  bool get isConfigured;
  bool get isAuthenticated;

  Future<List<PushOperationResult>> push(
    String bookId,
    List<SyncOperation> operations,
  );

  Future<PullBatch> pull(
    String bookId, {
    required int afterSequence,
    int limit = 100,
  });
}

abstract interface class ConflictResolutionTransport {
  Future<ConflictResolutionResult> resolveConflict({
    required SyncConflict conflict,
    required String resolutionOperationId,
    required ConflictResolutionType resolutionType,
    Map<String, Object?>? resolvedPayload,
  });
}

abstract interface class SyncWakeupTransport {
  Future<void> subscribeToBookChanges(String bookId, void Function() onWakeup);
  Future<void> unsubscribeFromBookChanges();
}

class UnavailableSyncTransport implements SyncTransport {
  const UnavailableSyncTransport({this.configured = false});

  final bool configured;

  @override
  bool get isConfigured => configured;

  @override
  bool get isAuthenticated => false;

  @override
  Future<PullBatch> pull(
    String bookId, {
    required int afterSequence,
    int limit = 100,
  }) => throw const SyncTransportException(
    SyncTransportErrorKind.authentication,
    'Sign in is required before synchronization.',
  );

  @override
  Future<List<PushOperationResult>> push(
    String bookId,
    List<SyncOperation> operations,
  ) => throw const SyncTransportException(
    SyncTransportErrorKind.authentication,
    'Sign in is required before synchronization.',
  );
}
