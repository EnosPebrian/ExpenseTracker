import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/metric_card.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../analytics/domain/financial_summary.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final topCategory = summary.topCategory;

    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'MAKE SENSE OF THE SIGNAL',
            title: 'Reports',
            subtitle: 'Useful answers, without the spreadsheet sprawl.',
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 850 ? 3 : 1,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.8,
                children: [
                  MetricCard(
                    label: 'Net cash flow',
                    value: _signedCurrency(summary.monthlyNetCashFlow),
                    note: '${summary.activityCount} ledger entries this month',
                  ),
                  MetricCard(
                    label: 'Savings rate',
                    value: _percentage(summary.savingsRate),
                    note: summary.monthlyIncome == 0
                        ? 'No income recorded this month'
                        : 'Net cash flow divided by income',
                  ),
                  MetricCard(
                    label: 'Top category',
                    value: topCategory?.category ?? 'No spending',
                    note: topCategory == null
                        ? 'No expenses recorded this month'
                        : '${_currency(topCategory.amount)} / '
                              '${_percentage(topCategory.share)} of spend',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _currency(int value) {
  return 'Rp ${money(value.abs())}';
}

String _signedCurrency(int value) {
  final prefix = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';

  return '$prefix${_currency(value)}';
}

String _percentage(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}
