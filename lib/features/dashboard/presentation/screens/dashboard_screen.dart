import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/metric_card.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../analytics/domain/financial_summary.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/presentation/widgets/transaction_tile.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.transactions,
    required this.onOpen,
    required this.summary,
    required this.referenceDate,
  });

  final List<Transaction> transactions;
  final ValueChanged<Transaction> onOpen;
  final FinancialSummary summary;
  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            kicker: _formatLongDate(referenceDate).toUpperCase(),
            title: 'Good morning',
            subtitle: "Here's your financial pulse for this month.",
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 1050
                    ? 4
                    : constraints.maxWidth > 560
                    ? 2
                    : 1,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: constraints.maxWidth > 1050 ? 2.05 : 2.2,
                children: [
                  MetricCard(
                    label: 'Recorded balance',
                    value: _signedCurrency(summary.recordedBalance),
                    note: 'Recorded income minus expenses',
                    dark: true,
                  ),
                  MetricCard(
                    label: 'Income',
                    value: _currency(summary.monthlyIncome),
                    note: _monthYear(summary.periodStart),
                  ),
                  MetricCard(
                    label: 'Expenses',
                    value: _currency(summary.monthlyExpenses),
                    note: _monthYear(summary.periodStart),
                  ),
                  MetricCard(
                    label: 'Calculated tithe',
                    value: _currency(summary.monthlyTithe),
                    note: '${_percentage(summary.titheRate)} of monthly income',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          ResponsivePair(
            left: CashFlowCard(summary: summary),
            right: SpendingCard(summary: summary),
          ),
          const SizedBox(height: 14),
          ResponsivePair(
            left: RecentTransactions(
              transactions: transactions,
              onOpen: onOpen,
            ),
            right: ActivityCard(summary: summary),
          ),
        ],
      ),
    );
  }
}

class CashFlowCard extends StatelessWidget {
  const CashFlowCard({super.key, required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final netPositive = summary.monthlyNetCashFlow >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelTitle('Cash flow', _monthYear(summary.periodStart)),
            const SizedBox(height: 24),
            _CashFlowLine(
              label: 'Income',
              amount: summary.monthlyIncome,
              icon: Icons.south_west_rounded,
              iconColor: success,
            ),
            const SizedBox(height: 12),
            _CashFlowLine(
              label: 'Expenses',
              amount: summary.monthlyExpenses,
              icon: Icons.north_east_rounded,
              iconColor: const Color(0xFFE28068),
            ),
            const Divider(height: 30),
            Row(
              children: [
                const Text(
                  'Net cash flow',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  _signedCurrency(
                    summary.monthlyNetCashFlow,
                    showPositiveSign: true,
                  ),
                  style: TextStyle(
                    color: netPositive ? success : const Color(0xFFB42318),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _CashFlowLine extends StatelessWidget {
  const _CashFlowLine({
    required this.label,
    required this.amount,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final int amount;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 17),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
        const Spacer(),
        Text(
          _currency(amount),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class SpendingCard extends StatelessWidget {
  const SpendingCard({super.key, required this.summary});

  final FinancialSummary summary;

  static const _colors = [
    violet,
    Color(0xFF739EE8),
    Color(0xFFF4AC8F),
    Color(0xFF76C99D),
    Color(0xFFD9D7E2),
  ];

  @override
  Widget build(BuildContext context) {
    final spending = summary.spendingByCategory.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelTitle('Spending by category', _monthYear(summary.periodStart)),
            const SizedBox(height: 22),
            if (spending.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Text(
                  'No expenses recorded this month.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              )
            else
              for (var index = 0; index < spending.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: _colors[index % _colors.length],
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          spending[index].category,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _currency(spending[index].amount),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 46,
                        child: Text(
                          _percentage(spending[index].share),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class RecentTransactions extends StatelessWidget {
  const RecentTransactions({
    super.key,
    required this.transactions,
    required this.onOpen,
  });

  final List<Transaction> transactions;
  final ValueChanged<Transaction> onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Recent transactions', 'Your latest activity'),
            const SizedBox(height: 12),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'No transactions recorded yet.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              )
            else
              for (final transaction in transactions.take(4))
                TransactionTile(
                  transaction: transaction,
                  onTap: () {
                    onOpen(transaction);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final topCategory = summary.topCategory;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle(
              'Monthly activity',
              'Based on recorded transactions',
            ),
            const SizedBox(height: 20),
            _ActivityLine(
              label: 'Ledger entries',
              value: '${summary.activityCount}',
            ),
            const SizedBox(height: 15),
            _ActivityLine(
              label: 'Savings rate',
              value: _percentage(summary.savingsRate),
            ),
            const SizedBox(height: 15),
            _ActivityLine(
              label: 'Top spending category',
              value: topCategory?.category ?? 'No spending',
            ),
            const SizedBox(height: 15),
            _ActivityLine(
              label: 'Top category amount',
              value: topCategory == null
                  ? _currency(0)
                  : _currency(topCategory.amount),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

const _monthNames = [
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
];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _formatLongDate(DateTime value) {
  return '${_weekdayNames[value.weekday - 1]}, '
      '${_monthNames[value.month - 1]} '
      '${value.day}, ${value.year}';
}

String _monthYear(DateTime value) {
  return '${_monthNames[value.month - 1]} ${value.year}';
}

String _currency(int value) {
  return 'Rp ${money(value.abs())}';
}

String _signedCurrency(int value, {bool showPositiveSign = false}) {
  final prefix = value < 0
      ? '-'
      : value > 0 && showPositiveSign
      ? '+'
      : '';

  return '$prefix${_currency(value)}';
}

String _percentage(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}
