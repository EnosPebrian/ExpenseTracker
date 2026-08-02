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
    this.diagnosticMessage,
  });

  final bool success;
  final String message;
  final InitialSyncManifest? manifest;
  final int? finalSequence;
  final String? diagnosticMessage;
}

class InitialSyncEntityDiagnostic {
  const InitialSyncEntityDiagnostic({
    this.remote = 0,
    this.fetched = 0,
    this.decoded = 0,
    this.persisted = 0,
    this.skipped = 0,
    this.failed = 0,
    this.locallyQueryable = 0,
  });

  final int remote;
  final int fetched;
  final int decoded;
  final int persisted;
  final int skipped;
  final int failed;
  final int locallyQueryable;

  InitialSyncEntityDiagnostic copyWith({
    int? remote,
    int? fetched,
    int? decoded,
    int? persisted,
    int? skipped,
    int? failed,
    int? locallyQueryable,
  }) => InitialSyncEntityDiagnostic(
    remote: remote ?? this.remote,
    fetched: fetched ?? this.fetched,
    decoded: decoded ?? this.decoded,
    persisted: persisted ?? this.persisted,
    skipped: skipped ?? this.skipped,
    failed: failed ?? this.failed,
    locallyQueryable: locallyQueryable ?? this.locallyQueryable,
  );

  Map<String, Object?> toJson() => {
    'remote': remote,
    'fetched': fetched,
    'decoded': decoded,
    'persisted': persisted,
    'skipped': skipped,
    'failed': failed,
    'locally_queryable': locallyQueryable,
  };

  factory InitialSyncEntityDiagnostic.fromJson(Map<String, Object?> json) =>
      InitialSyncEntityDiagnostic(
        remote: (json['remote'] as num?)?.toInt() ?? 0,
        fetched: (json['fetched'] as num?)?.toInt() ?? 0,
        decoded: (json['decoded'] as num?)?.toInt() ?? 0,
        persisted: (json['persisted'] as num?)?.toInt() ?? 0,
        skipped: (json['skipped'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        locallyQueryable: (json['locally_queryable'] as num?)?.toInt() ?? 0,
      );
}

class InitialSyncDiagnosticSummary {
  const InitialSyncDiagnosticSummary(this.entities);

  final Map<String, InitialSyncEntityDiagnostic> entities;

  int get fetched => _sum((value) => value.fetched);
  int get decoded => _sum((value) => value.decoded);
  int get persisted => _sum((value) => value.persisted);
  int get skipped => _sum((value) => value.skipped);
  int get failed => _sum((value) => value.failed);

  int _sum(int Function(InitialSyncEntityDiagnostic) select) =>
      entities.values.fold(0, (total, value) => total + select(value));

  Map<String, Object?> toJson() => {
    for (final entry in entities.entries) entry.key: entry.value.toJson(),
  };

  factory InitialSyncDiagnosticSummary.fromJson(Map<String, Object?> json) =>
      InitialSyncDiagnosticSummary({
        for (final entityType in initialSyncEntityOrder)
          entityType: InitialSyncEntityDiagnostic.fromJson(
            (json[entityType] as Map? ?? const {}).cast<String, Object?>(),
          ),
      });

  factory InitialSyncDiagnosticSummary.forManifest(
    InitialSyncManifest manifest,
  ) => InitialSyncDiagnosticSummary({
    for (final entityType in initialSyncEntityOrder)
      entityType: InitialSyncEntityDiagnostic(
        remote: manifest.counts[entityType] ?? 0,
      ),
  });
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
  const InitialSyncException(
    this.code,
    this.safeMessage, {
    this.entityType,
    this.recordId,
    this.phase,
    this.exceptionClass,
    this.lastCommittedCursor,
    this.committedRecords,
  });

  final InitialSyncErrorCode code;
  final String safeMessage;
  final String? entityType;
  final String? recordId;
  final String? phase;
  final String? exceptionClass;
  final String? lastCommittedCursor;
  final int? committedRecords;

  String get diagnosticMessage => [
    'Initial sync failure',
    if (phase != null) 'phase=$phase',
    if (entityType != null) 'entity=$entityType',
    if (recordId != null) 'record=$recordId',
    if (exceptionClass != null) 'class=$exceptionClass',
    if (lastCommittedCursor != null) 'cursor=$lastCommittedCursor',
    if (committedRecords != null) 'persisted=$committedRecords',
    'message=$safeMessage',
  ].join(' ');

  @override
  String toString() => safeMessage;
}
