import 'package:flutter/material.dart';

import '../controllers/restore_lifecycle_controller.dart';

class RestoreLifecyclePanel extends StatelessWidget {
  const RestoreLifecyclePanel({
    super.key,
    required this.controller,
    required this.bookId,
    this.authenticatedEmail,
    this.onReconnect,
    this.onRecoverMissing,
  });

  final RestoreLifecycleController controller;
  final String bookId;
  final String? authenticatedEmail;
  final VoidCallback? onReconnect;
  final VoidCallback? onRecoverMissing;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final preview = controller.preview;
      if (preview == null || preview.sourceBookId != bookId) {
        return const SizedBox.shrink();
      }
      return Container(
        key: const Key('restore-lifecycle-panel'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Backup restored',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'This household is currently stored only on this device.',
            ),
            const SizedBox(height: 6),
            Text(
              '${preview.householdName} · ${preview.baseCurrencyCode} · '
              '${preview.recordCount} records',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('restore-keep-local'),
                  onPressed: controller.busy ? null : controller.keepLocalOnly,
                  child: const Text('Keep local only'),
                ),
                FilledButton(
                  key: const Key('restore-create-new-shared'),
                  onPressed: controller.busy || authenticatedEmail == null
                      ? null
                      : () => _showNewSharedPreview(context),
                  child: const Text('Create new shared household'),
                ),
                OutlinedButton(
                  key: const Key('restore-reconnect-existing'),
                  onPressed: controller.busy ? null : onReconnect,
                  child: const Text('Reconnect existing shared household'),
                ),
              ],
            ),
            if (authenticatedEmail == null) ...[
              const SizedBox(height: 8),
              const Text('Sign in before creating a new shared household.'),
            ],
            const SizedBox(height: 10),
            const Text(
              'Want to add only records missing from the shared household? '
              'Use Recover missing records instead.',
            ),
            if (onRecoverMissing != null)
              TextButton(
                key: const Key('restore-open-recovery'),
                onPressed: controller.busy ? null : onRecoverMissing,
                child: const Text('Recover missing records'),
              ),
            if (controller.message case final message?) ...[
              const SizedBox(height: 8),
              Text(message, key: const Key('restore-lifecycle-message')),
            ],
            if (controller.error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const Key('restore-lifecycle-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      );
    },
  );

  Future<void> _showNewSharedPreview(BuildContext context) async {
    final preview = controller.preview;
    final email = authenticatedEmail;
    if (preview == null || email == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NewSharedHouseholdDialog(
        initialName: preview.proposedName,
        restoredName: preview.householdName,
        currencyCode: preview.baseCurrencyCode,
        recordCount: preview.recordCount,
        ownerEmail: email,
      ),
    );
    if (name != null) await controller.createNewSharedHousehold(name);
  }
}

class _NewSharedHouseholdDialog extends StatefulWidget {
  const _NewSharedHouseholdDialog({
    required this.initialName,
    required this.restoredName,
    required this.currencyCode,
    required this.recordCount,
    required this.ownerEmail,
  });

  final String initialName;
  final String restoredName;
  final String currencyCode;
  final int recordCount;
  final String ownerEmail;

  @override
  State<_NewSharedHouseholdDialog> createState() =>
      _NewSharedHouseholdDialogState();
}

class _NewSharedHouseholdDialogState extends State<_NewSharedHouseholdDialog> {
  late final TextEditingController name = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('restore-new-shared-preview'),
    title: const Text('Create new shared household'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restored household',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(widget.restoredName),
            Text('${widget.currencyCode} · ${widget.recordCount} records'),
            const Divider(height: 28),
            const Text(
              'New shared household',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextField(
              key: const Key('restore-new-shared-name'),
              controller: name,
              decoration: const InputDecoration(labelText: 'Household name'),
            ),
            const SizedBox(height: 8),
            Text('Owner: ${widget.ownerEmail}'),
            Text('Base currency: ${widget.currencyCode}'),
            const SizedBox(height: 12),
            const Text(
              'This creates a separate shared household. It does not modify '
              'your existing hosted household.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('restore-confirm-new-shared'),
        onPressed: name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, name.text.trim()),
        child: const Text('Create and upload'),
      ),
    ],
  );
}
