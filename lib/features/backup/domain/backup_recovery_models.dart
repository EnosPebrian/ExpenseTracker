enum BackupRecoveryClassification {
  identical,
  missing,
  changedConflict,
  remoteDeleted,
  semanticDuplicate,
  possibleDuplicate,
  invalidReference,
  foreignHousehold,
  recoverableDependency,
  unsupported,
}

class BackupRecoveryCloudState {
  const BackupRecoveryCloudState({
    required this.linked,
    required this.ready,
    this.cursor,
  });

  final bool linked;
  final bool ready;
  final int? cursor;
}

class BackupRecoveryCandidate {
  const BackupRecoveryCandidate({
    required this.entityType,
    required this.id,
    required this.record,
    required this.classification,
    this.dependencies = const [],
    this.reason,
  });

  final String entityType;
  final String id;
  final Map<String, Object?> record;
  final BackupRecoveryClassification classification;
  final List<String> dependencies;
  final String? reason;

  bool get selectable =>
      classification == BackupRecoveryClassification.missing ||
      classification == BackupRecoveryClassification.recoverableDependency;

  String get key => '$entityType::$id';

  BackupRecoveryCandidate copyWith({
    BackupRecoveryClassification? classification,
    List<String>? dependencies,
    String? reason,
  }) => BackupRecoveryCandidate(
    entityType: entityType,
    id: id,
    record: record,
    classification: classification ?? this.classification,
    dependencies: dependencies ?? this.dependencies,
    reason: reason ?? this.reason,
  );
}

class BackupRecoveryPreview {
  const BackupRecoveryPreview({
    required this.backupHouseholdName,
    required this.currentHouseholdName,
    required this.formatVersion,
    required this.exportedAt,
    required this.cloudState,
    required this.remoteVerified,
    required this.candidates,
    this.blockingErrors = const [],
  });

  final String backupHouseholdName;
  final String currentHouseholdName;
  final int formatVersion;
  final DateTime exportedAt;
  final BackupRecoveryCloudState cloudState;
  final bool remoteVerified;
  final List<BackupRecoveryCandidate> candidates;
  final List<String> blockingErrors;

  bool get canRecover =>
      blockingErrors.isEmpty && (!cloudState.linked || remoteVerified);

  int count(BackupRecoveryClassification classification) => candidates
      .where((candidate) => candidate.classification == classification)
      .length;

  Map<String, int> countsFor(BackupRecoveryClassification classification) {
    final result = <String, int>{};
    for (final candidate in candidates.where(
      (candidate) => candidate.classification == classification,
    )) {
      result[candidate.entityType] = (result[candidate.entityType] ?? 0) + 1;
    }
    return result;
  }
}

class BackupRecoveryPlan {
  const BackupRecoveryPlan({required this.records, required this.selectedKeys});

  final Map<String, List<Map<String, Object?>>> records;
  final Set<String> selectedKeys;
  int get recordCount =>
      records.values.fold(0, (total, rows) => total + rows.length);
}

class BackupRecoveryResult {
  const BackupRecoveryResult({
    required this.recoveredByEntity,
    required this.skippedAlreadyPresent,
    required this.skippedDuplicates,
    required this.conflictsKeptCurrent,
    required this.blocked,
    required this.pendingCount,
    required this.completedAt,
  });

  final Map<String, int> recoveredByEntity;
  final int skippedAlreadyPresent;
  final int skippedDuplicates;
  final int conflictsKeptCurrent;
  final int blocked;
  final int pendingCount;
  final DateTime completedAt;
}
