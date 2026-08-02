import 'package:flutter/material.dart';

import '../../domain/sync_models.dart';
import '../controllers/sync_controller.dart';

class SyncStatusSection extends StatelessWidget {
  const SyncStatusSection({
    super.key,
    required this.controller,
    this.onReviewConflicts,
  });

  final SyncController controller;
  final VoidCallback? onReviewConflicts;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Container(
        key: const Key('sync-status-section'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _label(controller.status, controller.pendingCount),
              key: const Key('sync-status-label'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (controller.status == SyncStatus.primaryUploadRequired) ...[
              const SizedBox(height: 4),
              const Text(
                'Financial synchronization needs initial setup. Existing '
                'records have not been uploaded.',
                key: Key('sync-initial-upload-warning'),
              ),
            ],
            if (controller.status == SyncStatus.secondaryDownloadRequired) ...[
              const SizedBox(height: 4),
              const Text(
                'Financial synchronization needs initial setup. Household '
                'records have not been downloaded.',
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Pending: ${controller.pendingCount} · Last successful: ${controller.lastSuccessfulSyncAt == null ? 'Not yet' : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(controller.lastSuccessfulSyncAt!))}',
            ),
            if (!controller.realtimeConnected && controller.canSync)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Realtime disconnected — normal sync still available',
                ),
              ),
            const SizedBox(height: 8),
            if (controller.status == SyncStatus.conflict &&
                onReviewConflicts != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: onReviewConflicts,
                  icon: const Icon(Icons.rule),
                  label: const Text('Review conflicts'),
                ),
              ),
            FilledButton.tonalIcon(
              key: const Key('sync-now-button'),
              onPressed: controller.canSync && !controller.busy
                  ? controller.syncNow
                  : null,
              icon: controller.busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(SyncStatus status, int pendingCount) => switch (status) {
    SyncStatus.localOnly => 'Local only',
    SyncStatus.notConfigured => 'Cloud not configured',
    SyncStatus.signedOut => 'Sign in required',
    SyncStatus.primaryUploadRequired => 'Initial upload required',
    SyncStatus.secondaryDownloadRequired => 'Initial download required',
    SyncStatus.initializing => 'Initial synchronization in progress',
    SyncStatus.initializationFailed => 'Initial synchronization needs retry',
    SyncStatus.synced => 'Synced',
    SyncStatus.pending => '$pendingCount changes waiting',
    SyncStatus.syncing => 'Syncing',
    SyncStatus.offline => 'Last sync failed — offline',
    SyncStatus.retryScheduled => 'Retry scheduled — $pendingCount waiting',
    SyncStatus.conflict => 'Conflict needs review',
    SyncStatus.error => 'Last sync failed',
  };
}
