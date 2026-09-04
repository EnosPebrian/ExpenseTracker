import 'package:flutter/material.dart';

import '../../domain/services/internal_transfer_matcher.dart';
import '../controllers/internal_transfer_review_controller.dart';

class InternalTransferReviewScreen extends StatelessWidget {
  const InternalTransferReviewScreen({super.key, required this.controller});

  final InternalTransferReviewController controller;

  static Future<void> show(
    BuildContext context, {
    required InternalTransferReviewController controller,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => InternalTransferReviewScreen(controller: controller),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review possible transfers')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final matches = controller.matches;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Possible internal transfers',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Pilgrim found transactions that may represent money moved between '
          'your own accounts. Nothing changes until you confirm.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () {
                controller.useCurrentMonth();
                controller.scan();
              },
              child: const Text('Current month'),
            ),
            OutlinedButton(
              onPressed: controller.usePreviousMonth,
              child: const Text('Previous month'),
            ),
            OutlinedButton(
              onPressed: () => _customRange(context),
              child: const Text('Custom range'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _filter('All', InternalTransferReviewFilter.all),
            _filter('Strong', InternalTransferReviewFilter.strong),
            _filter('Possible', InternalTransferReviewFilter.possible),
            _filter('Ambiguous', InternalTransferReviewFilter.ambiguous),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            Chip(
              label: Text(
                'Strong: ${controller.count(InternalTransferMatchClassification.strong)}',
              ),
            ),
            Chip(
              label: Text(
                'Possible: ${controller.count(InternalTransferMatchClassification.possible)}',
              ),
            ),
            Chip(
              label: Text(
                'Ambiguous: ${controller.count(InternalTransferMatchClassification.ambiguous)}',
              ),
            ),
          ],
        ),
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (controller.busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (matches.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  Text('No likely internal transfers found for this period.'),
                  SizedBox(height: 6),
                  Text(
                    'Pilgrim looks for equal-value movements between different '
                    'accounts in the same currency.',
                  ),
                ],
              ),
            ),
          )
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: controller.busy
                  ? null
                  : controller.confirmAllUnambiguous,
              icon: const Icon(Icons.done_all),
              label: const Text('Confirm unambiguous transfers'),
            ),
          ),
          const SizedBox(height: 8),
          for (final match in matches) _matchCard(context, match),
        ],
      ],
    );
  }

  Widget _filter(String label, InternalTransferReviewFilter value) =>
      FilterChip(
        label: Text(label),
        selected: controller.filter == value,
        onSelected: (_) => controller.setFilter(value),
      );

  Widget _matchCard(BuildContext context, InternalTransferMatch match) {
    final counterpart = match.counterpart ?? match.options.first.counterpart;
    final outgoing = match.source.type.name == 'expense'
        ? match.source
        : counterpart;
    final incoming = match.source.type.name == 'income'
        ? match.source
        : counterpart;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              match.classification.name.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('${outgoing.accountName} → ${incoming.accountName}'),
            Text('${outgoing.currencyCode} ${_grouped(outgoing.amount)}'),
            Text(
              '${_date(outgoing.date)} · ${outgoing.description}\n'
              '${_date(incoming.date)} · ${incoming.description}',
            ),
            const SizedBox(height: 8),
            for (final reason in match.options.first.reasons) Text('• $reason'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _review(context, match),
                  child: const Text('Review'),
                ),
                if (match.canConfirm)
                  FilledButton(
                    onPressed: () => _review(context, match),
                    child: const Text('Confirm transfer'),
                  ),
                if (match.classification ==
                    InternalTransferMatchClassification.ambiguous)
                  OutlinedButton(
                    onPressed: () => _chooseCounterpart(context, match),
                    child: const Text('Choose counterpart'),
                  ),
                TextButton(
                  onPressed: () => controller.dismiss(match.source.id),
                  child: const Text('Not a transfer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    InternalTransferMatch match,
  ) async {
    final counterpart = match.counterpart;
    if (counterpart == null) {
      await _chooseCounterpart(context, match);
      return;
    }
    final outgoing = match.source.type.name == 'expense'
        ? match.source
        : counterpart;
    final incoming = match.source.type.name == 'income'
        ? match.source
        : counterpart;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert these entries into an internal transfer?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FROM\n${outgoing.accountName}\n${_date(outgoing.date)}\n'
                '${outgoing.currencyCode} ${_grouped(outgoing.amount)}\n'
                '${outgoing.description}',
              ),
              const SizedBox(height: 16),
              Text(
                'TO\n${incoming.accountName}\n${_date(incoming.date)}\n'
                '${incoming.currencyCode} ${_grouped(incoming.amount)}\n'
                '${incoming.description}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Internal transfers move money between your own accounts and '
                'are not counted as household income or expense.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Using current device data. Changes will synchronize when online.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              controller.dismiss(match.source.id);
              Navigator.pop(context, false);
            },
            child: const Text('Keep separate'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm transfer'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.confirm(match);
  }

  Future<void> _chooseCounterpart(
    BuildContext context,
    InternalTransferMatch match,
  ) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose counterpart'),
        children: [
          for (final option in match.options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.counterpart.id),
              child: Text(
                '${option.counterpart.accountName} · '
                '${_date(option.counterpart.date)} · '
                '${option.counterpart.currencyCode} '
                '${_grouped(option.counterpart.amount)}',
              ),
            ),
        ],
      ),
    );
    if (chosen != null) controller.chooseCounterpart(match.source.id, chosen);
  }

  Future<void> _customRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: controller.from,
        end: controller.to,
      ),
    );
    if (range != null) controller.useCustomRange(range.start, range.end);
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _grouped(int value) {
    final digits = value.toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) output.write('.');
      output.write(digits[index]);
    }
    return output.toString();
  }
}
