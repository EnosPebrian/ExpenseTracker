import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_colors.dart';
import '../../domain/health_check_models.dart';
import '../controllers/health_check_controller.dart';

class HealthCheckScreen extends StatelessWidget {
  const HealthCheckScreen({
    super.key,
    required this.controller,
    this.onOpenConflicts,
    this.onOpenImportInbox,
    this.onOpenBackup,
    this.onOpenHousehold,
  });

  final HealthCheckController controller;
  final VoidCallback? onOpenConflicts;
  final VoidCallback? onOpenImportInbox;
  final VoidCallback? onOpenBackup;
  final VoidCallback? onOpenHousehold;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final report = controller.report;
        return ListView(
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 64),
          children: [
            const Text(
              'DATA & SYNC',
              style: TextStyle(
                color: Color(0xFF8D8A9B),
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Health Check',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF25232E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check local data structure, import relationships, sync state, and backup readiness without changing anything.',
              style: TextStyle(color: Color(0xFF8D8A9B), fontSize: 15),
            ),
            const SizedBox(height: 28),
            if (report == null) _InitialCard(controller: controller),
            if (report != null) ...[
              _OverallCard(report: report),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: controller.running ? null : controller.run,
                    icon: controller.running
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Run Again'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: report.privacySafeSummary()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Privacy-safe diagnostic summary copied.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy summary'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (final section in report.sections) ...[
                _SectionCard(section: section, action: _actionFor(section)),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Text(
                _checkedLabel(context, report.generatedAt),
                style: const TextStyle(color: Color(0xFF8D8A9B)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Health Check is read-only. It never repairs, synchronizes, or modifies your financial data.',
                style: TextStyle(color: Color(0xFF8D8A9B)),
              ),
            ],
          ],
        );
      },
    );
  }

  _SectionAction? _actionFor(HealthCheckSection section) =>
      switch (section.id) {
        'sync'
            when onOpenConflicts != null &&
                section.checks.any(
                  (item) =>
                      item.code == 'sync.unresolved_conflicts' &&
                      item.status == HealthCheckItemStatus.warning,
                ) =>
          _SectionAction('Review conflicts', onOpenConflicts!),
        'sync' when onOpenHousehold != null => _SectionAction(
          'Open sync settings',
          onOpenHousehold!,
        ),
        'import_inbox' when onOpenImportInbox != null => _SectionAction(
          'Open Import Inbox',
          onOpenImportInbox!,
        ),
        'backup' when onOpenBackup != null => _SectionAction(
          'Open Backup & Export',
          onOpenBackup!,
        ),
        _ => null,
      };

  static String _checkedLabel(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return 'Checked $date, $time';
  }
}

class _InitialCard extends StatelessWidget {
  const _InitialCard({required this.controller});
  final HealthCheckController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_outlined, size: 38, color: violet),
          const SizedBox(height: 18),
          Text(
            'Pilgrim Health Check',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Runs fast, local diagnostics. It does not contact the cloud or alter records.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: controller.running ? null : controller.run,
            icon: controller.running
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: const Text('Run Health Check'),
          ),
        ],
      ),
    ),
  );
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.report});
  final HealthCheckReport report;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (report.overallStatus) {
      HealthCheckOverallStatus.healthy => (
        'Healthy',
        const Color(0xFF198754),
        Icons.check_circle_outline,
      ),
      HealthCheckOverallStatus.attentionNeeded => (
        'Attention needed',
        const Color(0xFFB26A00),
        Icons.warning_amber_rounded,
      ),
      HealthCheckOverallStatus.critical => (
        'Critical',
        const Color(0xFFC43838),
        Icons.error_outline,
      ),
    };
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overall',
                  style: TextStyle(color: Color(0xFF777382)),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, this.action});
  final HealthCheckSection section;
  final _SectionAction? action;

  @override
  Widget build(BuildContext context) {
    final issues = section.checks
        .where(
          (item) =>
              item.status == HealthCheckItemStatus.warning ||
              item.status == HealthCheckItemStatus.error,
        )
        .length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: issues > 0,
        leading: _StatusIcon(status: section.status),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(issues == 0 ? 'No issues' : '$issues need attention'),
        children: [
          for (final item in section.checks)
            ListTile(
              leading: _StatusIcon(status: item.status, compact: true),
              title: Text(item.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.summary),
                  if (item.suggestedAction != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.suggestedAction!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    item.code,
                    style: const TextStyle(
                      color: Color(0xFF9A96A6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          if (action != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: TextButton(
                  onPressed: action!.callback,
                  child: Text(action!.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, this.compact = false});
  final HealthCheckItemStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      HealthCheckItemStatus.healthy => (
        Icons.check_circle_outline,
        const Color(0xFF198754),
      ),
      HealthCheckItemStatus.info => (
        Icons.info_outline,
        const Color(0xFF5B67A6),
      ),
      HealthCheckItemStatus.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFB26A00),
      ),
      HealthCheckItemStatus.error => (
        Icons.error_outline,
        const Color(0xFFC43838),
      ),
    };
    return Icon(icon, color: color, size: compact ? 21 : 28);
  }
}

class _SectionAction {
  const _SectionAction(this.label, this.callback);
  final String label;
  final VoidCallback callback;
}
