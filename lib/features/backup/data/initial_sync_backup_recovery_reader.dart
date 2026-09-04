import '../../sync/domain/initial_sync_models.dart';
import '../../sync/domain/initial_sync_transport.dart';
import '../domain/backup_recovery_service.dart';

class InitialSyncBackupRecoveryReader implements BackupRecoveryRemoteReader {
  const InitialSyncBackupRecoveryReader(this.transport);

  final InitialSyncTransport transport;

  @override
  bool get available =>
      transport.isConfigured &&
      transport.isAuthenticated &&
      transport is ReadOnlyHouseholdSnapshotTransport;

  @override
  Future<Map<String, List<Map<String, Object?>>>> read(String bookId) async {
    if (transport is! ReadOnlyHouseholdSnapshotTransport) {
      throw StateError('Read-only cloud verification is unavailable.');
    }
    final snapshotTransport = transport as ReadOnlyHouseholdSnapshotTransport;
    final status = await transport.inspect(bookId);
    if (!status.remoteInitializationComplete) {
      throw StateError('The shared household snapshot is not ready.');
    }
    final snapshot = await snapshotTransport.readHouseholdSnapshot(bookId);
    final result = <String, List<Map<String, Object?>>>{
      'household': [],
      'members': [],
      'accounts': [],
      'categories': [],
      'projects': [],
      'transactions': [],
      'transfer_links': [],
      'asset_definitions': [],
      'budgets': [],
      'transaction_import_rules': [],
      'manual_market_prices': [],
    };
    for (final entityType in initialSyncEntityOrder) {
      result[_backupKey(entityType)]!.addAll(snapshot[entityType] ?? const []);
    }
    return result;
  }

  static String _backupKey(String entityType) => switch (entityType) {
    'books' => 'household',
    'household_members' => 'members',
    'monthly_category_budgets' => 'budgets',
    _ => entityType,
  };
}
