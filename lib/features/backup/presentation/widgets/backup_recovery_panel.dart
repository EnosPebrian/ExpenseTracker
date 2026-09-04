import 'package:flutter/material.dart';

import '../../domain/backup_recovery_models.dart';
import '../controllers/backup_recovery_controller.dart';

class BackupRecoveryPanel extends StatefulWidget {
  const BackupRecoveryPanel({super.key, required this.controller});

  final BackupRecoveryController controller;

  @override
  State<BackupRecoveryPanel> createState() => _BackupRecoveryPanelState();
}

class _BackupRecoveryPanelState extends State<BackupRecoveryPanel> {
  final password = TextEditingController();
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    password.dispose();
    search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final preview = controller.preview;
    final result = controller.result;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recover missing records',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Add missing records from a Pilgrim backup without replacing '
              'this household or disconnecting cloud sharing.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.busy ? null : controller.pickBackup,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Select .ptbackup'),
                ),
                if (controller.selectedFileName != null)
                  Text(controller.selectedFileName!),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Backup password',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed:
                      controller.busy || controller.selectedFileName == null
                      ? null
                      : () => controller.analyze(password.text),
                  child: Text(controller.busy ? 'Analyzing…' : 'Analyze'),
                ),
              ],
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 10),
              Text(
                controller.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (preview != null) ...[
              const Divider(height: 32),
              _Summary(preview: preview),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: search,
                      onChanged: controller.setSearch,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search recovered records',
                      ),
                    ),
                  ),
                  DropdownButton<BackupRecoveryFilter>(
                    value: controller.filter,
                    onChanged: (value) {
                      if (value != null) controller.setFilter(value);
                    },
                    items: [
                      for (final value in BackupRecoveryFilter.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_filterLabel(value)),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: controller.visibleCandidates.length,
                  itemBuilder: (context, index) {
                    final candidate = controller.visibleCandidates[index];
                    return _CandidateTile(
                      candidate: candidate,
                      selected: controller.selectedKeys.contains(candidate.key),
                      onChanged: (value) =>
                          controller.toggle(candidate.key, value ?? false),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        preview.canRecover &&
                            controller.selectedKeys.isNotEmpty &&
                            !controller.busy
                        ? _confirmRecovery
                        : null,
                    icon: const Icon(Icons.restore_page_outlined),
                    label: Text(
                      'Recover selected (${controller.selectedKeys.length})',
                    ),
                  ),
                  TextButton(
                    onPressed: controller.busy ? null : controller.clear,
                    child: const Text('Cancel recovery'),
                  ),
                ],
              ),
            ],
            if (result != null) ...[
              const Divider(height: 32),
              Text(
                'Recovery completed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Recovered ${result.recoveredByEntity.values.fold<int>(0, (a, b) => a + b)} records. '
                'Already present: ${result.skippedAlreadyPresent}. '
                'Pending sync: ${result.pendingCount}.',
              ),
              for (final entry in result.recoveredByEntity.entries)
                Text('${entry.key}: ${entry.value} recovered'),
              Text('Possible duplicates skipped: ${result.skippedDuplicates}'),
              Text('Conflicts kept current: ${result.conflictsKeptCurrent}'),
              Text('Blocked: ${result.blocked}'),
              Text('Completed: ${result.completedAt.toLocal()}'),
              if (preview?.cloudState.linked == true)
                const Text('Recovered records will synchronize normally.'),
              Wrap(
                spacing: 10,
                children: [
                  if ((result.recoveredByEntity['transactions'] ?? 0) > 0 &&
                      controller.onViewTransactions != null)
                    TextButton(
                      onPressed: controller.onViewTransactions,
                      child: const Text('View recovered transactions'),
                    ),
                  TextButton(
                    onPressed: controller.clear,
                    child: const Text('Recover another backup'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _filterLabel(BackupRecoveryFilter filter) => switch (filter) {
    BackupRecoveryFilter.all => 'All',
    BackupRecoveryFilter.recoverable => 'Recoverable',
    BackupRecoveryFilter.duplicate => 'Duplicate',
    BackupRecoveryFilter.conflict => 'Conflict',
    BackupRecoveryFilter.blocked => 'Blocked',
  };

  Future<void> _confirmRecovery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recover selected records?'),
        content: Text(
          '${widget.controller.selectedKeys.length} selected records and '
          'required dependencies will be added. Existing records will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recover'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.recoverSelected();
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.preview});
  final BackupRecoveryPreview preview;

  @override
  Widget build(BuildContext context) {
    final values = <String, int>{
      'Already present': preview.count(BackupRecoveryClassification.identical),
      'Missing / recoverable': preview.count(
        BackupRecoveryClassification.missing,
      ),
      'Required dependencies': preview.count(
        BackupRecoveryClassification.recoverableDependency,
      ),
      'Possible duplicates':
          preview.count(BackupRecoveryClassification.semanticDuplicate) +
          preview.count(BackupRecoveryClassification.possibleDuplicate),
      'Changed / conflicting': preview.count(
        BackupRecoveryClassification.changedConflict,
      ),
      'Deleted from shared household': preview.count(
        BackupRecoveryClassification.remoteDeleted,
      ),
      'Blocked / unsupported':
          preview.count(BackupRecoveryClassification.invalidReference) +
          preview.count(BackupRecoveryClassification.unsupported),
    };
    final entityTypes =
        preview.candidates
            .map((candidate) => candidate.entityType)
            .toSet()
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${preview.backupHouseholdName} · backup v${preview.formatVersion}',
        ),
        Text('Created: ${preview.exportedAt.toLocal()}'),
        Text(
          'Current: ${preview.currentHouseholdName} · '
          '${preview.cloudState.linked ? 'shared household' : 'local only'}',
        ),
        if (preview.cloudState.linked)
          Text(
            preview.remoteVerified
                ? 'Shared household verified.'
                : 'Shared household verification required.',
          ),
        if (preview.blockingErrors.isNotEmpty)
          Text(
            preview.blockingErrors.join('\n'),
            style: const TextStyle(color: Colors.red),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final entry in values.entries)
              Text('${entry.key}: ${entry.value}'),
          ],
        ),
        const SizedBox(height: 8),
        for (final entityType in entityTypes)
          Text(
            '$entityType: '
            '${preview.candidates.where((item) => item.entityType == entityType && item.selectable).length} recoverable, '
            '${preview.candidates.where((item) => item.entityType == entityType && item.classification == BackupRecoveryClassification.identical).length} already present',
          ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });
  final BackupRecoveryCandidate candidate;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final title =
        candidate.record['title'] ??
        candidate.record['name'] ??
        candidate.record['display_name'] ??
        candidate.id;
    final amount = candidate.record['amount'];
    final date = candidate.record['transaction_date'];
    final account = candidate.record['account'];
    final category = candidate.record['category'];
    final member = candidate.record['entered_by_member_id'];
    return CheckboxListTile(
      dense: true,
      value: candidate.selectable ? selected : false,
      onChanged: candidate.selectable ? onChanged : null,
      title: Text('$title${amount == null ? '' : ' · $amount'}'),
      subtitle: Text(
        [
          candidate.entityType,
          candidate.classification.name,
          if (date != null) 'Date $date',
          if (account != null) 'Account $account',
          if (category != null) 'Category $category',
          if (member != null) 'Member $member',
          if (candidate.dependencies.isNotEmpty)
            'Requires ${candidate.dependencies.length} record(s)',
          if (candidate.reason != null) candidate.reason!,
        ].join(' · '),
      ),
    );
  }
}
