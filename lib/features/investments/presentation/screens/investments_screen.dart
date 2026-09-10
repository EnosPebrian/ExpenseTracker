import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../domain/entities/brokerage_performance.dart';
import '../controllers/brokerage_controller.dart';

class InvestmentsScreen extends StatelessWidget {
  const InvestmentsScreen({
    super.key,
    required this.bookId,
    required this.memberId,
    required this.performance,
    required this.accounts,
    required this.instruments,
    required this.transactions,
    required this.controller,
    required this.onOpenAccounts,
  });

  final String bookId;
  final String? memberId;
  final BrokeragePerformance performance;
  final List<Account> accounts;
  final List<AssetDefinition> instruments;
  final List<Transaction> transactions;
  final BrokerageController controller;
  final VoidCallback onOpenAccounts;

  Future<void> _add(BuildContext context) async {
    final request = await BrokerageActivityDialog.show(
      context,
      accounts: accounts,
      instruments: instruments,
    );
    if (request == null || !context.mounted) return;
    try {
      await controller.record(
        bookId: bookId,
        memberId: memberId,
        request: request,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not save activity.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brokerageAccounts = accounts
        .where((account) => account.accountType == AccountType.brokerage)
        .toList(growable: false);
    final activity =
        transactions
            .where((transaction) => transaction.brokerageActivityType != null)
            .toList(growable: false)
          ..sort((left, right) => right.date.compareTo(left.date));
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'INVESTMENTS',
            title: 'Brokerage',
            subtitle:
                'Cash, positions, and performance without mixing currencies.',
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  brokerageAccounts.isEmpty
                      ? 'Create a brokerage account before recording activity.'
                      : 'Trades reuse Pilgrim’s weighted-average asset ledger.',
                ),
              ),
              const SizedBox(width: 12),
              if (brokerageAccounts.isEmpty)
                OutlinedButton.icon(
                  onPressed: onOpenAccounts,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Open accounts'),
                )
              else
                FilledButton.icon(
                  key: const Key('add-brokerage-activity'),
                  onPressed: controller.saving ? null : () => _add(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add activity'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (performance.currencies.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No brokerage balances or positions yet.'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 3 : 1;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns == 1 ? 2.2 : 1.35,
                  children: [
                    for (final summary in performance.currencies)
                      _CurrencyCard(summary: summary),
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
          for (final account in performance.accounts) ...[
            _AccountCard(result: account),
            const SizedBox(height: 14),
          ],
          if (activity.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent investment activity',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final transaction in activity.take(12))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.show_chart_rounded,
                          color: violet,
                        ),
                        title: Text(transaction.title),
                        subtitle: Text(
                          '${transaction.brokerageActivityType!.label} · '
                          '${_date(transaction.date)}',
                        ),
                        trailing: transaction.amount == 0
                            ? const Text('No cash')
                            : Text(money(transaction.amount)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({required this.summary});
  final BrokerageCurrencyPerformance summary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.currencyCode,
            style: const TextStyle(fontWeight: FontWeight.w800, color: violet),
          ),
          const SizedBox(height: 8),
          _Metric(label: 'Investment net worth', value: summary.netWorth),
          _Metric(label: 'Brokerage cash', value: summary.cashBalance),
          _Metric(label: 'Positions', value: summary.positionMarketValue),
          _Metric(
            label: 'Realized performance',
            value: summary.realizedPerformance,
          ),
          _Metric(label: 'Unrealized gain/loss', value: summary.unrealizedGain),
        ],
      ),
    ),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.result});
  final BrokerageAccountPerformance result;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.account.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('${result.account.currencyCode} settlement account'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _Metric(label: 'Cash', value: result.cashBalance),
              _Metric(
                label: 'Positions',
                value: result.portfolio.totalMarketValue,
              ),
              _Metric(label: 'Realized', value: result.realizedPerformance),
              _Metric(
                label: 'Unrealized',
                value: result.portfolio.totalUnrealizedGain,
              ),
            ],
          ),
          if (result.portfolio.holdings.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('No open positions.'),
          ] else ...[
            const Divider(height: 28),
            for (final holding in result.portfolio.holdings)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(holding.name),
                subtitle: Text(
                  '${holding.quantity} ${holding.unit} · '
                  '${holding.currentPrice == null
                      ? 'Current price unavailable'
                      : holding.isPriceDelayed
                      ? 'Price delayed'
                      : 'Current price available'}',
                ),
                trailing: Text(money(holding.marketValue)),
              ),
          ],
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label: ${money(value)}'),
  );
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
