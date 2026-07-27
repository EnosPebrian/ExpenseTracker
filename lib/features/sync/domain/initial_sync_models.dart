enum InitialSyncDirection { upload, download }

const initialSyncEntityOrder = <String>[
  'books',
  'household_members',
  'categories',
  'projects',
  'accounts',
  'asset_definitions',
  'transactions',
];

class InitialSyncManifest {
  const InitialSyncManifest({
    required this.bookId,
    required this.bookName,
    required this.baseCurrencyCode,
    required this.counts,
    required this.snapshotSequence,
    this.memberRole,
    this.householdMemberId,
    this.remoteInitializationComplete = false,
    this.remoteRecordCount = 0,
  });

  final String bookId;
  final String bookName;
  final String baseCurrencyCode;
  final Map<String, int> counts;
  final int snapshotSequence;
  final String? memberRole;
  final String? householdMemberId;
  final bool remoteInitializationComplete;
  final int remoteRecordCount;

  int get totalCount => counts.values.fold(0, (total, value) => total + value);

  Map<String, Object?> toJson() => {
    'book_id': bookId,
    'book_name': bookName,
    'base_currency_code': baseCurrencyCode,
    'counts': counts,
    'snapshot_sequence': snapshotSequence,
    'member_role': memberRole,
    'household_member_id': householdMemberId,
    'remote_initialization_complete': remoteInitializationComplete,
    'remote_record_count': remoteRecordCount,
  };

  factory InitialSyncManifest.fromJson(Map<String, Object?> json) =>
      InitialSyncManifest(
        bookId: json['book_id'] as String,
        bookName: json['book_name'] as String? ?? 'Shared household',
        baseCurrencyCode: json['base_currency_code'] as String? ?? 'IDR',
        counts: (json['counts'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key as String, (value as num).toInt()),
        ),
        snapshotSequence: (json['snapshot_sequence'] as num?)?.toInt() ?? 0,
        memberRole: json['member_role'] as String?,
        householdMemberId: json['household_member_id'] as String?,
        remoteInitializationComplete:
            json['remote_initialization_complete'] == true,
        remoteRecordCount: (json['remote_record_count'] as num?)?.toInt() ?? 0,
      );
}

class InitialSyncSession {
  const InitialSyncSession({
    required this.id,
    required this.manifest,
    required this.direction,
  });

  final String id;
  final InitialSyncManifest manifest;
  final InitialSyncDirection direction;
}

class InitialSyncBatch {
  const InitialSyncBatch({
    required this.entityType,
    required this.rows,
    required this.nextCursor,
    required this.complete,
  });

  final String entityType;
  final List<Map<String, Object?>> rows;
  final String? nextCursor;
  final bool complete;
}

class InitialSyncResult {
  const InitialSyncResult({
    required this.success,
    required this.message,
    this.manifest,
    this.finalSequence,
  });

  final bool success;
  final String message;
  final InitialSyncManifest? manifest;
  final int? finalSequence;
}

enum InitialSyncErrorCode {
  notConfigured,
  signedOut,
  notOwner,
  remoteOccupied,
  remoteIncomplete,
  localTargetPopulated,
  conflict,
  validation,
  unavailable,
}

class InitialSyncException implements Exception {
  const InitialSyncException(this.code, this.safeMessage);

  final InitialSyncErrorCode code;
  final String safeMessage;

  @override
  String toString() => safeMessage;
}
