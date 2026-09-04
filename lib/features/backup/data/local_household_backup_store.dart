import '../../../core/database/local_store.dart';
import '../domain/backup_recovery_models.dart';
import '../domain/backup_recovery_service.dart';
import '../domain/household_backup_service.dart';

class LocalHouseholdBackupStore
    implements HouseholdBackupStore, BackupRecoveryStore {
  const LocalHouseholdBackupStore(this.store);

  final LocalStore store;

  @override
  int get schemaVersion => LocalStore.schemaVersion;

  @override
  Future<Map<String, List<Map<String, Object?>>>> snapshot(String bookId) {
    return store.createHouseholdBackupSnapshot(bookId);
  }

  @override
  Future<List<Map<String, Object?>>> localHouseholds() {
    return store.getFinancialBooks(includeDeleted: true);
  }

  @override
  Future<void> activate(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) {
    return store.activateHouseholdBackupSnapshot(
      snapshot,
      replaceBookId: replaceBookId,
      idempotent: idempotent,
    );
  }

  @override
  Future<Map<String, List<Map<String, Object?>>>> recoverySnapshot(
    String bookId,
  ) => store.createHouseholdBackupSnapshot(bookId);

  @override
  Future<BackupRecoveryCloudState> recoveryCloudState(String bookId) async {
    final books = await store.getFinancialBooks(includeDeleted: true);
    final book = books.firstWhere(
      (row) => row['id'] == bookId,
      orElse: () => const <String, Object?>{},
    );
    final linked = book['remote_linked_at'] != null;
    final cursor = await store.getSyncCursor(bookId);
    return BackupRecoveryCloudState(
      linked: linked,
      ready: !linked || cursor?['initialization_state'] == 'ready',
      cursor: (cursor?['last_server_sequence'] as num?)?.toInt(),
    );
  }

  @override
  Future<int> commitRecovery(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) => store.recoverHouseholdBackupRecords(
    bookId,
    records,
    enqueueSync: enqueueSync,
  );
}
