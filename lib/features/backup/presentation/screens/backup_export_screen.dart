import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../domain/backup_models.dart';
import '../controllers/backup_export_controller.dart';
import '../widgets/backup_destination_widgets.dart';

class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({super.key, required this.controller});

  final BackupExportController controller;

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  final _backupPassword = TextEditingController();
  final _backupConfirmation = TextEditingController();
  final _restorePassword = TextEditingController();
  final _safetyPassword = TextEditingController();
  final _replacementName = TextEditingController();
  RestoreMode _restoreMode = RestoreMode.newHousehold;
  CsvExportFilter _filter = const CsvExportFilter();
  bool _remapCollision = false;
  bool _confirmBackupWarning = false;
  bool _confirmCsvWarning = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _backupPassword.addListener(_changed);
    _backupConfirmation.addListener(_changed);
    _safetyPassword.addListener(_changed);
    _replacementName.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant BackupExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _backupPassword.removeListener(_changed);
    _backupConfirmation.removeListener(_changed);
    _safetyPassword.removeListener(_changed);
    _replacementName.removeListener(_changed);
    _backupPassword.dispose();
    _backupConfirmation.dispose();
    _restorePassword.dispose();
    _safetyPassword.dispose();
    _replacementName.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FC),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(40, 44, 40, 80),
            children: [
              Text(
                'HOUSEHOLD DATA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: const Color(0xFF9292A4),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Backup & Export',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create an encrypted recovery file, restore safely, or export '
                'human-readable CSV files.',
                style: TextStyle(color: Color(0xFF8C8C9E)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use cloud download for a normal device change. Use an encrypted '
                'backup when cloud recovery is unavailable or when restoring an '
                'earlier snapshot.',
              ),
              const SizedBox(height: 28),
              if (controller.message != null) _Notice(controller.message!),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 950;
                  final children = [
                    Expanded(child: _backupCard()),
                    Expanded(child: _restoreCard()),
                  ];
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            children[0],
                            const SizedBox(width: 20),
                            children[1],
                          ],
                        )
                      : Column(
                          children: [
                            _backupCard(),
                            const SizedBox(height: 20),
                            _restoreCard(),
                          ],
                        );
                },
              ),
              const SizedBox(height: 20),
              _csvCard(),
            ],
          ),
          if (controller.busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator(color: violet)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _backupCard() {
    final snapshot = widget.controller.snapshot;
    final household = snapshot?['household']?.single;
    final count =
        snapshot?.values.fold<int>(
          0,
          (total, records) => total + records.length,
        ) ??
        0;
    return _SectionCard(
      title: 'Encrypted household backup',
      subtitle: 'Portable disaster recovery for one household.',
      children: [
        Text('${household?['name'] ?? 'Active household'} · $count records'),
        const Text('Export time is recorded when the snapshot is created.'),
        const SizedBox(height: 12),
        BackupDestinationChooser(
          guidance: 'Choose where this encrypted backup will be saved.',
          destination: widget.controller.backupDestination,
          fileName: widget.controller.backupFileName,
          enabled: !widget.controller.busy,
          onChoose: widget.controller.chooseBackupDestination,
        ),
        const SizedBox(height: 16),
        _PasswordField(controller: _backupPassword, label: 'Backup password'),
        const SizedBox(height: 12),
        _PasswordField(
          controller: _backupConfirmation,
          label: 'Confirm backup password',
        ),
        const SizedBox(height: 12),
        const Text(
          'Keep this password somewhere safe. It cannot be recovered, and a '
          'forgotten password makes the backup unusable.',
          style: TextStyle(color: Color(0xFF8C5A18)),
        ),
        if (widget.controller.hasReferenceWarnings)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmBackupWarning,
            onChanged: (value) =>
                setState(() => _confirmBackupWarning = value ?? false),
            title: const Text(
              'I understand that historical category references will be preserved.',
            ),
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed:
              widget.controller.canCreateBackup(
                password: _backupPassword.text,
                confirmation: _backupConfirmation.text,
                confirmWarnings: _confirmBackupWarning,
              )
              ? () => widget.controller.createEncryptedBackup(
                  password: _backupPassword.text,
                  confirmation: _backupConfirmation.text,
                  confirmWarnings: _confirmBackupWarning,
                )
              : null,
          icon: widget.controller.activeAction == BackupAction.backup
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_outline),
          label: Text(
            widget.controller.activeAction == BackupAction.backup
                ? 'Creating backup…'
                : 'Create encrypted backup',
          ),
        ),
        if (widget.controller.backupNotice != null) ...[
          const SizedBox(height: 10),
          _Notice(
            widget.controller.backupNotice!,
            error: widget.controller.error != null,
          ),
        ],
        if (widget.controller.backupResult case final result?) ...[
          const SizedBox(height: 12),
          BackupCompletionPanel(
            title: 'Backup created successfully',
            result: result,
            countLabel: 'Records',
            count: widget.controller.backupRecordCount,
            timeLabel: 'Created',
            onOpenFolder: widget.controller.openBackupFolder,
            onCopyPath: widget.controller.copyBackupPath,
          ),
        ],
      ],
    );
  }

  Widget _restoreCard() {
    final backup = widget.controller.validatedBackup;
    final blockingReason = backup == null
        ? null
        : widget.controller.restoreBlockingReason(
            mode: _restoreMode,
            safetyBackupPassword: _safetyPassword.text,
            confirmedHouseholdName: _replacementName.text,
            remapOnCollision: _remapCollision,
          );
    return _SectionCard(
      title: 'Restore backup',
      subtitle: 'Validates integrity before changing local data.',
      children: [
        OutlinedButton.icon(
          onPressed: widget.controller.busy
              ? null
              : widget.controller.pickBackup,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(
            widget.controller.selectedBackupName ?? 'Select .ptbackup',
          ),
        ),
        if (widget.controller.restoreNotice != null) ...[
          const SizedBox(height: 10),
          _Notice(
            widget.controller.restoreNotice!,
            error: widget.controller.error != null,
          ),
        ],
        const SizedBox(height: 12),
        _PasswordField(controller: _restorePassword, label: 'Backup password'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: widget.controller.busy
              ? null
              : () => widget.controller.validateSelectedBackup(
                  _restorePassword.text,
                  mode: _restoreMode,
                  remapOnCollision: _remapCollision,
                ),
          child: const Text('Validate and preview'),
        ),
        if (backup != null) ...[
          const Divider(height: 32),
          Text(
            backup.manifest.bookName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          Text(
            '${backup.manifest.baseCurrencyCode} · exported '
            '${_dateLabel(backup.manifest.exportedAt)} · '
            '${backup.manifest.entityCounts['transactions'] ?? 0} transactions',
          ),
          Text(
            'Backup format ${backup.manifest.formatVersion} · database schema '
            '${backup.manifest.databaseSchemaVersion}',
          ),
          if (widget.controller.restorePreview case final preview?) ...[
            const SizedBox(height: 12),
            RestorePreviewPanel(preview: preview),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<RestoreMode>(
            initialValue: _restoreMode,
            decoration: const InputDecoration(labelText: 'Restore mode'),
            items: const [
              DropdownMenuItem(
                value: RestoreMode.newHousehold,
                child: Text('Restore as a new local household'),
              ),
              DropdownMenuItem(
                value: RestoreMode.replaceMatchingHousehold,
                child: Text('Replace matching active household (advanced)'),
              ),
            ],
            onChanged: widget.controller.busy
                ? null
                : (value) {
                    setState(() => _restoreMode = value!);
                    widget.controller.previewValidatedBackup(
                      mode: _restoreMode,
                      remapOnCollision: _remapCollision,
                    );
                  },
          ),
          const SizedBox(height: 12),
          if (_restoreMode == RestoreMode.newHousehold)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remapCollision,
              title: const Text('Restore a remapped copy if this ID exists'),
              subtitle: const Text('Never merges independent histories.'),
              onChanged: widget.controller.busy
                  ? null
                  : (value) {
                      setState(() => _remapCollision = value!);
                      widget.controller.previewValidatedBackup(
                        mode: _restoreMode,
                        remapOnCollision: _remapCollision,
                      );
                    },
            )
          else ...[
            const Text(
              'Before replacing this household, Pilgrim Tracker creates a '
              'safety backup of the current local data.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _replacementName,
              decoration: InputDecoration(
                labelText: 'Type “${backup.manifest.bookName}” to confirm',
              ),
            ),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _safetyPassword,
              label: 'Password for required safety backup',
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Restored data starts local-only. Cloud sharing must be relinked '
            'after verification.',
            style: TextStyle(color: Color(0xFF666677)),
          ),
          const SizedBox(height: 16),
          if (blockingReason != null) ...[
            Text(
              blockingReason,
              style: const TextStyle(color: Color(0xFFC5342D)),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            onPressed: widget.controller.busy || blockingReason != null
                ? null
                : () => widget.controller.restoreValidated(
                    mode: _restoreMode,
                    safetyBackupPassword: _safetyPassword.text,
                    confirmedHouseholdName: _replacementName.text,
                    remapOnCollision: _remapCollision,
                  ),
            icon: const Icon(Icons.restore),
            label: const Text('Restore validated backup'),
          ),
          if (widget.controller.restoreResult case final result?) ...[
            const SizedBox(height: 12),
            RestoreCompletionPanel(result: result),
          ],
        ],
      ],
    );
  }

  Widget _csvCard() {
    final snapshot = widget.controller.snapshot;
    final accounts = snapshot?['accounts'] ?? const [];
    final categories = snapshot?['categories'] ?? const [];
    final projects = snapshot?['projects'] ?? const [];
    final members = snapshot?['members'] ?? const [];
    return _SectionCard(
      title: 'CSV export',
      subtitle: 'UTF-8 ZIP for spreadsheets and review. This is not a backup.',
      children: [
        BackupDestinationChooser(
          guidance: 'Choose where the CSV ZIP will be saved.',
          destination: widget.controller.csvDestination,
          fileName: widget.controller.csvFileName,
          enabled: !widget.controller.busy,
          onChoose: widget.controller.chooseCsvDestination,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _DateFilter(
              label: 'From',
              value: _filter.startDate,
              onChanged: (date) => setState(
                () => _filter = _filter.copyWith(
                  startDate: date,
                  clearStartDate: date == null,
                ),
              ),
            ),
            _DateFilter(
              label: 'To',
              value: _filter.endDateInclusive,
              onChanged: (date) => setState(
                () => _filter = _filter.copyWith(
                  endDateInclusive: date,
                  clearEndDate: date == null,
                ),
              ),
            ),
            _RecordDropdown(
              label: 'Account',
              records: accounts,
              value: _filter.accountId,
              nameField: 'name',
              onChanged: (value) => setState(
                () => _filter = _filter.copyWith(
                  accountId: value,
                  clearAccount: value == null,
                ),
              ),
            ),
            _RecordDropdown(
              label: 'Category',
              records: categories,
              value: _filter.categoryId,
              nameField: 'name',
              onChanged: (value) => setState(
                () => _filter = _filter.copyWith(
                  categoryId: value,
                  clearCategory: value == null,
                ),
              ),
            ),
            _RecordDropdown(
              label: 'Project',
              records: projects,
              value: _filter.projectId,
              nameField: 'name',
              onChanged: (value) => setState(
                () => _filter = _filter.copyWith(
                  projectId: value,
                  clearProject: value == null,
                ),
              ),
            ),
            _RecordDropdown(
              label: 'Member',
              records: members,
              value: _filter.memberId,
              nameField: 'display_name',
              onChanged: (value) => setState(
                () => _filter = _filter.copyWith(
                  memberId: value,
                  clearMember: value == null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            for (final type in const ['income', 'expense', 'assetConversion'])
              FilterChip(
                label: Text(
                  type == 'assetConversion' ? 'Asset conversion' : type,
                ),
                selected: _filter.transactionTypes.contains(type),
                onSelected: (selected) {
                  final values = Set<String>.of(_filter.transactionTypes);
                  selected ? values.add(type) : values.remove(type);
                  setState(
                    () => _filter = _filter.copyWith(transactionTypes: values),
                  );
                },
              ),
            FilterChip(
              label: const Text('Include deleted'),
              selected: _filter.includeDeleted,
              onSelected: (value) => setState(
                () => _filter = _filter.copyWith(includeDeleted: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${widget.controller.estimateCsvCount(_filter)} transactions selected',
        ),
        if (widget.controller.hasReferenceWarnings)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmCsvWarning,
            onChanged: (value) =>
                setState(() => _confirmCsvWarning = value ?? false),
            title: const Text(
              'I understand that historical category references will be preserved.',
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              widget.controller.canExportCsv(
                confirmWarnings: _confirmCsvWarning,
              )
              ? () => widget.controller.exportCsv(
                  _filter,
                  confirmWarnings: _confirmCsvWarning,
                )
              : null,
          icon: widget.controller.activeAction == BackupAction.csv
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_view_outlined),
          label: Text(
            widget.controller.activeAction == BackupAction.csv
                ? 'Exporting CSV…'
                : 'Export CSV ZIP',
          ),
        ),
        if (widget.controller.csvNotice != null) ...[
          const SizedBox(height: 10),
          _Notice(
            widget.controller.csvNotice!,
            error: widget.controller.error != null,
          ),
        ],
        if (widget.controller.csvResult case final result?) ...[
          const SizedBox(height: 12),
          BackupCompletionPanel(
            title: 'CSV export created successfully',
            result: result,
            countLabel: 'Transactions',
            count: widget.controller.csvTransactionCount,
            timeLabel: 'Exported',
            onOpenFolder: widget.controller.openCsvFolder,
            onCopyPath: widget.controller.copyCsvPath,
          ),
        ],
      ],
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.toLocal().year.toString().padLeft(4, '0')}-'
      '${date.toLocal().month.toString().padLeft(2, '0')}-'
      '${date.toLocal().day.toString().padLeft(2, '0')}';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF8C8C9E))),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    decoration: InputDecoration(labelText: label),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFECE8) : const Color(0xFFE9F8F0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: error ? const Color(0xFFC5342D) : const Color(0xFF147A4D),
      ),
    ),
  );
}

class _DateFilter extends StatelessWidget {
  const _DateFilter({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: OutlinedButton.icon(
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          firstDate: DateTime(1900),
          lastDate: DateTime(2200),
          initialDate: value ?? DateTime.now(),
        );
        if (context.mounted && date != null) onChanged(date);
      },
      onLongPress: value == null ? null : () => onChanged(null),
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        value == null
            ? '$label: Any'
            : '$label: ${_BackupExportScreenState._dateLabel(value!)}',
      ),
    ),
  );
}

class _RecordDropdown extends StatelessWidget {
  const _RecordDropdown({
    required this.label,
    required this.records,
    required this.value,
    required this.nameField,
    required this.onChanged,
  });
  final String label;
  final List<Map<String, Object?>> records;
  final String? value;
  final String nameField;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All')),
        for (final record in records.where(
          (record) => record['deleted_at'] == null,
        ))
          DropdownMenuItem<String?>(
            value: record['id'] as String,
            child: Text(
              record[nameField] as String,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}
