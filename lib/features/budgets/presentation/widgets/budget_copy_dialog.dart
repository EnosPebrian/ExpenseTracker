import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../domain/services/monthly_budget_copy_service.dart';
import '../controllers/monthly_budget_controller.dart';

Future<void> showBudgetCopyDialog(
  BuildContext context, {
  required MonthlyBudgetController controller,
  required String currencyCode,
}) => showDialog<void>(
  context: context,
  barrierDismissible: !controller.copying,
  builder: (_) =>
      _BudgetCopyDialog(controller: controller, currencyCode: currencyCode),
);

class _BudgetCopyDialog extends StatefulWidget {
  const _BudgetCopyDialog({
    required this.controller,
    required this.currencyCode,
  });

  final MonthlyBudgetController controller;
  final String currencyCode;

  @override
  State<_BudgetCopyDialog> createState() => _BudgetCopyDialogState();
}

class _BudgetCopyDialogState extends State<_BudgetCopyDialog> {
  late DateTime sourceMonth;
  MonthlyBudgetCopyPreview? preview;
  MonthlyBudgetCopyResult? result;
  String? error;
  bool loading = true;
  bool submitting = false;

  DateTime get targetMonth => widget.controller.month;

  @override
  void initState() {
    super.initState();
    sourceMonth = DateTime(targetMonth.year, targetMonth.month - 1);
    _loadPreview();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Copy budgets'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copy budget limits and notes from another month. Spending is not copied.',
            ),
            const SizedBox(height: 16),
            Text('Target: ${_monthLabel(targetMonth)}'),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous source month',
                  onPressed: submitting ? null : () => _changeSource(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Source: ${_monthLabel(sourceMonth)}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Next source month',
                  onPressed: submitting ? null : () => _changeSource(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const Divider(),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error case final message?)
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (result case final completed?)
              _CopyCompletion(
                result: completed,
                currencyCode: widget.currencyCode,
              )
            else if (preview case final value?)
              _CopyPreview(preview: value, currencyCode: widget.currencyCode),
          ],
        ),
      ),
    ),
    actions: result != null
        ? [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ]
        : [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: preview == null || loading || submitting
                  ? null
                  : _copy,
              child: Text(submitting ? 'Copying...' : 'Copy'),
            ),
          ],
  );

  void _changeSource(int offset) {
    setState(() {
      sourceMonth = DateTime(sourceMonth.year, sourceMonth.month + offset);
      result = null;
    });
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      loading = true;
      preview = null;
      error = null;
    });
    try {
      final value = await widget.controller.previewCopy(sourceMonth);
      if (!mounted) return;
      setState(() {
        preview = value;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = _message(exception);
        loading = false;
      });
    }
  }

  Future<void> _copy() async {
    final value = preview;
    if (value == null || submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final completed = await widget.controller.copyBudgets(value);
      if (!mounted) return;
      setState(() {
        result = completed;
        submitting = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = _message(exception);
        submitting = false;
      });
    }
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('StateError: ', '');
}

class _CopyPreview extends StatelessWidget {
  const _CopyPreview({required this.preview, required this.currencyCode});

  final MonthlyBudgetCopyPreview preview;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          Text('To add: ${preview.budgetsToAdd}'),
          Text('Already present: ${preview.alreadyPresent}'),
          Text('Unavailable: ${preview.unavailableCategories}'),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Expected target plan: $currencyCode ${money(preview.expectedTargetTotalMinor)}',
      ),
      const SizedBox(height: 12),
      if (preview.rows.isEmpty)
        const Text('The source month has no active budgets to copy.')
      else
        for (final row in preview.rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row.categoryName),
            subtitle: Text(
              '$currencyCode ${money(row.sourceBudget.limitMinor)}',
            ),
            trailing: Text(_status(row.status)),
          ),
      if (preview.warnings.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final warning in preview.warnings)
          Text(warning, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );

  static String _status(MonthlyBudgetCopyRowStatus status) => switch (status) {
    MonthlyBudgetCopyRowStatus.willBeAdded => 'Will be added',
    MonthlyBudgetCopyRowStatus.alreadyPresent => 'Already present',
    MonthlyBudgetCopyRowStatus.categoryUnavailable => 'Category unavailable',
  };
}

class _CopyCompletion extends StatelessWidget {
  const _CopyCompletion({required this.result, required this.currencyCode});

  final MonthlyBudgetCopyResult result;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        result.copied == 0
            ? 'No budgets were copied.'
            : '${result.copied} budgets copied.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text('Already present: ${result.alreadyPresent}'),
      Text('Unavailable categories: ${result.unavailableCategories}'),
      Text('Target categories: ${result.finalTargetCount}'),
      Text(
        'Final planned amount: $currencyCode ${money(result.finalTargetTotalMinor)}',
      ),
    ],
  );
}

String _monthLabel(DateTime value) =>
    '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][value.month - 1]} ${value.year}';
