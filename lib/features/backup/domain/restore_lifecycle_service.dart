import '../../../features/master_data/domain/entities/financial_book.dart';
import '../../../features/master_data/domain/entities/household_member.dart';
import 'backup_models.dart';
import 'household_backup_integrity.dart';
import 'household_backup_service.dart';

class RestoreLifecyclePreview {
  const RestoreLifecyclePreview({
    required this.sourceBookId,
    required this.householdName,
    required this.baseCurrencyCode,
    required this.proposedName,
    required this.entityCounts,
  });

  final String sourceBookId;
  final String householdName;
  final String baseCurrencyCode;
  final String proposedName;
  final Map<String, int> entityCounts;

  int get recordCount =>
      entityCounts.values.fold(0, (sum, value) => sum + value);
}

class RestoreLifecycleClone {
  const RestoreLifecycleClone({
    required this.sourceBookId,
    required this.book,
    required this.owner,
    required this.entityCounts,
  });

  final String sourceBookId;
  final FinancialBook book;
  final HouseholdMember owner;
  final Map<String, int> entityCounts;
}

/// Validates and clones a restored local-only household before cloud bootstrap.
///
/// The source snapshot is never modified. The clone receives a new household ID
/// and a consistent remap of every globally unique entity ID and reference.
class RestoreLifecycleService {
  const RestoreLifecycleService(this.store);

  final HouseholdBackupStore store;

  static bool isRestoredLocalOnly(FinancialBook? book) =>
      book != null &&
      book.remoteLinkedAt == null &&
      book.deviceId == 'restore-device';

  Future<RestoreLifecyclePreview> preview(
    String bookId, {
    String? proposedName,
  }) async {
    final snapshot = await _validatedSnapshot(bookId);
    final household = snapshot['household']!.single;
    final sourceName = household['name'] as String;
    final name = _validatedName(proposedName ?? '$sourceName (Recovered)');
    return RestoreLifecyclePreview(
      sourceBookId: bookId,
      householdName: sourceName,
      baseCurrencyCode: household['base_currency_code'] as String? ?? 'IDR',
      proposedName: name,
      entityCounts: _counts(snapshot),
    );
  }

  Future<RestoreLifecycleClone> cloneForNewSharedHousehold({
    required String sourceBookId,
    required String proposedName,
  }) async {
    final source = await _validatedSnapshot(sourceBookId);
    final prepared = HouseholdBackupIntegrity.prepareForRestore(
      source,
      remapAsCopy: true,
    );
    final household = prepared['household']!.single;
    household['name'] = _validatedName(proposedName);
    final activeMembers = prepared['members']!
        .where((record) => record['deleted_at'] == null)
        .toList();
    final ownerRecord = activeMembers.firstWhere(
      (record) => record['role'] == 'owner',
      orElse: () => activeMembers.first,
    );
    ownerRecord['role'] = 'owner';

    HouseholdBackupIntegrity.validate(prepared);
    HouseholdBackupIntegrity.financialSummary(prepared);
    await store.activate(prepared);

    final book = FinancialBook.fromRecord(household);
    return RestoreLifecycleClone(
      sourceBookId: sourceBookId,
      book: book,
      owner: HouseholdMember.fromRecord(ownerRecord),
      entityCounts: _counts(prepared),
    );
  }

  Future<Map<String, List<Map<String, Object?>>>> _validatedSnapshot(
    String bookId,
  ) async {
    final rawSnapshot = await store.snapshot(bookId);
    final rawHouseholds = rawSnapshot['household'] ?? const [];
    if (rawHouseholds.length != 1) {
      throw const BackupValidationException(
        'The restored household snapshot is incomplete or belongs to another household.',
      );
    }
    final book = FinancialBook.fromRecord(rawHouseholds.single);
    if (!isRestoredLocalOnly(book)) {
      throw const BackupValidationException(
        'Create new shared household is available only for a completed local-only restore.',
      );
    }

    final snapshot = HouseholdBackupIntegrity.sanitize(rawSnapshot);
    final households = snapshot['household'] ?? const [];
    if (households.length != 1 || households.single['id'] != bookId) {
      throw const BackupValidationException(
        'The restored household snapshot is incomplete or belongs to another household.',
      );
    }
    HouseholdBackupIntegrity.validate(snapshot);
    HouseholdBackupIntegrity.financialSummary(snapshot);
    return snapshot;
  }

  static Map<String, int> _counts(
    Map<String, List<Map<String, Object?>>> snapshot,
  ) => {
    for (final key in portableBackupEntityKeys) key: snapshot[key]?.length ?? 0,
  };

  static String _validatedName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 120) {
      throw const BackupValidationException(
        'Enter a household name between 1 and 120 characters.',
      );
    }
    return name;
  }
}
