import 'dart:convert';

import 'initial_sync_models.dart';

enum SyncOperationType { upsert, delete }

enum SyncOutboxStatus { pending, sending, retry, conflict, completed }

enum SyncInitializationState {
  notInitialized,
  primaryUploadRequired,
  secondaryDownloadRequired,
  uploading,
  downloading,
  ready,
  failed,
}

enum SyncStatus {
  localOnly,
  notConfigured,
  signedOut,
  primaryUploadRequired,
  secondaryDownloadRequired,
  initializing,
  initializationFailed,
  synced,
  pending,
  syncing,
  offline,
  retryScheduled,
  conflict,
  error,
}

class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.bookId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.baseVersion,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.attemptCount,
    required this.status,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  final String operationId;
  final String bookId;
  final String entityType;
  final String entityId;
  final SyncOperationType operationType;
  final int baseVersion;
  final Map<String, Object?>? payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final SyncOutboxStatus status;

  factory SyncOperation.fromRecord(Map<String, Object?> record) {
    final payloadJson = record['payload_json'] as String?;
    return SyncOperation(
      operationId: record['operation_id'] as String,
      bookId: record['book_id'] as String,
      entityType: record['entity_type'] as String,
      entityId: record['entity_id'] as String,
      operationType: SyncOperationType.values.byName(
        record['operation_type'] as String,
      ),
      baseVersion: (record['base_version'] as num).toInt(),
      payload: payloadJson == null
          ? null
          : (jsonDecode(payloadJson) as Map).cast<String, Object?>(),
      createdAt: _date(record['created_at']),
      updatedAt: _date(record['updated_at']),
      attemptCount: (record['attempt_count'] as num?)?.toInt() ?? 0,
      nextAttemptAt: _nullableDate(record['next_attempt_at']),
      lastErrorCode: record['last_error_code'] as String?,
      lastErrorMessage: record['last_error_message'] as String?,
      status: SyncOutboxStatus.values.byName(record['status'] as String),
    );
  }
}

class SyncCursor {
  const SyncCursor({
    required this.bookId,
    required this.lastServerSequence,
    required this.initializationState,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.lastProcessedEntity,
    this.lastProcessedCursor,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.initializationDirection,
    this.initializationSessionId,
    this.manifest,
    this.snapshotSequence = 0,
    this.snapshotOutboxRowId = 0,
    this.initialSyncDiagnostic,
  });

  final String bookId;
  final int lastServerSequence;
  final SyncInitializationState initializationState;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? lastProcessedEntity;
  final String? lastProcessedCursor;
  final int uploadedCount;
  final int downloadedCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? initializationDirection;
  final String? initializationSessionId;
  final Map<String, Object?>? manifest;
  final int snapshotSequence;
  final int snapshotOutboxRowId;
  final InitialSyncDiagnosticSummary? initialSyncDiagnostic;

  factory SyncCursor.fromRecord(Map<String, Object?> record) => SyncCursor(
    bookId: record['book_id'] as String,
    lastServerSequence: (record['last_server_sequence'] as num?)?.toInt() ?? 0,
    initializationState: SyncInitializationState.values.byName(
      record['initialization_state'] as String? ?? 'notInitialized',
    ),
    updatedAt: _date(record['updated_at']),
    startedAt: _nullableDate(record['started_at']),
    completedAt: _nullableDate(record['completed_at']),
    lastProcessedEntity: record['last_processed_entity'] as String?,
    lastProcessedCursor: record['last_processed_cursor'] as String?,
    uploadedCount: (record['uploaded_count'] as num?)?.toInt() ?? 0,
    downloadedCount: (record['downloaded_count'] as num?)?.toInt() ?? 0,
    lastErrorCode: record['last_error_code'] as String?,
    lastErrorMessage: record['last_error_message'] as String?,
    initializationDirection: record['initialization_direction'] as String?,
    initializationSessionId: record['initialization_session_id'] as String?,
    manifest: record['manifest_json'] is String
        ? (jsonDecode(record['manifest_json'] as String) as Map)
              .cast<String, Object?>()
        : null,
    snapshotSequence: (record['snapshot_sequence'] as num?)?.toInt() ?? 0,
    snapshotOutboxRowId:
        (record['snapshot_outbox_rowid'] as num?)?.toInt() ?? 0,
    initialSyncDiagnostic: record['initial_sync_diagnostic_json'] is String
        ? InitialSyncDiagnosticSummary.fromJson(
            (jsonDecode(record['initial_sync_diagnostic_json'] as String)
                    as Map)
                .cast<String, Object?>(),
          )
        : null,
  );
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.bookId,
    required this.entityType,
    required this.entityId,
    required this.operationId,
    required this.baseVersion,
    required this.serverVersion,
    required this.localPayload,
    required this.serverPayload,
    required this.createdAt,
    this.conflictType = SyncConflictType.versionConflict,
    this.changedLocalFields = const [],
    this.changedServerFields = const [],
    this.resolutionStatus = ConflictResolutionStatus.unresolved,
    this.resolutionOperationId,
  });

  final String id;
  final String bookId;
  final String entityType;
  final String entityId;
  final String operationId;
  final int baseVersion;
  final int serverVersion;
  final Map<String, Object?>? localPayload;
  final Map<String, Object?>? serverPayload;
  final DateTime createdAt;
  final SyncConflictType conflictType;
  final List<String> changedLocalFields;
  final List<String> changedServerFields;
  final ConflictResolutionStatus resolutionStatus;
  final String? resolutionOperationId;

  factory SyncConflict.fromRecord(Map<String, Object?> record) {
    List<String> fields(Object? value) =>
        value is String ? (jsonDecode(value) as List).cast<String>() : const [];
    Map<String, Object?>? payload(Object? value) => value is String
        ? (jsonDecode(value) as Map).cast<String, Object?>()
        : null;
    return SyncConflict(
      id: record['id'] as String,
      bookId: record['book_id'] as String,
      entityType: record['entity_type'] as String,
      entityId: record['entity_id'] as String,
      operationId: record['operation_id'] as String,
      baseVersion: (record['base_version'] as num).toInt(),
      serverVersion: (record['server_version'] as num).toInt(),
      localPayload: payload(record['local_payload_json']),
      serverPayload: payload(record['server_payload_json']),
      createdAt: _date(record['created_at']),
      conflictType: SyncConflictType.values.byName(
        record['conflict_type'] as String? ?? 'versionConflict',
      ),
      changedLocalFields: fields(record['changed_local_fields_json']),
      changedServerFields: fields(record['changed_server_fields_json']),
      resolutionStatus: ConflictResolutionStatus.values.byName(
        record['resolution_status'] as String? ?? 'unresolved',
      ),
      resolutionOperationId: record['resolution_operation_id'] as String?,
    );
  }
}

enum SyncConflictType {
  versionConflict,
  deleteVersusUpdate,
  updateVersusDelete,
  ownershipConflict,
  openingBalanceConflict,
  linkedTransactionConflict,
  assetTradeConflict,
  generalEntityConflict,
}

enum ConflictResolutionStatus {
  unresolved,
  resolving,
  resolved,
  resolutionFailed,
  dismissedOnlyWhenObsolete,
}

enum ConflictResolutionType {
  keepServer,
  keepDevice,
  manualMerge,
  keepDeleted,
  restoreDevice,
}

class ConflictResolutionResult {
  const ConflictResolutionResult({
    required this.status,
    this.canonicalPayload,
    this.serverVersion,
    this.serverSequence,
  });
  final String status;
  final Map<String, Object?>? canonicalPayload;
  final int? serverVersion;
  final int? serverSequence;
}

enum PushResultStatus {
  applied,
  alreadyApplied,
  versionConflict,
  unauthorized,
  validationError,
}

class PushOperationResult {
  const PushOperationResult({
    required this.operationId,
    required this.status,
    this.serverVersion,
    this.serverSequence,
    this.serverPayload,
    this.errorCode,
  });

  final String operationId;
  final PushResultStatus status;
  final int? serverVersion;
  final int? serverSequence;
  final Map<String, Object?>? serverPayload;
  final String? errorCode;
}

class RemoteChange {
  const RemoteChange({
    required this.sequence,
    required this.entityType,
    required this.entityId,
    required this.serverVersion,
    required this.operationType,
    required this.payload,
  });

  final int sequence;
  final String entityType;
  final String entityId;
  final int serverVersion;
  final SyncOperationType operationType;
  final Map<String, Object?> payload;
}

class PullBatch {
  const PullBatch({required this.changes, required this.finalSequence});

  final List<RemoteChange> changes;
  final int finalSequence;
}

class SyncRunResult {
  const SyncRunResult({
    required this.status,
    this.pendingCount = 0,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.message,
  });

  final SyncStatus status;
  final int pendingCount;
  final int pushedCount;
  final int pulledCount;
  final String? message;
}

DateTime _date(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);

DateTime? _nullableDate(Object? value) =>
    value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
