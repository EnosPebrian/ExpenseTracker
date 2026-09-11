import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../domain/entities/brokerage_performance.dart';
import '../controllers/brokerage_controller.dart';
import '../widgets/investment_tab_content.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({
    super.key,
    required this.bookId,
    required this.memberId,
    required this.performance,
    required this.accounts,
    required this.instruments,
    required this.transactions,
    required this.controller,
    required this.onAddBrokerageAccount,
    required this.onImportStatement,
  });

  final String bookId;
  final String? memberId;
  final BrokeragePerformance performance;
  final List<Account> accounts;
  final List<AssetDefinition> instruments;
  final List<Transaction> transactions;
  final BrokerageController controller;
  final VoidCallback onAddBrokerageAccount;
  final VoidCallback onImportStatement;

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  InvestmentSection selectedSection = InvestmentSection.overview;

  Future<void> _add(BuildContext context) async {
    final request = await BrokerageActivityDialog.show(
      context,
      accounts: widget.accounts,
      instruments: widget.instruments,
    );
    if (request == null || !context.mounted) return;
    try {
      await widget.controller.record(
        bookId: widget.bookId,
        memberId: widget.memberId,
        request: request,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.error ?? 'Could not save activity.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brokerageAccounts = widget.accounts
        .where((account) => account.accountType == AccountType.brokerage)
        .toList(growable: false);
    final activity =
        widget.transactions
            .where((transaction) => transaction.brokerageActivityType != null)
            .toList(growable: false)
          ..sort((left, right) => right.date.compareTo(left.date));
    final content = switch (selectedSection) {
      InvestmentSection.overview => InvestmentOverviewTab(
        performance: widget.performance,
        activity: activity,
        onAddBrokerageAccount: widget.onAddBrokerageAccount,
      ),
      InvestmentSection.brokerageAccounts => BrokerageAccountsTab(
        performance: widget.performance,
        onAdd: widget.onAddBrokerageAccount,
      ),
      InvestmentSection.holdings => InvestmentHoldingsTab(
        performance: widget.performance,
      ),
      InvestmentSection.trades => InvestmentTradesTab(
        transactions: activity,
        accounts: brokerageAccounts,
      ),
      InvestmentSection.statements => InvestmentStatementsTab(
        hasBrokerageAccount: brokerageAccounts.isNotEmpty,
        onImport: widget.onImportStatement,
        onAddBrokerageAccount: widget.onAddBrokerageAccount,
      ),
      InvestmentSection.performance => InvestmentPerformanceTab(
        performance: widget.performance,
      ),
    };
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'INVESTMENTS',
            title: 'Investments',
            subtitle:
                'Track brokerage accounts, holdings, trades, and investment performance.',
          ),
          InvestmentSectionSelector(
            selected: selectedSection,
            onSelected: (section) => setState(() => selectedSection = section),
          ),
          const SizedBox(height: 16),
          if (brokerageAccounts.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('add-brokerage-activity'),
                onPressed: widget.controller.saving
                    ? null
                    : () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('Add activity'),
              ),
            ),
          if (brokerageAccounts.isNotEmpty) const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(key: ValueKey(selectedSection), child: content),
          ),
        ],
      ),
    );
  }
}

class BrokerageActivityDialog extends StatefulWidget {
  const BrokerageActivityDialog({
    super.key,
    required this.accounts,
    required this.instruments,
  });

  final List<Account> accounts;
  final List<AssetDefinition> instruments;

  static Future<BrokerageActivityRequest?> show(
    BuildContext context, {
    required List<Account> accounts,
    required List<AssetDefinition> instruments,
  }) => showDialog<BrokerageActivityRequest>(
    context: context,
    builder: (_) =>
        BrokerageActivityDialog(accounts: accounts, instruments: instruments),
  );

  @override
  State<BrokerageActivityDialog> createState() =>
      _BrokerageActivityDialogState();
}

class _BrokerageActivityDialogState extends State<BrokerageActivityDialog> {
  BrokerageActivityType type = BrokerageActivityType.buy;
  String? brokerageId;
  String? instrumentId;
  String? counterpartyId;
  DateTime date = DateTime.now();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final unitPrice = TextEditingController();
  final fee = TextEditingController();
  final numerator = TextEditingController(text: '2');
  final denominator = TextEditingController(text: '1');
  final note = TextEditingController();
  final reference = TextEditingController();
  String? error;

  List<Account> get brokerages => widget.accounts
      .where((account) => account.accountType == AccountType.brokerage)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    brokerageId = brokerages.firstOrNull?.id;
    instrumentId = widget.instruments.firstOrNull?.id;
    counterpartyId = widget.accounts
        .where((account) => account.id != brokerageId)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    for (final controller in [
      amount,
      quantity,
      unitPrice,
      fee,
      numerator,
      denominator,
      note,
      reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get isTrade =>
      type == BrokerageActivityType.buy || type == BrokerageActivityType.sell;
  bool get isFunding =>
      type == BrokerageActivityType.deposit ||
      type == BrokerageActivityType.withdrawal;
  bool get isSplit => type == BrokerageActivityType.split;
  bool get needsInstrument => isTrade || isSplit;

  void _submit() {
    final amountValue = _integer(amount.text);
    final quantityValue = double.tryParse(quantity.text.trim());
    final priceValue = _integer(unitPrice.text);
    final feeValue = _integer(fee.text);
    if (brokerageId == null ||
        (needsInstrument && instrumentId == null) ||
        (isFunding && counterpartyId == null) ||
        (!isSplit && amountValue <= 0) ||
        (isTrade &&
            (quantityValue == null || quantityValue <= 0 || priceValue <= 0))) {
      setState(
        () => error = 'Complete all required fields with positive values.',
      );
      return;
    }
    Navigator.pop(
      context,
      BrokerageActivityRequest(
        activityType: type,
        brokerageAccountId: brokerageId!,
        date: date,
        instrumentId: instrumentId,
        counterpartyAccountId: counterpartyId,
        amount: amountValue,
        quantity: quantityValue,
        unitPrice: priceValue,
        feeAmount: feeValue,
        splitNumerator: _integer(numerator.text),
        splitDenominator: _integer(denominator.text),
        note: note.text,
        reference: reference.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record investment activity'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<BrokerageActivityType>(
              key: const Key('brokerage-activity-type'),
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: [
                for (final value in BrokerageActivityType.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: (value) => setState(() => type = value ?? type),
            ),
            DropdownButtonFormField<String>(
              initialValue: brokerageId,
              decoration: const InputDecoration(labelText: 'Brokerage account'),
              items: [
                for (final account in brokerages)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) => setState(() => brokerageId = value),
            ),
            if (needsInstrument ||
                type == BrokerageActivityType.dividend ||
                type == BrokerageActivityType.fee ||
                type == BrokerageActivityType.tax)
              DropdownButtonFormField<String?>(
                initialValue: instrumentId,
                decoration: InputDecoration(
                  labelText: needsInstrument
                      ? 'Instrument'
                      : 'Instrument (optional)',
                ),
                items: [
                  if (!needsInstrument)
                    const DropdownMenuItem(value: null, child: Text('None')),
                  for (final instrument in widget.instruments)
                    DropdownMenuItem(
                      value: instrument.id,
                      child: Text(instrument.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => instrumentId = value),
              ),
            if (isFunding)
              DropdownButtonFormField<String>(
                initialValue: counterpartyId,
                decoration: const InputDecoration(labelText: 'Other account'),
                items: [
                  for (final account in widget.accounts)
                    if (account.id != brokerageId)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                ],
                onChanged: (value) => setState(() => counterpartyId = value),
              ),
            if (!isSplit)
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
            if (isTrade) ...[
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              TextField(
                controller: unitPrice,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Unit price'),
              ),
              TextField(
                controller: fee,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fee (optional)'),
              ),
            ],
            if (isSplit) ...[
              TextField(
                controller: numerator,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'New shares'),
              ),
              TextField(
                controller: denominator,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'For existing shares',
                ),
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_date(date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2200),
                  initialDate: date,
                );
                if (selected != null) setState(() => date = selected);
              },
            ),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
              ),
            ),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
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
        key: const Key('save-brokerage-activity'),
        onPressed: _submit,
        child: const Text('Save'),
      ),
    ],
  );

  static int _integer(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
