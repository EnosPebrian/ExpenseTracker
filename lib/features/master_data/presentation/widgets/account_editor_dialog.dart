import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/household_member.dart';
import '../../domain/services/account_balance_calculator.dart';

class AccountEditorDialog extends StatefulWidget {
  const AccountEditorDialog({
    super.key,
    required this.account,
    required this.defaultCurrencyCode,
    required this.transactions,
    required this.members,
    required this.onSave,
  });

  final Account? account;
  final String defaultCurrencyCode;
  final List<Transaction> transactions;
  final List<HouseholdMember> members;
  final Future<void> Function(Account account) onSave;

  static Future<void> show(
    BuildContext context, {
    Account? account,
    required String defaultCurrencyCode,
    required List<Transaction> transactions,
    List<HouseholdMember> members = const [],
    required Future<void> Function(Account account) onSave,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AccountEditorDialog(
        account: account,
        defaultCurrencyCode: defaultCurrencyCode,
        transactions: transactions,
        members: members,
        onSave: onSave,
      ),
    );
  }

  @override
  State<AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<AccountEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _currencyController;
  late final TextEditingController _balanceController;
  late AccountType _type;
  String? _ownerMemberId;
  late bool _openingEnabled;
  DateTime? _openingDate;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _nameController = TextEditingController(text: account?.name ?? '');
    _currencyController = TextEditingController(
      text: account?.currencyCode ?? widget.defaultCurrencyCode,
    );
    _balanceController = TextEditingController(
      text: account?.openingBalance.toString() ?? '0',
    );
    _type = account?.accountType ?? AccountType.bank;
    _ownerMemberId = account?.ownerMemberId;
    _openingEnabled = account?.hasOpeningBalance ?? false;
    _openingDate = account?.openingBalanceDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _openingDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) setState(() => _openingDate = selected);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final currency = _currencyController.text.trim().toUpperCase();
    final amount = int.tryParse(
      _balanceController.text.replaceAll('.', '').replaceAll(',', ''),
    );
    if (name.isEmpty) {
      setState(() => _error = 'Account name is required.');
      return;
    }
    if (currency.isEmpty) {
      setState(() => _error = 'Currency is required.');
      return;
    }
    if (_openingEnabled && amount == null) {
      setState(() => _error = 'Enter a valid starting balance.');
      return;
    }
    if (_openingEnabled && _openingDate == null) {
      setState(() => _error = 'Balance effective date is required.');
      return;
    }

    final base = widget.account;
    final account = (base ?? Account(name: name)).copyWith(
      name: name,
      accountType: _type,
      ownerMemberId: _ownerMemberId,
      currencyCode: currency,
      openingBalance: _openingEnabled ? amount! : 0,
      openingBalanceDate: _openingEnabled ? _openingDate : null,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(account);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final warningAccount =
        widget.account ?? Account(name: _nameController.text);
    final hasOlderTransactions =
        _openingEnabled &&
        _openingDate != null &&
        AccountBalanceCalculator.hasTransactionsBeforeOpeningDate(
          account: warningAccount,
          transactions: widget.transactions,
          openingBalanceDate: _openingDate,
        );

    return AlertDialog(
      title: Text(widget.account == null ? 'Create account' : 'Edit account'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('account-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Account name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountType>(
                key: const Key('account-type-field'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Account type'),
                items: [
                  for (final type in AccountType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('account-owner-field'),
                initialValue: _ownerMemberId,
                decoration: const InputDecoration(labelText: 'Owner'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Joint household'),
                  ),
                  for (final member in widget.members)
                    DropdownMenuItem<String?>(
                      value: member.id,
                      child: Text(member.displayName),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _ownerMemberId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('account-currency-field'),
                controller: _currencyController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  counterText: '',
                ),
              ),
              SwitchListTile.adaptive(
                key: const Key('opening-balance-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable starting balance'),
                value: _openingEnabled,
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _openingEnabled = value;
                          if (value) _openingDate ??= DateTime.now();
                        });
                      },
              ),
              if (_openingEnabled) ...[
                TextField(
                  key: const Key('opening-balance-field'),
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Starting balance',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const Key('opening-balance-date'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Balance effective from'),
                  subtitle: Text(
                    _openingDate == null
                        ? 'Required'
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(_openingDate!),
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _saving ? null : _pickDate,
                ),
                if (hasOlderTransactions)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Transactions exist before this date. They remain visible '
                      'but will not affect the current balance.',
                      key: Key('older-transactions-warning'),
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
              ] else if (widget.account?.hasOpeningBalance ?? false)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Saving will remove the starting balance.'),
                ),
              const SizedBox(height: 12),
              const Text(
                'This sets the account’s starting position. It is not counted '
                'as income, expense, cash flow, or tithe.',
                style: TextStyle(fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    key: const Key('account-editor-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-account-button'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving' : 'Save'),
        ),
      ],
    );
  }
}
