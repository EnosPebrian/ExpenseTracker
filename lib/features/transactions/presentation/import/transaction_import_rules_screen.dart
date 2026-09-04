import 'package:flutter/material.dart';

import '../../../../core/database/local_store.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../data/local_transaction_import_rule_repository.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_import_rule.dart';
import '../../domain/services/transaction_import_rule_engine.dart';

Future<TransactionImportRule?> showTransactionImportRuleEditor(
  BuildContext context, {
  required String bookId,
  required List<Account> accounts,
  required Map<String, ImportRuleCategory> categories,
  TransactionImportRule? existing,
  TransactionImportRule? initial,
}) => showDialog<TransactionImportRule>(
  context: context,
  builder: (context) => _RuleEditor(
    bookId: bookId,
    existing: existing,
    initial: initial,
    accounts: accounts,
    categories: categories,
  ),
);

class TransactionImportRulesScreen extends StatefulWidget {
  const TransactionImportRulesScreen({
    super.key,
    required this.bookId,
    required this.accounts,
    this.store,
    this.initialRules,
    this.initialCategories,
  });

  final LocalStore? store;
  final String bookId;
  final List<Account> accounts;
  final List<TransactionImportRule>? initialRules;
  final Map<String, ImportRuleCategory>? initialCategories;

  static Future<void> show(
    BuildContext context, {
    required LocalStore store,
    required String bookId,
    required List<Account> accounts,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TransactionImportRulesScreen(
        store: store,
        bookId: bookId,
        accounts: accounts,
      ),
    ),
  );

  @override
  State<TransactionImportRulesScreen> createState() =>
      _TransactionImportRulesScreenState();
}

class _TransactionImportRulesScreenState
    extends State<TransactionImportRulesScreen> {
  late final repository = LocalTransactionImportRuleRepository(widget.store!);
  final testDescription = TextEditingController();
  final testReference = TextEditingController();
  final testMerchant = TextEditingController();
  List<TransactionImportRule> rules = const [];
  Map<String, ImportRuleCategory> categories = const {};
  bool loading = true;
  String? error;
  TransactionImportRuleType testType = TransactionImportRuleType.expense;
  String? testAccountId;

  @override
  void dispose() {
    testDescription.dispose();
    testReference.dispose();
    testMerchant.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialRules != null && widget.initialCategories != null) {
      rules = widget.initialRules!;
      categories = widget.initialCategories!;
      loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final rows = await widget.store!.getCategoryRecords(
        bookId: widget.bookId,
        includeDeleted: true,
      );
      final loaded = await repository.getAll(
        bookId: widget.bookId,
        includeDeleted: false,
      );
      if (!mounted) return;
      setState(() {
        categories = {
          for (final row in rows)
            row['id'] as String: ImportRuleCategory(
              id: row['id'] as String,
              bookId: row['book_id'] as String,
              name: row['name'] as String,
              type: row['category_type'] == 'income'
                  ? TransactionType.income
                  : TransactionType.expense,
              available: row['deleted_at'] == null,
            ),
        };
        rules = loaded;
        loading = false;
        error = null;
      });
    } catch (exception) {
      if (mounted) {
        setState(() {
          loading = false;
          error = exception.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Import rules')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: loading ? null : () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('New rule'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Rules suggest categories during CSV, receipt, and statement review. Manual choices always win.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _tester(),
              const SizedBox(height: 12),
              if (rules.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No import rules yet.'),
                  ),
                ),
              for (final rule in rules) _ruleTile(rule),
              const SizedBox(height: 80),
            ],
          ),
  );

  Widget _ruleTile(TransactionImportRule rule) {
    final category = categories[rule.categoryId];
    final accountMatches = widget.accounts.where(
      (item) => item.id == rule.accountId,
    );
    final account = accountMatches.isEmpty ? null : accountMatches.first;
    return Card(
      child: ListTile(
        title: Text(rule.name),
        subtitle: Text(
          '${rule.transactionType.name} · ${rule.matchField.name} ${rule.operator.name} “${rule.pattern}”\n'
          '${category?.name ?? 'Category unavailable'} · ${account?.name ?? (rule.accountId == null ? 'All accounts' : 'Account unavailable')} · priority ${rule.priority}',
        ),
        isThreeLine: true,
        leading: Switch(
          value: rule.enabled,
          onChanged: (value) async {
            await repository.setEnabled(rule, value);
            await _load();
          },
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') await _edit(rule);
            if (value == 'delete') {
              await repository.delete(rule);
              await _load();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Widget _tester() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Test rules', style: Theme.of(context).textTheme.titleMedium),
            DropdownButtonFormField<TransactionImportRuleType>(
              initialValue: testType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: TransactionImportRuleType.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => testType = value!),
            ),
            DropdownButtonFormField<String>(
              initialValue: testAccountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: widget.accounts
                  .where((account) => account.deletedAt == null)
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => testAccountId = value),
            ),
            TextField(
              controller: testDescription,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: testReference,
              decoration: const InputDecoration(labelText: 'Reference'),
            ),
            TextField(
              controller: testMerchant,
              decoration: const InputDecoration(labelText: 'Merchant hint'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                final accountId =
                    testAccountId ??
                    (widget.accounts.isEmpty ? '' : widget.accounts.first.id);
                final match = const TransactionImportRuleEngine().evaluate(
                  input: TransactionImportRuleInput(
                    bookId: widget.bookId,
                    type: testType == TransactionImportRuleType.expense
                        ? TransactionType.expense
                        : TransactionType.income,
                    accountId: accountId,
                    description: testDescription.text,
                    reference: testReference.text,
                    merchantHint: testMerchant.text,
                  ),
                  rules: rules,
                  categories: categories,
                  activeAccountIds: widget.accounts
                      .where((account) => account.deletedAt == null)
                      .map((account) => account.id)
                      .toSet(),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      match.ambiguous
                          ? 'Ambiguous: ${match.matchedRuleIds.length} rules match.'
                          : match.categoryName == null
                          ? 'No rules matched.'
                          : 'Matched: ${match.categoryName}',
                    ),
                  ),
                );
              },
              child: const Text('Test rules'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit([TransactionImportRule? existing]) async {
    final result = await showTransactionImportRuleEditor(
      context,
      bookId: widget.bookId,
      existing: existing,
      accounts: widget.accounts,
      categories: categories,
    );
    if (result == null) return;
    try {
      await repository.save(result);
      await _load();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    required this.bookId,
    required this.accounts,
    required this.categories,
    this.existing,
    this.initial,
  });
  final String bookId;
  final List<Account> accounts;
  final Map<String, ImportRuleCategory> categories;
  final TransactionImportRule? existing;
  final TransactionImportRule? initial;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  TransactionImportRule? get _value => widget.existing ?? widget.initial;
  late final name = TextEditingController(
    text: _value?.name ?? 'New import rule',
  );
  late final pattern = TextEditingController(text: _value?.pattern ?? '');
  late final priority = TextEditingController(
    text: '${_value?.priority ?? 100}',
  );
  late var type = _value?.transactionType ?? TransactionImportRuleType.expense;
  late var field =
      _value?.matchField ?? TransactionImportRuleMatchField.description;
  late var operator =
      _value?.operator ?? TransactionImportRuleOperator.contains;
  late String? accountId = _value?.accountId;
  late String? categoryId = _value?.categoryId;
  String? error;

  @override
  Widget build(BuildContext context) {
    final availableCategories = widget.categories.values
        .where(
          (category) => category.available && category.type.name == type.name,
        )
        .toList();
    if (categoryId != null &&
        !availableCategories.any((item) => item.id == categoryId)) {
      categoryId = null;
    }
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Create import rule' : 'Edit import rule',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Rule name'),
              ),
              DropdownButtonFormField(
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Transaction type',
                ),
                items: TransactionImportRuleType.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => type = value!),
              ),
              DropdownButtonFormField(
                initialValue: field,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Match field'),
                items: TransactionImportRuleMatchField.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => field = value!),
              ),
              DropdownButtonFormField(
                initialValue: operator,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Operator'),
                items: TransactionImportRuleOperator.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => operator = value!),
              ),
              TextField(
                controller: pattern,
                decoration: const InputDecoration(labelText: 'Pattern'),
              ),
              TextField(
                controller: priority,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Priority (higher wins)',
                ),
              ),
              DropdownButtonFormField<String?>(
                initialValue: accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account scope'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All accounts'),
                  ),
                  ...widget.accounts
                      .where((item) => item.deletedAt == null)
                      .map(
                        (item) => DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                ],
                onChanged: (value) => setState(() => accountId = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Suggested category',
                ),
                items: availableCategories
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => categoryId = value),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: () {
            try {
              if (categoryId == null) {
                throw const FormatException('Choose a category.');
              }
              final now = DateTime.now();
              Navigator.pop(
                context,
                TransactionImportRule(
                  id: widget.existing?.id,
                  bookId: widget.bookId,
                  name: name.text,
                  enabled: widget.existing?.enabled ?? true,
                  priority: int.parse(priority.text),
                  transactionType: type,
                  matchField: field,
                  operator: operator,
                  pattern: pattern.text,
                  accountId: accountId,
                  categoryId: categoryId!,
                  createdAt: widget.existing?.createdAt,
                  updatedAt: now,
                  version: (widget.existing?.version ?? 0) + 1,
                  deviceId: widget.existing?.deviceId ?? 'local-device',
                  syncStatus: 'pending',
                ),
              );
            } catch (exception) {
              setState(() => error = exception.toString());
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
