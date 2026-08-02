import 'package:flutter/material.dart';

import '../../data/portable_file_service.dart';
import '../../domain/backup_models.dart';

class BackupDestinationChooser extends StatelessWidget {
  const BackupDestinationChooser({
    super.key,
    required this.guidance,
    required this.destination,
    required this.fileName,
    required this.enabled,
    required this.onChoose,
  });

  final String guidance;
  final PortableDestination? destination;
  final String fileName;
  final bool enabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(guidance),
      const SizedBox(height: 8),
      Text('Folder: ${destination?.displayValue ?? 'Not selected'}'),
      Tooltip(message: fileName, child: Text('File: $fileName')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: enabled ? onChoose : null,
        icon: const Icon(Icons.folder_outlined),
        label: Text(destination == null ? 'Choose folder' : 'Change folder'),
      ),
    ],
  );
}

class BackupCompletionPanel extends StatelessWidget {
  const BackupCompletionPanel({
    super.key,
    required this.title,
    required this.result,
    required this.countLabel,
    required this.count,
    required this.timeLabel,
    required this.onOpenFolder,
    required this.onCopyPath,
  });

  final String title;
  final PortableSaveResult result;
  final String countLabel;
  final int count;
  final String timeLabel;
  final Future<void> Function() onOpenFolder;
  final Future<void> Function() onCopyPath;

  @override
  Widget build(BuildContext context) {
    final local = result.completedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final timestamp =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF8F1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF9AD5B8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('File: ${result.fileName}'),
            Tooltip(
              message: result.destinationDisplayValue,
              child: Text(
                'Location: ${result.destinationDisplayValue}',
                softWrap: true,
              ),
            ),
            Text('$timeLabel: $timestamp'),
            Text('$countLabel: $count'),
            if (result.canOpenFolder || result.canCopyPath) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (result.canOpenFolder)
                    TextButton.icon(
                      onPressed: onOpenFolder,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Open folder'),
                    ),
                  if (result.canCopyPath)
                    TextButton.icon(
                      onPressed: onCopyPath,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy path'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RestorePreviewPanel extends StatelessWidget {
  const RestorePreviewPanel({super.key, required this.preview});

  final RestorePreview preview;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFD8D8E2)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Restore preview',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        if (preview.mode == RestoreMode.replaceMatchingHousehold) ...[
          Text('Records to replace: ${preview.recordsToReplace}'),
          Text('Records unchanged: ${preview.alreadyPresent}'),
          Text('New supporting records: ${preview.newRecords}'),
        ] else ...[
          Text('New records: ${preview.newRecords}'),
          Text('Already present: ${preview.alreadyPresent}'),
          Text('Blocking ID conflicts: ${preview.conflicts}'),
        ],
        Text('Invalid records: ${preview.invalidRecords}'),
        Text('Blocking integrity errors: ${preview.blockingErrors.length}'),
        Text('Expected final total: ${_total(preview.expectedFinalTotals)}'),
        if (preview.blockingReason case final reason?)
          Text(reason, style: TextStyle(color: Color(0xFFC5342D))),
      ],
    ),
  );
}

class RestoreCompletionPanel extends StatelessWidget {
  const RestoreCompletionPanel({super.key, required this.result});

  final RestoreResult result;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restore completed',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text('Records added: ${result.preview.newRecords}'),
          if (result.preview.mode == RestoreMode.replaceMatchingHousehold)
            Text('Records replaced: ${result.preview.recordsToReplace}'),
          Text('Already present/skipped: ${result.preview.alreadyPresent}'),
          Text(
            'Final database total: '
            '${_total(result.preview.expectedFinalTotals)}',
          ),
          Text('Completed: ${result.completedAt.toLocal()}'),
        ],
      ),
    ),
  );
}

int _total(Map<String, int> values) =>
    values.values.fold(0, (total, value) => total + value);
