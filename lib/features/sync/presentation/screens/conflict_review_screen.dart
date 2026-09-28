import 'package:flutter/material.dart';
import '../../domain/conflict_merge_policy.dart';
import '../../domain/sync_models.dart';
import '../controllers/sync_conflict_controller.dart';
import '../widgets/conflict_merge_dialog.dart';

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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.loading) const LinearProgressIndicator(),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!controller.loading && controller.conflicts.isEmpty)
              const Text('No conflicts need review.'),
            for (final conflict in controller.conflicts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${conflict.entityType.replaceAll('_', ' ')}: '
                        '${conflict.localPayload?['title'] ?? conflict.localPayload?['name'] ?? 'Saved record'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'This device and the shared household have different versions. '
                        'The conflict remains saved until the server and this device accept the resolution.',
                      ),
                      if (ConflictMergePolicy.coordinated(conflict))
                        const Text(
                          'Linked financial record: field-by-field merging is disabled.',
                        ),
                      if (controller.resolvingId == conflict.id)
                        const LinearProgressIndicator(),
                      if (conflict.resolutionIntent != null) ...[
                        const Text(
                          'A saved resolution is awaiting confirmation. Retry that same decision safely.',
                        ),
                        FilledButton(
                          onPressed: controller.resolvingId == null
                              ? () => controller.resolve(
                                  conflict,
                                  ConflictResolutionType.keepServer,
                                )
                              : null,
                          child: const Text('Retry saved resolution'),
                        ),
                      ] else
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
                              child: const Text('Keep cloud version'),
                            ),
                            OutlinedButton(
                              onPressed: controller.resolvingId == null
                                  ? () => _confirm(
                                      conflict,
                                      ConflictResolutionType.keepDevice,
                                    )
                                  : null,
                              child: const Text('Keep local version'),
                            ),
                            if (ConflictMergePolicy.fields(conflict).isNotEmpty)
                              FilledButton(
                                onPressed: controller.resolvingId == null
                                    ? () => showDialog<void>(
                                        context: context,
                                        builder: (_) => ConflictMergeDialog(
                                          conflict: conflict,
                                          controller: controller,
                                        ),
                                      )
                                    : null,
                                child: const Text('Merge manually'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _confirm(
    SyncConflict conflict,
    ConflictResolutionType type,
  ) async {
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm financial conflict resolution'),
            content: const Text(
              'Use this whole version as the shared record? Other pending changes are not discarded.',
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
    if (approved) await widget.controller.resolve(conflict, type);
  }
}
