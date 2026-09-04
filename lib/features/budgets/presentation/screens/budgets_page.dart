import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../domain/entities/monthly_category_budget.dart';
import '../../domain/services/monthly_budget_calculator.dart';
import '../controllers/monthly_budget_controller.dart';
import '../widgets/budget_copy_dialog.dart';

class BudgetsPage extends StatelessWidget {
  const BudgetsPage({
    super.key,
    required this.controller,
    required this.currencyCode,
  });

  final MonthlyBudgetController controller;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summary;
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'MONTHLY PLAN',
            title: 'Budgets',
            subtitle: 'Set household limits for expense categories.',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => controller.setMonth(
                  DateTime(
                    summary.monthStart.year,
                    summary.monthStart.month - 1,
                  ),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_monthName(summary.monthStart.month)} ${summary.monthStart.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => controller.setMonth(
                  DateTime(
                    summary.monthStart.year,
                    summary.monthStart.month + 1,
                  ),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => controller.setMonth(DateTime.now()),
                child: const Text('Current month'),
              ),
              OutlinedButton.icon(
                onPressed: controller.copying
                    ? null
                    : () => showBudgetCopyDialog(
                        context,
                        controller: controller,
                        currencyCode: currencyCode,
                      ),
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy budgets'),
              ),
              FilledButton.icon(
                onPressed: controller.activeCategoryNames.isEmpty
                    ? null
                    : () => _showEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('Add budget'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 28,
                runSpacing: 8,
                children: [
                  Text('${summary.categories.length} budgeted categories'),
                  Text(
                    'Planned: $currencyCode ${money(summary.totalLimitMinor)}',
                  ),
                  if (controller.lastCopyResult case final result?
                      when result.preview.targetMonth == summary.monthStart)
                    Text('Latest copy: ${result.copied} categories added'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TotalCard(
                label: 'Total budgeted',
                value: '$currencyCode ${money(summary.totalLimitMinor)}',
              ),
              _TotalCard(
                label: 'Total spent',
                value: '$currencyCode ${money(summary.budgetedSpendMinor)}',
              ),
              _TotalCard(
                label: 'Remaining',
                value: '$currencyCode ${money(summary.remainingMinor)}',
              ),
              _TotalCard(
                label: 'Overspent',
                value: '$currencyCode ${money(summary.overspentMinor)}',
              ),
              _TotalCard(
                label: 'Unbudgeted spend',
                value: '$currencyCode ${money(summary.unbudgetedSpendMinor)}',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (summary.categories.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No budgets for this month.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add a category budget to compare actual household spending with your plan.',
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: controller.activeCategoryNames.isEmpty
                          ? null
                          : () => _showEditor(context),
                      child: const Text('Add budget'),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final result in summary.categories) ...[
              _BudgetCard(
                result: result,
                currencyCode: currencyCode,
                categoryArchived: !controller.activeCategoryNames.containsKey(
                  result.budget.categoryId,
                ),
                onEdit: () => _showEditor(context, existing: result.budget),
                onDelete: () => _confirmDelete(context, result.budget),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context, {
    MonthlyCategoryBudget? existing,
  }) async {
    final choices = Map<String, String>.of(controller.activeCategoryNames);
    if (existing != null) {
      choices.putIfAbsent(
        existing.categoryId,
        () =>
            controller.categoryNames[existing.categoryId] ??
            'Archived category',
      );
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _BudgetEditorDialog(
        controller: controller,
        choices: choices,
        currencyCode: currencyCode,
        existing: existing,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    MonthlyCategoryBudget budget,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete budget?'),
        content: const Text('Spending records will not be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.delete(budget);
  }

  static String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

class _BudgetEditorDialog extends StatefulWidget {
  const _BudgetEditorDialog({
    required this.controller,
    required this.choices,
    required this.currencyCode,
    this.existing,
  });

  final MonthlyBudgetController controller;
  final Map<String, String> choices;
  final String currencyCode;
  final MonthlyCategoryBudget? existing;

  @override
  State<_BudgetEditorDialog> createState() => _BudgetEditorDialogState();
}

class _BudgetEditorDialogState extends State<_BudgetEditorDialog> {
  late String categoryId;
  late final TextEditingController amount;
  late final TextEditingController note;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    categoryId = widget.existing?.categoryId ?? widget.choices.keys.first;
    amount = TextEditingController(
      text: widget.existing == null ? '' : money(widget.existing!.limitMinor),
    );
    note = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Add monthly budget' : 'Edit monthly budget',
    ),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Expense category'),
              items: widget.choices.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: widget.existing == null
                  ? (value) => setState(() => categoryId = value!)
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsFormatter()],
              decoration: InputDecoration(
                labelText: 'Monthly limit',
                prefixText: '${widget.currencyCode} ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: submitting ? null : _save,
        child: Text(submitting ? 'Saving...' : 'Save'),
      ),
    ],
  );

  Future<void> _save() async {
    setState(() => submitting = true);
    final value =
        int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    try {
      await widget.controller.save(
        existing: widget.existing,
        categoryId: categoryId,
        limitMinor: value,
        note: note.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 245,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.result,
    required this.currencyCode,
    required this.categoryArchived,
    required this.onEdit,
    required this.onDelete,
  });
  final CategoryBudgetResult result;
  final String currencyCode;
  final bool categoryArchived;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final progress = result.usedRatio.clamp(0.0, 1.0).toDouble();
    final label = switch (result.threshold) {
      BudgetThreshold.onTrack =>
        result.spentMinor == 0 ? 'No spending' : 'On track',
      BudgetThreshold.nearLimit => 'Near limit',
      BudgetThreshold.overspent =>
        result.spentMinor == result.budget.limitMinor
            ? 'Limit reached'
            : 'Overspent',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.categoryName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (categoryArchived) const Text('Archived category'),
                    ],
                  ),
                ),
                Text(label),
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 10),
            Text(
              '$currencyCode ${money(result.spentMinor)} spent of $currencyCode ${money(result.budget.limitMinor)}',
            ),
            Text(
              result.overspentMinor == 0
                  ? '$currencyCode ${money(result.remainingMinor)} remaining'
                  : '$currencyCode ${money(result.overspentMinor)} over budget',
            ),
            if (result.budget.note case final note?) ...[
              const SizedBox(height: 6),
              Text(note),
            ],
          ],
        ),
      ),
    );
  }
}
