import 'package:flutter/material.dart';

import '../../domain/sync_models.dart';
import '../controllers/sync_conflict_controller.dart';

class ConflictReviewScreen extends StatefulWidget {
  const ConflictReviewScreen({super.key, required this.controller});
  final SyncConflictController controller;
  static Future<void> show(
    BuildContext context,
    SyncConflictController controller,
  ) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ConflictReviewScreen(controller: controller),
    ),
  );
  @override
  State<ConflictReviewScreen> createState() => _ConflictReviewScreenState();
}

class _ConflictReviewScreenState extends State<ConflictReviewScreen> {
  int index = 0;
  final choices = <String, bool>{};
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conflict review')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.conflicts.isEmpty) {
          return const Center(child: Text('No conflicts need review.'));
        }
        if (index >= controller.conflicts.length) {
          index = controller.conflicts.length - 1;
        }
        final conflict = controller.conflicts[index];
        final fields = conflict.changedLocalFields
            .where(
              (f) => !const {
                'id',
                'book_id',
                'created_at',
                'updated_at',
                'version',
                'device_id',
                'sync_status',
              }.contains(f),
            )
            .toList();
        final merged = {...?conflict.serverPayload};
        for (final field in fields) {
          if (choices[field] ?? false) {
            merged[field] = conflict.localPayload?[field];
          }
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${index + 1} of ${controller.count} conflicts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _title(conflict),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              'Occurred ${MaterialLocalizations.of(context).formatMediumDate(conflict.createdAt)}',
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(),
            for (final field in fields)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(field),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(
                              'Shared: ${_value(conflict.serverPayload?[field])}',
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(
                              'This device: ${_value(conflict.localPayload?[field])}',
                            ),
                          ),
                        ],
                        selected: {choices[field] ?? false},
                        onSelectionChanged: (value) =>
                            setState(() => choices[field] = value.single),
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: controller.resolvingId == null
                      ? () => _confirm(
                          conflict,
                          ConflictResolutionType.keepServer,
                        )
                      : null,
                  child: const Text('Keep shared version'),
                ),
                OutlinedButton(
                  onPressed: controller.resolvingId == null
                      ? () => _confirm(
                          conflict,
                          ConflictResolutionType.keepDevice,
                        )
                      : null,
                  child: const Text('Keep this device'),
                ),
                if (!{
                  SyncConflictType.linkedTransactionConflict,
                  SyncConflictType.assetTradeConflict,
                }.contains(conflict.conflictType))
                  FilledButton(
                    onPressed: controller.resolvingId == null
                        ? () => _confirm(
                            conflict,
                            ConflictResolutionType.manualMerge,
                            merged,
                          )
                        : null,
                    child: const Text('Merge manually'),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
  Future<void> _confirm(
    SyncConflict conflict,
    ConflictResolutionType type, [
    Map<String, Object?>? merged,
  ]) async {
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm financial conflict resolution'),
            content: const Text(
              'This creates the canonical shared version and cannot be undone automatically.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Resolve'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;
    await widget.controller.resolve(conflict, type, mergedPayload: merged);
    if (mounted) setState(() => choices.clear());
  }

  static String _title(SyncConflict c) =>
      '${_label(c.entityType)} conflict: ${c.localPayload?['title'] ?? c.localPayload?['name'] ?? c.localPayload?['display_name'] ?? c.entityId}';
  static String _label(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
  static String _value(Object? value) =>
      value == null ? 'None' : value.toString();
}
