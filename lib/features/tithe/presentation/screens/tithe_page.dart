import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/tithe_summary.dart';

class TithePage extends StatelessWidget {
  const TithePage({
    super.key,
    required this.summary,
    required this.onRecordPayment,
    this.onOpenPayment,
  });

  final TitheSummary summary;
  final VoidCallback onRecordPayment;
  final ValueChanged<Transaction>? onOpenPayment;

  @override
  Widget build(BuildContext context) {
    final cumulative = summary.cumulative;
    return PageFrame(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                kicker: 'GIVING WITH INTENTION',
                title: 'Tithe',
                subtitle:
                    'Tithe due follows your active policy. Payments are ordinary expenses in the System Tithe category.',
              ),
              _BalanceHero(summary: cumulative, currency: summary.currencyCode),
              const SizedBox(height: 18),
              ResponsivePair(
                left: _PeriodBlock(
                  key: const Key('tithe-this-month'),
                  title: 'This month',
                  summary: summary.currentMonth,
                  currency: summary.currencyCode,
                ),
                right: _PeriodBlock(
                  key: const Key('tithe-year-to-date'),
                  title: 'Year to date',
                  summary: summary.yearToDate,
                  currency: summary.currencyCode,
                ),
              ),
              const SizedBox(height: 18),
              _PaymentsSection(
                payments: summary.recentPayments,
                currency: summary.currencyCode,
                onOpen: onOpenPayment,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('record-tithe-payment'),
                onPressed: onRecordPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: violet,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: const Text('Record Tithe Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.summary, required this.currency});

  final TithePeriodSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final label = summary.isAdvance
        ? 'Advance / Credit'
        : summary.isOutstanding
        ? 'Outstanding'
        : 'Fully paid';
    return Container(
      key: Key(summary.isAdvance ? 'tithe-advance' : 'tithe-balance'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D3A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CURRENT BALANCE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            _currency(summary.balance.abs(), currency),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (summary.due == 0 && summary.paid == 0) ...[
            const SizedBox(height: 14),
            const Text(
              'No tithe obligation or payment is recorded yet. Add eligible income and Pilgrim will calculate what is due.',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodBlock extends StatelessWidget {
  const _PeriodBlock({
    super.key,
    required this.title,
    required this.summary,
    required this.currency,
  });

  final String title;
  final TithePeriodSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _MetricRow('Due', summary.due, currency),
          _MetricRow('Paid', summary.paid, currency),
          const Divider(height: 22),
          _MetricRow('Balance', summary.balance, currency, emphasized: true),
        ],
      ),
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(
    this.label,
    this.value,
    this.currency, {
    this.emphasized = false,
  });

  final String label;
  final int value;
  final String currency;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Text(
          _currency(value, currency),
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({
    required this.payments,
    required this.currency,
    this.onOpen,
  });

  final List<Transaction> payments;
  final String currency;
  final ValueChanged<Transaction>? onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(
            'Recent payments',
            'Derived from ordinary transactions',
          ),
          const SizedBox(height: 12),
          if (payments.isEmpty)
            const Padding(
              key: Key('tithe-empty-payments'),
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No tithe payments recorded yet.'),
            ),
          for (final payment in payments)
            ListTile(
              key: Key('tithe-payment-${payment.id}'),
              contentPadding: EdgeInsets.zero,
              onTap: onOpen == null ? null : () => onOpen!(payment),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1EEFF),
                child: Icon(Icons.favorite_outline, color: violet, size: 18),
              ),
              title: Text(payment.account),
              subtitle: Text(_date(payment.date)),
              trailing: Text(
                _currency(payment.amount, currency),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    ),
  );
}

String _currency(int value, String currency) {
  final sign = value < 0 ? '-' : '';
  final symbol = currency == 'IDR' ? 'Rp' : currency;
  return '$sign$symbol ${money(value.abs())}';
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')} '
    '${_monthNames[value.month - 1]} ${value.year}';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
