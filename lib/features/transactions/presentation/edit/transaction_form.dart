import 'package:flutter/material.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../domain/entities/transaction.dart';

import 'transaction_form_fields.dart';

class TransactionFormOptions {
  const TransactionFormOptions({
    required this.accounts,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.projects,
    this.assets = const [],
  });

  final List<String> accounts;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final List<String> projects;
  final List<String> assets;
}

class TransactionForm extends StatefulWidget {
  const TransactionForm({
    super.key,
    required this.transaction,
    required this.options,
    required this.onSubmit,
  });

  final Transaction transaction;
  final TransactionFormOptions options;
  final Future<void> Function(Transaction) onSubmit;

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  late final TextEditingController amountController;
  late final TextEditingController descriptionController;
  late final TextEditingController quantityController;
  late final TextEditingController unitController;
  late final TextEditingController unitPriceController;
  late TransactionType type;
  late String account;
  late String destinationAccount;
  late String category;
  late String project;
  late DateTime date;
  late TimeOfDay time;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    final movement = transaction.account.split(' -> ');
    type = transaction.type;
    account = movement.first;
    destinationAccount = movement.length > 1
        ? movement.sublist(1).join(' -> ')
        : _firstDifferent(account);
    category = transaction.category;
    project = _projectName(transaction.projectId);
    date = transaction.date;
    time = TimeOfDay.fromDateTime(transaction.date);
    amountController = TextEditingController(text: money(transaction.amount));
    descriptionController = TextEditingController(text: transaction.title);
    quantityController = TextEditingController(
      text: transaction.quantity?.toString() ?? '',
    );
    unitController = TextEditingController(text: transaction.unit ?? '');
    unitPriceController = TextEditingController(
      text: transaction.unitPrice == null ? '' : money(transaction.unitPrice!),
    );
    _normalizeSelections();
  }

  List<String> get categories => type == TransactionType.income
      ? widget.options.incomeCategories
      : widget.options.expenseCategories;

  List<String> get movementOptions =>
      <String>{...widget.options.accounts, ...widget.options.assets}.toList();

  String _firstDifferent(String value) => movementOptions.firstWhere(
    (candidate) => candidate != value,
    orElse: () => value,
  );

  String _projectName(String? projectId) {
    if (projectId == null) return 'No project';
    return widget.options.projects.firstWhere(
      (name) => _projectId(name) == projectId,
      orElse: () => projectId,
    );
  }

  void _normalizeSelections() {
    final availableAccounts =
        type == TransactionType.transfer ||
            type == TransactionType.assetConversion
        ? movementOptions
        : widget.options.accounts;
    if (!availableAccounts.contains(account)) {
      account = availableAccounts.first;
    }
    if (!movementOptions.contains(destinationAccount) ||
        destinationAccount == account) {
      destinationAccount = _firstDifferent(account);
    }
    if ((type == TransactionType.expense || type == TransactionType.income) &&
        !categories.contains(category)) {
      category = categories.first;
    }
  }

  void _setType(TransactionType value) => setState(() {
    type = value;
    _normalizeSelections();
  });

  Future<void> _submit() async {
    final amount = int.tryParse(
      amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (amount == null || amount <= 0) {
      setState(() => error = 'Enter an amount greater than zero.');
      return;
    }
    if ((type == TransactionType.transfer ||
            type == TransactionType.assetConversion) &&
        account == destinationAccount) {
      setState(() => error = 'Choose different source and destination values.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final original = widget.transaction;
      await widget.onSubmit(
        original.copyWith(
          projectId: project == 'No project' ? null : _projectId(project),
          title: descriptionController.text.trim().isEmpty
              ? original.title
              : descriptionController.text.trim(),
          category: type == TransactionType.transfer
              ? 'Transfer'
              : type == TransactionType.assetConversion
              ? 'Asset conversion'
              : category,
          account:
              type == TransactionType.transfer ||
                  type == TransactionType.assetConversion
              ? '$account -> $destinationAccount'
              : account,
          date: DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ),
          amount: amount,
          type: type,
          quantity: type == TransactionType.assetConversion
              ? double.tryParse(quantityController.text)
              : null,
          unit: type == TransactionType.assetConversion
              ? unitController.text.trim()
              : null,
          unitPrice: type == TransactionType.assetConversion
              ? int.tryParse(
                  unitPriceController.text.replaceAll(RegExp(r'[^0-9]'), ''),
                )
              : null,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
    quantityController.dispose();
    unitController.dispose();
    unitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: const Text('Edit transaction'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TransactionFormFields(
                  type: type,
                  amountController: amountController,
                  descriptionController: descriptionController,
                  quantityController: quantityController,
                  unitController: unitController,
                  unitPriceController: unitPriceController,
                  account: account,
                  destinationAccount: destinationAccount,
                  category: category,
                  project: project,
                  date: date,
                  time: time,
                  accountOptions: _withCurrent(
                    widget.options.accounts,
                    account,
                  ),
                  assetOptions: widget.options.assets,
                  categoryOptions: _withCurrent(categories, category),
                  projectOptions: _withCurrent([
                    'No project',
                    ...widget.options.projects,
                  ], project),
                  onTypeChanged: _setType,
                  onAccountChanged: (value) => setState(() => account = value),
                  onDestinationChanged: (value) =>
                      setState(() => destinationAccount = value),
                  onCategoryChanged: (value) =>
                      setState(() => category = value),
                  onProjectChanged: (value) => setState(() => project = value),
                  onDateChanged: (value) => setState(() => date = value),
                  onTimeChanged: (value) => setState(() => time = value),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving ? null : _submit,
            child: Text(saving ? 'Saving...' : 'Save changes'),
          ),
        ],
      ),
    );
  }

  static List<String> _withCurrent(List<String> values, String current) => [
    if (!values.contains(current)) current,
    ...values,
  ];

  static String _projectId(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');
}
