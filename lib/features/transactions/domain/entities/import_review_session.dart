import 'dart:convert';

import 'package:uuid/uuid.dart';

enum ImportReviewSourceType { csv, receipt, invoice, bankStatement }

enum ImportReviewSessionState {
  pendingReview,
  readyToCommit,
  completed,
  discarded,
}

class ImportReviewSession {
  ImportReviewSession({
    String? id,
    required this.bookId,
    required this.sourceType,
    required this.title,
    required this.sourceFingerprint,
    this.destinationAccountId,
    this.state = ImportReviewSessionState.pendingReview,
    this.createdByMemberId,
    this.summary = const {},
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now() {
    if (title.trim().isEmpty || title.trim().length > 160) {
      throw ArgumentError.value(
        title,
        'title',
        'Must contain 1–160 characters.',
      );
    }
    if (sourceFingerprint.trim().isEmpty) {
      throw ArgumentError.value(sourceFingerprint, 'sourceFingerprint');
    }
  }

  final String id;
  final String bookId;
  final ImportReviewSourceType sourceType;
  final String title;
  final String sourceFingerprint;
  final String? destinationAccountId;
  final ImportReviewSessionState state;
  final String? createdByMemberId;
  final Map<String, Object?> summary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  bool get terminal =>
      state == ImportReviewSessionState.completed ||
      state == ImportReviewSessionState.discarded;

  ImportReviewSession transition(
    ImportReviewSessionState next, {
    DateTime? at,
  }) {
    const allowed = {
      ImportReviewSessionState.pendingReview: {
        ImportReviewSessionState.readyToCommit,
        ImportReviewSessionState.discarded,
      },
      ImportReviewSessionState.readyToCommit: {
        ImportReviewSessionState.completed,
      },
      ImportReviewSessionState.completed: <ImportReviewSessionState>{},
      ImportReviewSessionState.discarded: <ImportReviewSessionState>{},
    };
    if (next != state && !allowed[state]!.contains(next)) {
      throw StateError(
        'Invalid import review transition: ${state.name} → ${next.name}.',
      );
    }
    final timestamp = at ?? DateTime.now();
    return copyWith(
      state: next,
      updatedAt: timestamp,
      completedAt: next == ImportReviewSessionState.completed
          ? timestamp
          : completedAt,
      deletedAt: next == ImportReviewSessionState.discarded
          ? timestamp
          : deletedAt,
      version: next == state ? version : version + 1,
      syncStatus: next == state ? syncStatus : 'pending',
    );
  }

  ImportReviewSession copyWith({
    String? title,
    String? destinationAccountId,
    bool clearDestinationAccount = false,
    ImportReviewSessionState? state,
    Map<String, Object?>? summary,
    DateTime? updatedAt,
    DateTime? completedAt,
    DateTime? deletedAt,
    int? version,
    String? syncStatus,
  }) => ImportReviewSession(
    id: id,
    bookId: bookId,
    sourceType: sourceType,
    title: title ?? this.title,
    sourceFingerprint: sourceFingerprint,
    destinationAccountId: clearDestinationAccount
        ? null
        : destinationAccountId ?? this.destinationAccountId,
    state: state ?? this.state,
    createdByMemberId: createdByMemberId,
    summary: summary ?? this.summary,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: completedAt ?? this.completedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    version: version ?? this.version,
    deviceId: deviceId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'book_id': bookId,
    'source_type': sourceType.name,
    'title': title.trim(),
    'source_fingerprint': sourceFingerprint,
    'destination_account_id': destinationAccountId,
    'state': state.name,
    'created_by_member_id': createdByMemberId,
    'summary_json': jsonEncode(summary),
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'completed_at': completedAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory ImportReviewSession.fromRecord(Map<String, Object?> row) =>
      ImportReviewSession(
        id: row['id'] as String,
        bookId: row['book_id'] as String,
        sourceType: ImportReviewSourceType.values.byName(
          row['source_type'] as String,
        ),
        title: row['title'] as String,
        sourceFingerprint: row['source_fingerprint'] as String,
        destinationAccountId: row['destination_account_id'] as String?,
        state: ImportReviewSessionState.values.byName(row['state'] as String),
        createdByMemberId: row['created_by_member_id'] as String?,
        summary: (jsonDecode(row['summary_json'] as String? ?? '{}') as Map)
            .cast<String, Object?>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at'] as num).toInt(),
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updated_at'] as num).toInt(),
        ),
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (row['completed_at'] as num).toInt(),
              ),
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (row['deleted_at'] as num).toInt(),
              ),
        version: (row['version'] as num?)?.toInt() ?? 1,
        deviceId: row['device_id'] as String? ?? 'local-device',
        syncStatus: row['sync_status'] as String? ?? 'local_only',
      );
}
