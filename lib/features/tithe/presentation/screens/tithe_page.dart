import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../analytics/domain/financial_summary.dart';

class TithePage extends StatelessWidget {
  const TithePage({super.key, required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'GIVING WITH INTENTION',
            title: 'Tithe',
            subtitle: 'A calculation based on the income recorded this month.',
          ),
          ResponsivePair(
            left: _CalculatedTitheCard(summary: summary),
            right: _ActiveTitheRuleCard(summary: summary),
          ),
        ],
      ),
    );
  }
}

class _CalculatedTitheCard extends StatelessWidget {
  const _CalculatedTitheCard({required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D3A),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CALCULATED TITHE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _currency(summary.monthlyTithe),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            MetricSmall(
              'Recorded monthly income',
              _currency(summary.monthlyIncome),
            ),
            const SizedBox(height: 12),
            MetricSmall('Applied rate', _percentage(summary.titheRate)),
            const SizedBox(height: 18),
            const Text(
              'Payment and carry-forward tracking are not yet included.',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTitheRuleCard extends StatelessWidget {
  const _ActiveTitheRuleCard({required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle(
              'Active calculation rule',
              'Applied to recorded monthly income',
            ),
            const SizedBox(height: 22),
            Text(
              _percentage(summary.titheRate),
              style: const TextStyle(
                color: violet,
                fontSize: 40,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Gross recorded income',
              style: TextStyle(color: muted, fontSize: 10),
            ),
            const SizedBox(height: 24),
            const Text(
              'Expense, transfer, and asset conversion entries are excluded.',
              style: TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

String _currency(int value) {
  return 'Rp ${money(value.abs())}';
}

String _percentage(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}
