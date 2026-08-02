import 'dart:typed_data';

const portableBackupFormatVersion = 1;
const portableBackupApplicationVersion = '1.0.0+1';

const portableBackupEntityKeys = <String>[
  'household',
  'members',
  'accounts',
  'categories',
  'projects',
  'transactions',
  'asset_definitions',
  'manual_market_prices',
];

enum RestoreMode { newHousehold, replaceMatchingHousehold }

class RestorePreview {
  const RestorePreview({
    required this.mode,
    required this.newByEntity,
    required this.identicalByEntity,
    required this.replacementByEntity,
    required this.conflictingByEntity,
    required this.invalidByEntity,
    required this.expectedFinalTotals,
    this.blockingErrors = const [],
    this.details = const [],
  });

  final RestoreMode mode;
  final Map<String, int> newByEntity;
  final Map<String, int> identicalByEntity;
  final Map<String, int> replacementByEntity;
  final Map<String, int> conflictingByEntity;
  final Map<String, int> invalidByEntity;
  final Map<String, int> expectedFinalTotals;
  final List<String> blockingErrors;
  final List<String> details;

  int get newRecords => _sum(newByEntity);
  int get alreadyPresent => _sum(identicalByEntity);
  int get recordsToReplace => _sum(replacementByEntity);
  int get conflicts => _sum(conflictingByEntity);
  int get invalidRecords => _sum(invalidByEntity);
  bool get canRestore =>
      conflicts == 0 && invalidRecords == 0 && blockingErrors.isEmpty;

  String? get blockingReason {
    if (blockingErrors.isNotEmpty) return blockingErrors.first;
    if (invalidRecords > 0) {
      return 'Restore contains $invalidRecords invalid record(s).';
    }
    if (conflicts > 0) {
      return 'Restore contains $conflicts blocking ID collision(s).';
    }
    return null;
  }

  static int _sum(Map<String, int> values) =>
      values.values.fold(0, (total, value) => total + value);
}

class RestoreResult {
  const RestoreResult({
    required this.bookId,
    required this.preview,
    required this.completedAt,
  });

  final String bookId;
  final RestorePreview preview;
  final DateTime completedAt;
}

enum ReferenceIssueSeverity { fatal, warning, information }

enum ReferenceState { nullValue, present, softDeleted, absent, crossBook }

class ReferenceIntegrityIssue {
  const ReferenceIntegrityIssue({
    required this.severity,
    required this.state,
    required this.entityId,
    required this.message,
  });

  final ReferenceIssueSeverity severity;
  final ReferenceState state;
  final String entityId;
  final String message;
}

class PortableBackupManifest {
  const PortableBackupManifest({
    required this.formatVersion,
    required this.applicationVersion,
    required this.databaseSchemaVersion,
    required this.exportedAt,
    required this.bookId,
    required this.bookName,
    required this.baseCurrencyCode,
    required this.entityCounts,
    required this.contentChecksum,
    required this.encryptionMetadata,
    required this.financialSummary,
    required this.deletedStateCounts,
  });

  final int formatVersion;
  final String applicationVersion;
  final int databaseSchemaVersion;
  final DateTime exportedAt;
  final String bookId;
  final String bookName;
  final String baseCurrencyCode;
  final Map<String, int> entityCounts;
  final String contentChecksum;
  final Map<String, Object?> encryptionMetadata;
  final Map<String, Object?> financialSummary;
  final Map<String, int> deletedStateCounts;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'applicationVersion': applicationVersion,
    'databaseSchemaVersion': databaseSchemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'bookId': bookId,
    'bookName': bookName,
    'baseCurrencyCode': baseCurrencyCode,
    'entityCounts': entityCounts,
    'contentChecksum': contentChecksum,
    'encryptionMetadata': encryptionMetadata,
    'financialSummary': financialSummary,
    'deletedStateCounts': deletedStateCounts,
  };

  factory PortableBackupManifest.fromJson(Map<String, Object?> json) {
    Map<String, int> integers(Object? value) => Map<String, Object?>.from(
      value! as Map,
    ).map((key, value) => MapEntry(key, (value as num).toInt()));

    return PortableBackupManifest(
      formatVersion: (json['formatVersion'] as num).toInt(),
      applicationVersion: json['applicationVersion'] as String,
      databaseSchemaVersion: (json['databaseSchemaVersion'] as num).toInt(),
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      bookId: json['bookId'] as String,
      bookName: json['bookName'] as String,
      baseCurrencyCode: json['baseCurrencyCode'] as String,
      entityCounts: integers(json['entityCounts']),
      contentChecksum: json['contentChecksum'] as String,
      encryptionMetadata: Map<String, Object?>.from(
        json['encryptionMetadata']! as Map,
      ),
      financialSummary: Map<String, Object?>.from(
        json['financialSummary']! as Map,
      ),
      deletedStateCounts: integers(json['deletedStateCounts']),
    );
  }
}

class CreatedBackup {
  const CreatedBackup({required this.bytes, required this.manifest});

  final Uint8List bytes;
  final PortableBackupManifest manifest;
}

class DecodedBackup {
  const DecodedBackup({required this.manifest, required this.snapshot});

  final PortableBackupManifest manifest;
  final Map<String, List<Map<String, Object?>>> snapshot;
}

class CreatedCsvBundle {
  const CreatedCsvBundle({required this.bytes, required this.recordCount});

  final Uint8List bytes;
  final int recordCount;
}

class CsvExportFilter {
  const CsvExportFilter({
    this.startDate,
    this.endDateInclusive,
    this.transactionTypes = const {},
    this.accountId,
    this.categoryId,
    this.projectId,
    this.memberId,
    this.includeDeleted = false,
  });

  final DateTime? startDate;
  final DateTime? endDateInclusive;
  final Set<String> transactionTypes;
  final String? accountId;
  final String? categoryId;
  final String? projectId;
  final String? memberId;
  final bool includeDeleted;

  CsvExportFilter copyWith({
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDateInclusive,
    bool clearEndDate = false,
    Set<String>? transactionTypes,
    String? accountId,
    bool clearAccount = false,
    String? categoryId,
    bool clearCategory = false,
    String? projectId,
    bool clearProject = false,
    String? memberId,
    bool clearMember = false,
    bool? includeDeleted,
  }) => CsvExportFilter(
    startDate: clearStartDate ? null : startDate ?? this.startDate,
    endDateInclusive: clearEndDate
        ? null
        : endDateInclusive ?? this.endDateInclusive,
    transactionTypes: transactionTypes ?? this.transactionTypes,
    accountId: clearAccount ? null : accountId ?? this.accountId,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    projectId: clearProject ? null : projectId ?? this.projectId,
    memberId: clearMember ? null : memberId ?? this.memberId,
    includeDeleted: includeDeleted ?? this.includeDeleted,
  );
}

class BackupValidationException implements Exception {
  const BackupValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupPasswordOrCorruptionException implements Exception {
  const BackupPasswordOrCorruptionException();

  @override
  String toString() => 'The password is wrong or the backup is corrupted.';
}

class UnsupportedBackupVersionException implements Exception {
  const UnsupportedBackupVersionException(this.version);
  final int version;

  @override
  String toString() =>
      'Backup format $version is newer than this app supports.';
}

class RestoreCollisionException implements Exception {
  const RestoreCollisionException(this.message);
  final String message;

  @override
  String toString() => message;
}
