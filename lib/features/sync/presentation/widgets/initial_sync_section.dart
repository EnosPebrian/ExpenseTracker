import 'package:flutter/material.dart';

import '../../domain/sync_models.dart';
import '../controllers/initial_sync_controller.dart';

class InitialSyncSection extends StatefulWidget {
  const InitialSyncSection({super.key, required this.controller});

  final InitialSyncController controller;

  @override
  State<InitialSyncSection> createState() => _InitialSyncSectionState();
}

class _InitialSyncSectionState extends State<InitialSyncSection> {
  bool confirmedPrimary = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final primaryState = controller.primaryCursor?.initializationState;
        final secondaryState = controller.secondaryCursor?.initializationState;
        final showPrimary =
            controller.primaryBook?.remoteLinkedAt != null &&
            primaryState != SyncInitializationState.ready;
        final showSecondary =
            controller.secondaryBookId != null &&
            secondaryState != SyncInitializationState.ready;
        if (!showPrimary && !showSecondary) return const SizedBox.shrink();
        return Material(
          key: const Key('initial-sync-section'),
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Initial Synchronization',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (showPrimary) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'This device contains the household’s existing financial history.\n\n'
                    'Upload it as the initial shared household data.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Remote household: '
                    '${controller.primaryRemoteManifest?.bookName ?? controller.primaryBook?.name ?? 'Linked household'}',
                  ),
                  Text(
                    'Remote financial records: '
                    '${controller.primaryRemoteManifest?.remoteRecordCount ?? 0}',
                  ),
                  if (controller.primaryCursor?.manifest case final manifest?)
                    Text('Local snapshot records: ${_total(manifest)}'),
                  CheckboxListTile(
                    key: const Key('initial-upload-confirmation'),
                    contentPadding: EdgeInsets.zero,
                    value: confirmedPrimary,
                    onChanged: controller.busy
                        ? null
                        : (value) =>
                              setState(() => confirmedPrimary = value ?? false),
                    title: const Text(
                      'I confirm this device contains the primary household records.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  _ProgressLine(
                    label: 'Uploaded',
                    value: controller.uploadedCount,
                    total: controller.primaryCursor?.manifest == null
                        ? null
                        : _total(controller.primaryCursor!.manifest!),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        key: const Key('initial-upload-button'),
                        onPressed:
                            controller.canUpload &&
                                confirmedPrimary &&
                                !controller.busy
                            ? () => controller.upload(confirmed: true)
                            : null,
                        child: Text(
                          primaryState == SyncInitializationState.failed
                              ? 'Resume upload'
                              : 'Upload primary data',
                        ),
                      ),
                      if (_canCancel(primaryState))
                        TextButton(
                          key: const Key('initial-upload-cancel'),
                          onPressed: controller.busy
                              ? null
                              : () => controller.cancel(
                                  controller.primaryBook!.id,
                                ),
                          child: const Text('Cancel'),
                        ),
                    ],
                  ),
                ],
                if (showSecondary) ...[
                  if (showPrimary) const Divider(height: 24),
                  const SizedBox(height: 8),
                  const Text(
                    'Download the existing shared household to this device.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Household: '
                    '${controller.secondaryRemoteManifest?.bookName ?? 'Shared household'}',
                  ),
                  Text('Member role: ${controller.secondaryRole ?? 'member'}'),
                  Text(
                    'Remote snapshot records: '
                    '${controller.secondaryRemoteManifest?.totalCount ?? 0}',
                  ),
                  const Text(
                    'Initial download does not merge independent local financial history.',
                    key: Key('initial-download-non-merge-warning'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  _ProgressLine(
                    label: 'Downloaded',
                    value: controller.downloadedCount,
                    total: controller.secondaryRemoteManifest?.totalCount,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        key: const Key('initial-download-button'),
                        onPressed: controller.canDownload && !controller.busy
                            ? controller.download
                            : null,
                        child: Text(
                          secondaryState == SyncInitializationState.failed
                              ? 'Resume download'
                              : 'Download shared household',
                        ),
                      ),
                      if (_canCancel(secondaryState))
                        TextButton(
                          key: const Key('initial-download-cancel'),
                          onPressed: controller.busy
                              ? null
                              : () => controller.cancel(
                                  controller.secondaryBookId!,
                                ),
                          child: const Text('Cancel'),
                        ),
                    ],
                  ),
                ],
                if (controller.busy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(
                    key: Key('initial-sync-progress'),
                  ),
                ],
                if (controller.error case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    key: const Key('initial-sync-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static int _total(Map<String, Object?> manifest) {
    final counts = manifest['counts'];
    if (counts is! Map) return 0;
    return counts.values.fold<int>(
      0,
      (total, value) => total + (value as num).toInt(),
    );
  }

  static bool _canCancel(SyncInitializationState? state) =>
      state == SyncInitializationState.uploading ||
      state == SyncInitializationState.downloading ||
      state == SyncInitializationState.failed;
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.label, required this.value, this.total});

  final String label;
  final int value;
  final int? total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text('$label: $value${total == null ? '' : ' / $total'}'),
  );
}
