import '../../../core/database/local_store.dart';
import '../../backup/domain/backup_models.dart';
import '../../sync/domain/sync_models.dart';
import '../domain/health_check_models.dart';
import '../domain/health_check_service.dart';

class LocalHealthCheckDataSource implements HealthCheckDataSource {
  const LocalHealthCheckDataSource({
    required this.store,
    required this.bookId,
    required this.syncStatus,
    required this.lastSuccessfulSyncAt,
  });

  final LocalStore store;
  final String Function() bookId;
  final SyncStatus Function() syncStatus;
  final DateTime? Function() lastSuccessfulSyncAt;

  @override
  Future<HealthCheckSnapshot> load() async {
    final activeBookId = bookId();
    if (activeBookId.isEmpty) {
      throw StateError('No active household is available.');
    }
    final records = await store.createHouseholdBackupSnapshot(activeBookId);
    final sessions = await store.getImportReviewSessions(
      bookId: activeBookId,
      includeDeleted: true,
    );
    final drafts = await store.getAllImportReviewDrafts(
      bookId: activeBookId,
      includeDeleted: true,
    );
    final statusCounts = await store.getSyncOutboxStatusCounts(activeBookId);
    final pending = await store.getPendingSyncCount(activeBookId);
    final conflicts = await store.getUnresolvedSyncConflictCount(activeBookId);
    final session = await store.getLocalSession();
    final household = records['household']!.single;
    final linked = household['remote_linked_at'] != null;
    return HealthCheckSnapshot(
      schemaVersion: await store.getSchemaVersion(),
      expectedSchemaVersion: LocalStore.schemaVersion,
      bookId: activeBookId,
      backupFormatVersion: portableBackupFormatVersion,
      sync: HealthSyncSnapshot(
        cloudState: _cloudState(linked, syncStatus()),
        pendingOutboxCount: pending,
        failedOutboxCount:
            (statusCounts['retry'] ?? 0) + (statusCounts['conflict'] ?? 0),
        unresolvedConflictCount: conflicts,
        lastSuccessfulSyncAt: lastSuccessfulSyncAt(),
      ),
      localSession: session ?? const {},
      records: records,
      importSessions: sessions,
      importDrafts: drafts,
    );
  }

  static HealthCloudState _cloudState(bool linked, SyncStatus status) {
    if (!linked) return HealthCloudState.localOnly;
    return switch (status) {
      SyncStatus.synced => HealthCloudState.ready,
      SyncStatus.pending || SyncStatus.syncing => HealthCloudState.pending,
      SyncStatus.offline ||
      SyncStatus.retryScheduled => HealthCloudState.unavailable,
      SyncStatus.signedOut => HealthCloudState.signedOut,
      SyncStatus.notConfigured => HealthCloudState.notConfigured,
      SyncStatus.primaryUploadRequired ||
      SyncStatus.secondaryDownloadRequired ||
      SyncStatus.initializing => HealthCloudState.initializing,
      SyncStatus.initializationFailed ||
      SyncStatus.conflict ||
      SyncStatus.error => HealthCloudState.failed,
      SyncStatus.localOnly => HealthCloudState.localOnly,
    };
  }
}
