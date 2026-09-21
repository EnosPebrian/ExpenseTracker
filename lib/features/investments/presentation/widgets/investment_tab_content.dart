import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../assets/domain/entities/asset_portfolio.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../domain/entities/brokerage_performance.dart';

enum InvestmentSection {
  overview('Overview'),
  brokerageAccounts('Brokerage Accounts'),
  holdings('Holdings'),
  trades('Trades'),
  statements('Statements'),
  performance('Performance');

  const InvestmentSection(this.label);

  final String label;
}

class InvestmentSectionSelector extends StatelessWidget {
  const InvestmentSectionSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final InvestmentSection selected;
  final ValueChanged<InvestmentSection> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('investment-section-selector'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final section in InvestmentSection.values) ...[
          ChoiceChip(
            key: ValueKey('investment-tab-${section.name}'),
            label: Text(section.label),
            selected: section == selected,
            onSelected: (_) => onSelected(section),
          ),
          if (section != InvestmentSection.values.last)
            const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class InvestmentOverviewTab extends StatelessWidget {
  const InvestmentOverviewTab({
    super.key,
    required this.performance,
    required this.activity,
    required this.onAddBrokerageAccount,
  });

  final BrokeragePerformance performance;
  final List<Transaction> activity;
  final VoidCallback onAddBrokerageAccount;

  @override
  Widget build(BuildContext context) {
    if (performance.accounts.isEmpty) {
      return BrokerageEmptyState(onAdd: onAddBrokerageAccount);
    }

    final holdings = _holdings(performance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InvestmentPerformanceGrid(currencies: performance.currencies),
        const SizedBox(height: 16),
        ResponsivePair(
          left: _SectionCard(
            title: 'Brokerage accounts',
            subtitle: '${performance.accounts.length} active',
            children: [
              for (final result in performance.accounts.take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.account_balance_outlined,
                    color: violet,
                  ),
                  title: Text(result.account.name),
                  subtitle: Text('${result.account.currencyCode} settlement'),
                  trailing: Text(
                    _currencyMoney(
                      result.account.currencyCode,
                      result.netWorth,
                    ),
                  ),
                ),
            ],
          ),
          right: _SectionCard(
            title: 'Holdings summary',
            subtitle: holdings.isEmpty
                ? 'No open positions.'
                : '${holdings.length} open ${holdings.length == 1 ? 'position' : 'positions'}',
            children: holdings.isEmpty
                ? const [
                    Text('Holdings appear after recorded buys or imports.'),
                  ]
                : [
                    for (final entry in holdings.take(4))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.holding.name),
                        subtitle: Text(
                          '${entry.holding.quantity} ${entry.holding.unit} · ${entry.account.account.currencyCode}',
                        ),
                        trailing: Text(
                          _currencyMoney(
                            entry.account.account.currencyCode,
                            entry.holding.marketValue,
                          ),
                        ),
                      ),
                  ],
          ),
        ),
        const SizedBox(height: 16),
        _RecentInvestmentActivity(activity: activity),
      ],
    );
  }
}

class BrokerageAccountsTab extends StatelessWidget {
  const BrokerageAccountsTab({
    super.key,
    required this.performance,
    required this.onAdd,
  });

  final BrokeragePerformance performance;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (performance.accounts.isEmpty) {
      return BrokerageEmptyState(onAdd: onAdd);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('add-brokerage-account'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add brokerage account'),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - ((columns - 1) * 14)) / columns;
            return Wrap(
              key: const Key('brokerage-account-grid'),
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final result in performance.accounts)
                  SizedBox(
                    width: width,
                    child: BrokerageAccountCard(result: result),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class InvestmentHoldingsTab extends StatelessWidget {
  const InvestmentHoldingsTab({super.key, required this.performance});

  final BrokeragePerformance performance;

  @override
  Widget build(BuildContext context) {
    final holdings = _holdings(performance);
    if (holdings.isEmpty) {
      return const InvestmentEmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'No holdings yet',
        message:
            'Holdings will appear after brokerage transactions or supported statement imports.',
      );
    }

    return Column(
      children: [
        for (final entry in holdings) ...[
          _HoldingCard(entry: entry),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class InvestmentTradesTab extends StatelessWidget {
  const InvestmentTradesTab({
    super.key,
    required this.transactions,
    required this.accounts,
  });

  final List<Transaction> transactions;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final trades = transactions
        .where(
          (transaction) =>
              transaction.brokerageActivityType == BrokerageActivityType.buy ||
              transaction.brokerageActivityType == BrokerageActivityType.sell,
        )
        .toList(growable: false);
    if (trades.isEmpty) {
      return const InvestmentEmptyState(
        icon: Icons.swap_horiz_rounded,
        title: 'No trades yet',
        message: 'Recorded buys and sells will appear here.',
      );
    }

    final accountsById = {for (final account in accounts) account.id: account};
    return _SectionCard(
      title: 'Trades',
      subtitle: 'Authoritative brokerage buys and sells',
      children: [
        for (final trade in trades)
          Builder(
            builder: (context) {
              final account = accountsById[trade.brokerageAccountId];
              final currency = account?.currencyCode ?? '—';
              final instrument =
                  trade.assetSymbol ?? trade.assetName ?? trade.title;
              return ListTile(
                key: ValueKey('investment-trade-${trade.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF1EEFF),
                  foregroundColor: violet,
                  child: Icon(
                    trade.brokerageActivityType == BrokerageActivityType.buy
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                  ),
                ),
                title: Text(
                  '${trade.brokerageActivityType!.label} · $instrument',
                ),
                subtitle: Text(
                  '${_date(trade.date)} · ${account?.name ?? 'Unavailable account'}\n'
                  '${_quantity(trade)} · Price ${_currencyMoney(currency, trade.unitPrice ?? 0)} · Fee ${_currencyMoney(currency, trade.feeAmount)}',
                ),
                isThreeLine: true,
                trailing: Text(_currencyMoney(currency, trade.amount)),
              );
            },
          ),
      ],
    );
  }
}

class InvestmentStatementsTab extends StatelessWidget {
  const InvestmentStatementsTab({
    super.key,
    required this.hasBrokerageAccount,
    required this.onImport,
    required this.onAddBrokerageAccount,
  });

  final bool hasBrokerageAccount;
  final VoidCallback onImport;
  final VoidCallback onAddBrokerageAccount;

  @override
  Widget build(BuildContext context) => InvestmentEmptyState(
    icon: Icons.upload_file_outlined,
    title: 'Import brokerage statements',
    message: hasBrokerageAccount
        ? 'Bring trades, fees, dividends, and investment activity into Pilgrim Tracker from a reviewed UTF-8 CSV statement.'
        : 'Add a brokerage account before importing a reviewed UTF-8 CSV statement.',
    action: FilledButton.icon(
      key: Key(
        hasBrokerageAccount
            ? 'import-brokerage-statement'
            : 'add-brokerage-account-from-statements',
      ),
      onPressed: hasBrokerageAccount ? onImport : onAddBrokerageAccount,
      icon: Icon(hasBrokerageAccount ? Icons.upload_file : Icons.add),
      label: Text(
        hasBrokerageAccount ? 'Import statement' : 'Add brokerage account',
      ),
    ),
  );
}

class InvestmentPerformanceTab extends StatelessWidget {
  const InvestmentPerformanceTab({super.key, required this.performance});

  final BrokeragePerformance performance;

  @override
  Widget build(BuildContext context) {
    if (performance.currencies.isEmpty) {
      return const InvestmentEmptyState(
        icon: Icons.insights_outlined,
        title: 'No performance yet',
        message:
            'Performance appears after brokerage balances or investment activity are recorded.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Currencies remain separate. Pilgrim does not claim time-weighted or money-weighted returns.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 14),
        InvestmentPerformanceGrid(currencies: performance.currencies),
      ],
    );
  }
}

class BrokerageEmptyState extends StatelessWidget {
  const BrokerageEmptyState({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => InvestmentEmptyState(
    icon: Icons.account_balance_outlined,
    title: 'No brokerage accounts yet',
    message:
        'Add a brokerage account to track investments, holdings, trades, and portfolio performance.',
    action: FilledButton.icon(
      key: const Key('add-brokerage-account'),
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('Add brokerage account'),
    ),
  );
}

class InvestmentEmptyState extends StatelessWidget {
  const InvestmentEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Icon(icon, size: 40, color: violet),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    ),
  );
}

class InvestmentPerformanceGrid extends StatelessWidget {
  const InvestmentPerformanceGrid({super.key, required this.currencies});

  final List<BrokerageCurrencyPerformance> currencies;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 3
          : constraints.maxWidth >= 560
          ? 2
          : 1;
      final width = (constraints.maxWidth - ((columns - 1) * 14)) / columns;
      return Wrap(
        key: const Key('investment-performance-grid'),
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final summary in currencies)
            SizedBox(
              width: width,
              child: _CurrencyCard(summary: summary),
            ),
        ],
      );
    },
  );
}

class BrokerageAccountCard extends StatelessWidget {
  const BrokerageAccountCard({super.key, required this.result});

  final BrokerageAccountPerformance result;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('brokerage-account-${result.account.id}'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.account.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const _StatusBadge(),
            ],
          ),
          const SizedBox(height: 4),
          Text('${result.account.currencyCode} brokerage account'),
          Text(
            'Updated ${_date(result.account.updatedAt)}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          _Metric(
            label: 'Cash balance',
            value: _currencyMoney(
              result.account.currencyCode,
              result.cashBalance,
            ),
          ),
          _Metric(
            label: 'Portfolio value',
            value: _currencyMoney(
              result.account.currencyCode,
              result.portfolio.totalMarketValue,
            ),
          ),
          _Metric(
            label: 'Investment net worth',
            value: _currencyMoney(result.account.currencyCode, result.netWorth),
          ),
        ],
      ),
    ),
  );
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
          _Metric(
            label: 'Portfolio value',
            value: _currencyMoney(
              summary.currencyCode,
              summary.positionMarketValue,
            ),
          ),
          _Metric(
            label: 'Invested cost',
            value: _currencyMoney(
              summary.currencyCode,
              summary.positionCostBasis,
            ),
          ),
          _Metric(
            label: 'Brokerage cash',
            value: _currencyMoney(summary.currencyCode, summary.cashBalance),
          ),
          _Metric(
            label: 'Unrealized gain/loss',
            value: _currencyMoney(summary.currencyCode, summary.unrealizedGain),
          ),
          _Metric(
            label: 'Realized performance',
            value: _currencyMoney(
              summary.currencyCode,
              summary.realizedPerformance,
            ),
          ),
          _Metric(
            label: 'Dividends',
            value: _currencyMoney(summary.currencyCode, summary.dividendIncome),
          ),
          _Metric(
            label: 'Interest income',
            value: _currencyMoney(summary.currencyCode, summary.interestIncome),
          ),
          _Metric(
            label: 'Fees and tax',
            value: _currencyMoney(
              summary.currencyCode,
              summary.investmentCosts,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({required this.entry});

  final _HoldingEntry entry;

  @override
  Widget build(BuildContext context) {
    final holding = entry.holding;
    final currency = entry.account.account.currencyCode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              holding.symbol == null
                  ? holding.name
                  : '${holding.symbol} · ${holding.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(entry.account.account.name),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _Metric(
                  label: 'Quantity',
                  value: '${holding.quantity} ${holding.unit}',
                ),
                _Metric(
                  label: 'Average cost',
                  value: _currencyMoney(currency, holding.averageCost),
                ),
                _Metric(
                  label: 'Last known price',
                  value: holding.currentPrice == null
                      ? 'Unavailable'
                      : _currencyMoney(currency, holding.currentPrice!),
                ),
                _Metric(
                  label: 'Market value',
                  value: _currencyMoney(currency, holding.marketValue),
                ),
                _Metric(
                  label: 'Unrealized gain/loss',
                  value: _currencyMoney(currency, holding.unrealizedGain),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentInvestmentActivity extends StatelessWidget {
  const _RecentInvestmentActivity({required this.activity});

  final List<Transaction> activity;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Recent investment activity',
    subtitle: 'Latest brokerage ledger entries',
    children: activity.isEmpty
        ? const [Text('No investment activity recorded yet.')]
        : [
            for (final transaction in activity.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.show_chart_rounded, color: violet),
                title: Text(transaction.title),
                subtitle: Text(
                  '${transaction.brokerageActivityType!.label} · ${_date(transaction.date)}',
                ),
                trailing: transaction.amount == 0
                    ? const Text('No cash')
                    : Text(money(transaction.amount)),
              ),
          ],
  );
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
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(title, subtitle),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text('$label: $value'),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFE9F7F0),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Active',
      style: TextStyle(
        color: success,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _HoldingEntry {
  const _HoldingEntry({required this.account, required this.holding});

  final BrokerageAccountPerformance account;
  final AssetHolding holding;
}

List<_HoldingEntry> _holdings(BrokeragePerformance performance) => [
  for (final account in performance.accounts)
    for (final holding in account.portfolio.holdings)
      _HoldingEntry(account: account, holding: holding),
];

String _currencyMoney(String currency, int amount) =>
    '$currency ${money(amount)}';

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

String _quantity(Transaction transaction) {
  final quantity = transaction.quantity;
  if (quantity == null) return 'Quantity unavailable';
  return '$quantity ${transaction.unit ?? 'units'}';
}
