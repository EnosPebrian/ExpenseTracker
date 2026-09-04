import 'package:flutter/material.dart';

import '../../../master_data/domain/entities/account.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_import_rule.dart';
import '../../domain/import/transaction_import_models.dart';
import '../../domain/services/internal_transfer_matcher.dart';
import '../controllers/transaction_import_controller.dart';
import 'transaction_import_mapping_panel.dart';
import 'transaction_import_rules_screen.dart';

class TransactionImportScreen extends StatelessWidget {
  const TransactionImportScreen({
    super.key,
    required this.controller,
    required this.onViewImported,
    this.preparedSource = false,
    this.title = 'Import CSV',
    this.sourceSummary,
  });
  final TransactionImportController controller;
  final ValueChanged<List<String>> onViewImported;
  final bool preparedSource;
  final String title;
  final Widget? sourceSummary;

  static Future<void> show(
    BuildContext context, {
    required TransactionImportController controller,
    required ValueChanged<List<String>> onViewImported,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TransactionImportScreen(
        controller: controller,
        onViewImported: onViewImported,
      ),
    ),
  );

  static Future<void> showPrepared(
    BuildContext context, {
    required TransactionImportController controller,
    required String title,
    required Widget sourceSummary,
    required ValueChanged<List<String>> onViewImported,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TransactionImportScreen(
        controller: controller,
        onViewImported: onViewImported,
        preparedSource: true,
        title: title,
        sourceSummary: sourceSummary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          controller.preview == null ||
          controller.result != null ||
          controller.saved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Keep this import for later?'),
            content: const Text(
              'Save normalized drafts to the Import Inbox or discard this review.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Keep reviewing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('Save to inbox'),
              ),
            ],
          ),
        );
        if (!context.mounted || choice == null || choice == 'cancel') return;
        if (choice == 'save' && await controller.saveForLater() == null) return;
        if (choice == 'discard' && controller.reviewBundle != null) {
          await controller.discardSavedReview();
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Stack(
            children: [
              _body(context),
              if (controller.busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x33000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final result = controller.result;
    if (result != null) return _result(context, result);
    final preview = controller.preview;
    final source = controller.source;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (preparedSource) ...[
          ?sourceSummary,
          const SizedBox(height: 12),
          DropdownButtonFormField<Account>(
            initialValue: controller.destinationAccount,
            decoration: const InputDecoration(labelText: 'Destination account'),
            items: controller.accounts
                .where(
                  (account) =>
                      account.deletedAt == null &&
                      account.bookId == controller.activeBookId,
                )
                .map(
                  (account) => DropdownMenuItem(
                    value: account,
                    child: Text('${account.name} · ${account.currencyCode}'),
                  ),
                )
                .toList(),
            onChanged: controller.selectAccount,
          ),
          if (preview == null && source != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: controller.destinationAccount == null
                    ? null
                    : controller.analyze,
                child: const Text('Analyze review'),
              ),
            ),
            if (controller.destinationAccount == null) ...[
              const SizedBox(height: 8),
              const Text('Select destination account before importing.'),
            ],
          ],
        ] else ...[
          Text(
            'CSV transaction import',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Import transactions from a bank or spreadsheet CSV. Pilgrim previews '
            'the file, checks duplicates, and lets you review every row before saving.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<Account>(
            initialValue: controller.destinationAccount,
            decoration: const InputDecoration(labelText: 'Destination account'),
            items: controller.accounts
                .where(
                  (account) =>
                      account.deletedAt == null &&
                      account.bookId == controller.activeBookId,
                )
                .map(
                  (account) => DropdownMenuItem(
                    value: account,
                    child: Text('${account.name} · ${account.currencyCode}'),
                  ),
                )
                .toList(),
            onChanged: controller.selectAccount,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: controller.selectCsv,
              icon: const Icon(Icons.file_open),
              label: Text(
                controller.source == null ? 'Select CSV' : 'Choose another CSV',
              ),
            ),
          ),
        ],
        if (controller.error != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (!preparedSource && source != null) ...[
          const SizedBox(height: 20),
          Text(
            '${source.fileName} · ${source.rows.length} rows · '
            '${source.delimiter == ',' ? 'comma' : 'semicolon'} delimiter',
          ),
          const SizedBox(height: 12),
          SegmentedButton<CsvHeaderMode>(
            segments: const [
              ButtonSegment(
                value: CsvHeaderMode.firstRowHeaders,
                label: Text('First row is headers'),
              ),
              ButtonSegment(
                value: CsvHeaderMode.firstRowData,
                label: Text('First row is data'),
              ),
            ],
            selected: {source.headerMode},
            onSelectionChanged: (value) =>
                controller.changeHeaderMode(value.single),
          ),
          const SizedBox(height: 12),
          TransactionImportMappingPanel(
            key: ValueKey('${source.fileFingerprint}-${source.headerMode}'),
            headers: source.headers,
            initial: controller.mapping,
            onChanged: controller.setMapping,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: controller.mapping == null ? null : controller.analyze,
              child: const Text('Analyze CSV'),
            ),
          ),
        ],
        if (preview != null) ...[
          const SizedBox(height: 24),
          _preview(context, preview),
        ],
      ],
    );
  }

  Widget _preview(BuildContext context, TransactionImportPreview preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review before import',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (!preview.remoteFreshnessVerified)
          const Card(
            color: Color(0xFFFFF3D6),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Cloud refresh was unavailable. Duplicate analysis uses current local data only.',
              ),
            ),
          ),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _count(
              'New',
              preview.count(TransactionImportClassification.newRecord),
            ),
            _count(
              'Already imported',
              preview.count(TransactionImportClassification.alreadyImported),
            ),
            _count(
              'Duplicates',
              preview.count(TransactionImportClassification.semanticDuplicate) +
                  preview.count(
                    TransactionImportClassification.possibleDuplicate,
                  ),
            ),
            _count(
              'Invalid',
              preview.count(TransactionImportClassification.invalid),
            ),
            _count('Included', preview.readyCount),
            _count('Possible transfers', controller.transferMatches.length),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search review rows',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: controller.setReviewQuery,
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<TransactionImportClassification?>(
                initialValue: controller.reviewFilter,
                decoration: const InputDecoration(labelText: 'Classification'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All rows')),
                  ...TransactionImportClassification.values.map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  ),
                ],
                onChanged: controller.setReviewFilter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: controller.includeAllSafeNew,
              child: const Text('Include all ready'),
            ),
            OutlinedButton(
              onPressed: controller.excludeAll,
              child: const Text('Exclude all'),
            ),
            OutlinedButton(
              onPressed: controller.excludeAllDuplicates,
              child: const Text('Exclude duplicates'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Bulk category for selected rows',
                ),
                items:
                    {
                          ...controller.expenseCategories,
                          ...controller.incomeCategories,
                        }
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null && !controller.bulkAssignCategory(value)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select rows of one transaction type.'),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 460,
          child: ListView.builder(
            itemCount: controller.visibleDrafts.length,
            itemBuilder: (context, index) =>
                _draftCard(context, controller.visibleDrafts[index]),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: controller.importReviewRepository == null
                  ? null
                  : () async {
                      final saved = await controller.saveForLater();
                      if (saved != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Saved to Import Inbox.'),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.inbox_outlined),
              label: Text(controller.saved ? 'Saved' : 'Save for later'),
            ),
            FilledButton(
              onPressed: preview.readyCount == 0
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Import selected transactions?'),
                          content: Text(
                            '${preview.readyCount} selected entries will be saved. '
                            'Each confirmed transfer is committed atomically. '
                            'Excluded and duplicate rows will not be changed.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Import'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await controller.commit();
                      }
                    },
              child: Text('Import ${preview.readyCount} transactions'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _draftCard(BuildContext context, TransactionImportDraft draft) {
    final categoryChoices = draft.type == TransactionType.income
        ? controller.incomeCategories
        : controller.expenseCategories;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: controller.selectedDraftIds.contains(
                    draft.transactionId,
                  ),
                  onChanged: (value) => controller.toggleSelected(
                    draft.transactionId,
                    value ?? false,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Row ${draft.sourceRowNumber} · ${draft.description}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: draft.included,
                  onChanged: draft.canChangeInclusion
                      ? (value) => controller.toggleIncluded(
                          draft.transactionId,
                          value,
                        )
                      : null,
                ),
                IconButton(
                  tooltip: 'Edit draft',
                  onPressed: () => _edit(context, draft),
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
            Text(
              '${draft.type.name} · ${draft.amount} · '
              '${draft.date.year}-${draft.date.month.toString().padLeft(2, '0')}-'
              '${draft.date.day.toString().padLeft(2, '0')} · '
              '${draft.classification.name}',
            ),
            DropdownButton<String>(
              value:
                  categoryChoices.contains(draft.category) &&
                      draft.category.isNotEmpty
                  ? draft.category
                  : null,
              hint: const Text('Assign category'),
              items: categoryChoices
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.editDraft(draft.transactionId, category: value);
                }
              },
            ),
            Text(_categoryProvenance(draft)),
            if (controller.transferMatchFor(draft.transactionId)
                case final match?) ...[
              const SizedBox(height: 8),
              _transferSuggestion(context, draft, match),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (draft.category.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        controller.editDraft(draft.transactionId, category: ''),
                    child: const Text('Clear category'),
                  ),
                if (draft.category.isNotEmpty &&
                    controller.saveImportRule != null)
                  TextButton.icon(
                    onPressed: () => _createRule(context, draft),
                    icon: const Icon(Icons.rule),
                    label: const Text('Create rule'),
                  ),
              ],
            ),
            for (final issue in draft.issues)
              Text(
                issue.message,
                style: TextStyle(
                  color: issue.blocking
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xFF8A6A00),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _transferSuggestion(
    BuildContext context,
    TransactionImportDraft draft,
    InternalTransferMatch match,
  ) {
    final counterpart = match.counterpart ?? match.options.first.counterpart;
    final confirmed = controller.isTransferConfirmed(draft.transactionId);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EBFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            confirmed
                ? 'Internal transfer confirmed'
                : 'Possible internal transfer',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            '${draft.type == TransactionType.expense ? controller.destinationAccount!.name : counterpart.accountName}'
            ' → '
            '${draft.type == TransactionType.income ? controller.destinationAccount!.name : counterpart.accountName}',
          ),
          Text('${counterpart.currencyCode} ${counterpart.amount}'),
          for (final reason in match.options.first.reasons) Text('• $reason'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _reviewImportTransfer(context, draft, match),
                child: const Text('Review transfer'),
              ),
              if (match.classification ==
                  InternalTransferMatchClassification.ambiguous)
                TextButton(
                  onPressed: () =>
                      _chooseImportCounterpart(context, draft, match),
                  child: const Text('Choose counterpart'),
                ),
              TextButton(
                onPressed: () =>
                    controller.keepAsTransaction(draft.transactionId),
                child: const Text('Keep as transaction'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reviewImportTransfer(
    BuildContext context,
    TransactionImportDraft draft,
    InternalTransferMatch match,
  ) async {
    final counterpart = match.counterpart;
    if (counterpart == null) {
      await _chooseImportCounterpart(context, draft, match);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert these entries into an internal transfer?'),
        content: Text(
          'FROM\n'
          '${draft.type == TransactionType.expense ? controller.destinationAccount!.name : counterpart.accountName}\n'
          'TO\n'
          '${draft.type == TransactionType.income ? controller.destinationAccount!.name : counterpart.accountName}\n\n'
          'Internal transfers move money between your own accounts and are not '
          'counted as household income or expense.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep separate'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm transfer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.confirmTransfer(draft.transactionId);
    } else if (confirmed == false) {
      controller.keepAsTransaction(draft.transactionId);
    }
  }

  Future<void> _chooseImportCounterpart(
    BuildContext context,
    TransactionImportDraft draft,
    InternalTransferMatch match,
  ) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose counterpart'),
        children: [
          for (final option in match.options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.counterpart.id),
              child: Text(
                '${option.counterpart.accountName} · '
                '${option.counterpart.currencyCode} '
                '${option.counterpart.amount}',
              ),
            ),
        ],
      ),
    );
    if (chosen != null) {
      controller.confirmTransfer(draft.transactionId, counterpartId: chosen);
    }
  }

  String _categoryProvenance(TransactionImportDraft draft) {
    if (draft.ruleAmbiguous) {
      final matches = draft.matchedRuleIds
          .map(controller.ruleMatchSummary)
          .join('; ');
      return 'No category · conflicting rule suggestions: $matches';
    }
    return switch (draft.categorySource) {
      TransactionImportCategorySource.manual => 'Selected manually',
      TransactionImportCategorySource.source => 'From source category',
      TransactionImportCategorySource.rule =>
        'Suggested by rule “${controller.ruleName(draft.winningRuleId) ?? 'Unavailable rule'}”',
      TransactionImportCategorySource.unresolved => 'No category suggestion',
    };
  }

  Future<void> _createRule(
    BuildContext context,
    TransactionImportDraft draft,
  ) async {
    final categoryMatches = controller.availableRuleCategories.values.where(
      (category) =>
          category.available &&
          category.name == draft.category &&
          category.type == draft.type,
    );
    if (categoryMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected category is unavailable.')),
      );
      return;
    }
    final useMerchant = draft.merchantHint.trim().isNotEmpty;
    final pattern = useMerchant ? draft.merchantHint : draft.description;
    final proposedName = '${draft.category}: $pattern';
    final initial = TransactionImportRule(
      bookId: controller.activeBookId,
      name: proposedName.length <= 80
          ? proposedName
          : proposedName.substring(0, 80),
      priority: 100,
      transactionType: draft.type == TransactionType.expense
          ? TransactionImportRuleType.expense
          : TransactionImportRuleType.income,
      matchField: useMerchant
          ? TransactionImportRuleMatchField.merchantHint
          : TransactionImportRuleMatchField.description,
      operator: useMerchant
          ? TransactionImportRuleOperator.equals
          : TransactionImportRuleOperator.contains,
      pattern: pattern,
      categoryId: categoryMatches.first.id,
    );
    final rule = await showTransactionImportRuleEditor(
      context,
      bookId: controller.activeBookId,
      accounts: controller.accounts,
      categories: controller.availableRuleCategories,
      initial: initial,
    );
    if (rule == null || !context.mounted) return;
    try {
      await controller.createImportRule(rule);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Import rule created.')));
    } catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create rule: $exception')),
      );
    }
  }

  Future<void> _edit(BuildContext context, TransactionImportDraft draft) async {
    final description = TextEditingController(text: draft.description);
    final amount = TextEditingController(text: draft.amount.toString());
    final reference = TextEditingController(text: draft.reference);
    final note = TextEditingController(text: draft.note);
    var type = draft.type;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit row ${draft.sourceRowNumber}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minor-unit amount',
                  ),
                ),
                DropdownButtonFormField<TransactionType>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(
                      value: TransactionType.expense,
                      child: Text('Expense'),
                    ),
                    DropdownMenuItem(
                      value: TransactionType.income,
                      child: Text('Income'),
                    ),
                  ],
                  onChanged: (value) => setState(() => type = value ?? type),
                ),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Reference'),
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      controller.editDraft(
        draft.transactionId,
        description: description.text,
        amount: int.tryParse(amount.text) ?? 0,
        type: type,
        reference: reference.text,
        note: note.text,
      );
    }
    description.dispose();
    amount.dispose();
    reference.dispose();
    note.dispose();
  }

  Widget _result(BuildContext context, TransactionImportResult result) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Import complete',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        Text(
          'Imported ordinary transactions: '
          '${result.importedIds.length - result.convertedInternalTransfers}',
        ),
        Text(
          'Converted internal transfers: '
          '${result.convertedInternalTransfers}',
        ),
        Text('Already imported: ${result.alreadyImported}'),
        Text('Skipped duplicates: ${result.skippedDuplicates}'),
        Text('Excluded: ${result.excluded}'),
        Text('Income total: ${result.incomeTotal}'),
        Text('Expense total: ${result.expenseTotal}'),
        Text('Completed: ${result.completedAt.toLocal()}'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: () => onViewImported(
                result.viewTransactionIds.isEmpty
                    ? result.importedIds
                    : result.viewTransactionIds,
              ),
              child: const Text('View imported transactions'),
            ),
            OutlinedButton(
              onPressed: controller.reset,
              child: Text(
                preparedSource
                    ? 'Import another document'
                    : 'Import another CSV',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _count(String label, int value) => Chip(label: Text('$label: $value'));
}
