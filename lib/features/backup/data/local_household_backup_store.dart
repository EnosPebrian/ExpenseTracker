import '../../../core/database/local_store.dart';
import '../domain/household_backup_service.dart';

class LocalHouseholdBackupStore implements HouseholdBackupStore {
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
}
