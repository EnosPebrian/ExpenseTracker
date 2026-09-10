import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../../transactions/domain/import/transaction_import_models.dart';
import '../../domain/import/brokerage_import_models.dart';
import '../../domain/import/brokerage_import_planner.dart';
import '../controllers/brokerage_import_controller.dart';

class BrokerageImportScreen extends StatefulWidget {
  const BrokerageImportScreen({
    super.key,
    required this.bookId,
    required this.memberId,
    required this.accounts,
    required this.instruments,
    required this.controller,
    required this.remoteFreshnessVerified,
  });

  final String bookId;
  final String? memberId;
  final List<Account> accounts;
  final List<AssetDefinition> instruments;
  final BrokerageImportController controller;
  final bool remoteFreshnessVerified;

  static Future<void> show(
    BuildContext context, {
    required String bookId,
    required String? memberId,
    required List<Account> accounts,
    required List<AssetDefinition> instruments,
    required BrokerageImportController controller,
    required bool remoteFreshnessVerified,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BrokerageImportScreen(
        bookId: bookId,
        memberId: memberId,
        accounts: accounts,
        instruments: instruments,
        controller: controller,
        remoteFreshnessVerified: remoteFreshnessVerified,
      ),
    ),
  );

  @override
  State<BrokerageImportScreen> createState() => _BrokerageImportScreenState();
}

class _BrokerageImportScreenState extends State<BrokerageImportScreen> {
  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    final brokerage = widget.accounts
        .where((account) => account.accountType == AccountType.brokerage)
        .firstOrNull;
    if (!widget.accounts.any(
      (account) => account.id == controller.brokerageAccountId,
    )) {
      controller.brokerageAccountId = brokerage?.id;
    }
    if (!widget.accounts.any(
      (account) => account.id == controller.counterpartyAccountId,
    )) {
      controller.counterpartyAccountId = widget.accounts
          .where(
            (account) =>
                account.id != brokerage?.id &&
                account.currencyCode == brokerage?.currencyCode,
          )
          .firstOrNull
          ?.id;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Import brokerage statement')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Reviewed CSV import',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'Map columns explicitly. Unknown activities and instruments stay unresolved until you choose what they mean.',
            ),
            const SizedBox(height: 16),
            _AccountSelection(widget: widget),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: controller.busy ? null : controller.selectCsv,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(
                controller.source == null
                    ? 'Choose brokerage CSV'
                    : 'Choose another CSV',
              ),
            ),
            if (controller.source case final source?) ...[
              const SizedBox(height: 12),
              Text('${source.fileName} · ${source.rows.length} rows'),
              const SizedBox(height: 12),
              _MappingPanel(controller: controller),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('analyze-brokerage-csv'),
                onPressed: controller.busy
                    ? null
                    : () => controller.analyze(
                        bookId: widget.bookId,
                        remoteFresh: widget.remoteFreshnessVerified,
                      ),
                child: const Text('Analyze statement'),
              ),
            ],
            if (controller.error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.preview case final preview?) ...[
              const SizedBox(height: 20),
              _PreviewSummary(preview: preview),
              if (!preview.remoteFreshnessVerified)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Offline review uses current local data. Reconnect before commit when possible to refresh duplicate evidence.',
                    ),
                  ),
                ),
              for (final draft in preview.drafts)
                _DraftCard(
                  draft: draft,
                  bookId: widget.bookId,
                  instruments: widget.instruments,
                  controller: controller,
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('commit-brokerage-import'),
                onPressed: controller.busy || !preview.canCommit
                    ? null
                    : () => controller.commit(
                        bookId: widget.bookId,
                        memberId: widget.memberId,
                      ),
                icon: const Icon(Icons.check_circle_outline),
                label: Text('Import ${preview.readyCount} activities'),
              ),
            ],
            if (controller.result case final result?) ...[
              const SizedBox(height: 20),
              Card(
                color: const Color(0xFFE7F6EF),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Import complete: ${result.importedEventIds.length} events, '
                    '${result.transactionsCreated} financial rows, '
                    '${result.instrumentsCreated} instruments. '
                    '${result.alreadyImported} already present.',
                  ),
                ),
              ),
            ],
            if (controller.busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        );
      },
    ),
  );
}

class _AccountSelection extends StatelessWidget {
  const _AccountSelection({required this.widget});
  final BrokerageImportScreen widget;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final brokerages = widget.accounts
        .where((account) => account.accountType == AccountType.brokerage)
        .toList(growable: false);
    final selected = brokerages
        .where((account) => account.id == controller.brokerageAccountId)
        .firstOrNull;
    final counterparties = widget.accounts
        .where(
          (account) =>
              account.id != selected?.id &&
              account.currencyCode == selected?.currencyCode,
        )
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: controller.brokerageAccountId,
              decoration: const InputDecoration(labelText: 'Brokerage account'),
              items: [
                for (final account in brokerages)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                final account = brokerages.firstWhere(
                  (candidate) => candidate.id == value,
                );
                final other = widget.accounts
                    .where(
                      (candidate) =>
                          candidate.id != value &&
                          candidate.currencyCode == account.currencyCode,
                    )
                    .firstOrNull;
                controller.setAccounts(
                  brokerageId: value,
                  counterpartyId: other?.id,
                );
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue:
                  counterparties.any(
                    (account) => account.id == controller.counterpartyAccountId,
                  )
                  ? controller.counterpartyAccountId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Funding account for deposits/withdrawals',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Not selected'),
                ),
                for (final account in counterparties)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) {
                final brokerage = controller.brokerageAccountId;
                if (brokerage != null) {
                  controller.setAccounts(
                    brokerageId: brokerage,
                    counterpartyId: value,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MappingPanel extends StatelessWidget {
  const _MappingPanel({required this.controller});
  final BrokerageImportController controller;

  @override
  Widget build(BuildContext context) {
    final source = controller.source!;
    final mapping = controller.mapping!;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: canonicalBrokerageMappingFor(source.headers) == null,
        title: const Text('Column mapping'),
        subtitle: const Text('Review every source field before analysis.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _column('Date', mapping.dateColumn, (value) {
                _update(mapping, dateColumn: value!);
              }),
              _column('Activity', mapping.activityColumn, (value) {
                _update(mapping, activityColumn: value!);
              }),
              _column('Symbol / instrument', mapping.instrumentColumn, (value) {
                _update(mapping, instrumentColumn: value!);
              }),
              _column('Gross amount', mapping.grossAmountColumn, (value) {
                _update(mapping, grossAmountColumn: value!);
              }),
              _column('Quantity', mapping.quantityColumn, (value) {
                _update(mapping, quantityColumn: value);
              }, optional: true),
              _column('Execution price', mapping.executionPriceColumn, (value) {
                _update(mapping, executionPriceColumn: value);
              }, optional: true),
              _column('Fee', mapping.feeColumn, (value) {
                _update(mapping, feeColumn: value);
              }, optional: true),
              _column('Tax', mapping.taxColumn, (value) {
                _update(mapping, taxColumn: value);
              }, optional: true),
              _column('Currency', mapping.currencyColumn, (value) {
                _update(mapping, currencyColumn: value);
              }, optional: true),
              _column('Reference', mapping.referenceColumn, (value) {
                _update(mapping, referenceColumn: value);
              }, optional: true),
              _column('Note', mapping.noteColumn, (value) {
                _update(mapping, noteColumn: value);
              }, optional: true),
              _column('Broker realized P&L', mapping.realizedPnlColumn, (
                value,
              ) {
                _update(mapping, realizedPnlColumn: value);
              }, optional: true),
              _column('Split numerator', mapping.splitNumeratorColumn, (value) {
                _update(mapping, splitNumeratorColumn: value);
              }, optional: true),
              _column('Split denominator', mapping.splitDenominatorColumn, (
                value,
              ) {
                _update(mapping, splitDenominatorColumn: value);
              }, optional: true),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CsvDateFormat>(
            initialValue: mapping.dateFormat,
            decoration: const InputDecoration(labelText: 'Date format'),
            items: [
              for (final value in CsvDateFormat.values)
                DropdownMenuItem(value: value, child: Text(value.name)),
            ],
            onChanged: (value) {
              if (value != null) _update(mapping, dateFormat: value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<CsvSeparator>(
                  initialValue: mapping.decimalSeparator,
                  decoration: const InputDecoration(
                    labelText: 'Decimal separator',
                  ),
                  items: [
                    for (final value in CsvSeparator.values)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _update(mapping, decimalSeparator: value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<CsvSeparator>(
                  initialValue: mapping.thousandsSeparator,
                  decoration: const InputDecoration(
                    labelText: 'Thousands separator',
                  ),
                  items: [
                    for (final value in CsvSeparator.values)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _update(mapping, thousandsSeparator: value);
                    }
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Strip currency symbols'),
            value: mapping.stripCurrencySymbols,
            onChanged: (value) => _update(mapping, stripCurrencySymbols: value),
          ),
        ],
      ),
    );
  }

  Widget _column(
    String label,
    int? value,
    ValueChanged<int?> onChanged, {
    bool optional = false,
  }) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<int?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        if (optional)
          const DropdownMenuItem(value: null, child: Text('Not mapped')),
        for (var index = 0; index < controller.source!.headers.length; index++)
          DropdownMenuItem(
            value: index,
            child: Text(controller.source!.headers[index]),
          ),
      ],
      onChanged: onChanged,
    ),
  );

  void _update(
    BrokerageStatementMapping current, {
    int? dateColumn,
    int? activityColumn,
    int? instrumentColumn,
    int? grossAmountColumn,
    Object? quantityColumn = _unchanged,
    Object? executionPriceColumn = _unchanged,
    Object? feeColumn = _unchanged,
    Object? taxColumn = _unchanged,
    Object? currencyColumn = _unchanged,
    Object? referenceColumn = _unchanged,
    Object? noteColumn = _unchanged,
    Object? realizedPnlColumn = _unchanged,
    Object? splitNumeratorColumn = _unchanged,
    Object? splitDenominatorColumn = _unchanged,
    CsvDateFormat? dateFormat,
    CsvSeparator? decimalSeparator,
    CsvSeparator? thousandsSeparator,
    bool? stripCurrencySymbols,
  }) => controller.setMapping(
    BrokerageStatementMapping(
      dateColumn: dateColumn ?? current.dateColumn,
      activityColumn: activityColumn ?? current.activityColumn,
      instrumentColumn: instrumentColumn ?? current.instrumentColumn,
      grossAmountColumn: grossAmountColumn ?? current.grossAmountColumn,
      quantityColumn: identical(quantityColumn, _unchanged)
          ? current.quantityColumn
          : quantityColumn as int?,
      executionPriceColumn: identical(executionPriceColumn, _unchanged)
          ? current.executionPriceColumn
          : executionPriceColumn as int?,
      feeColumn: identical(feeColumn, _unchanged)
          ? current.feeColumn
          : feeColumn as int?,
      taxColumn: identical(taxColumn, _unchanged)
          ? current.taxColumn
          : taxColumn as int?,
      currencyColumn: identical(currencyColumn, _unchanged)
          ? current.currencyColumn
          : currencyColumn as int?,
      referenceColumn: identical(referenceColumn, _unchanged)
          ? current.referenceColumn
          : referenceColumn as int?,
      noteColumn: identical(noteColumn, _unchanged)
          ? current.noteColumn
          : noteColumn as int?,
      realizedPnlColumn: identical(realizedPnlColumn, _unchanged)
          ? current.realizedPnlColumn
          : realizedPnlColumn as int?,
      splitNumeratorColumn: identical(splitNumeratorColumn, _unchanged)
          ? current.splitNumeratorColumn
          : splitNumeratorColumn as int?,
      splitDenominatorColumn: identical(splitDenominatorColumn, _unchanged)
          ? current.splitDenominatorColumn
          : splitDenominatorColumn as int?,
      dateFormat: dateFormat ?? current.dateFormat,
      decimalSeparator: decimalSeparator ?? current.decimalSeparator,
      thousandsSeparator: thousandsSeparator ?? current.thousandsSeparator,
      stripCurrencySymbols:
          stripCurrencySymbols ?? current.stripCurrencySymbols,
    ),
  );
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview});
  final BrokerageImportPreview preview;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          Text('Ready: ${preview.readyCount}'),
          Text('Unresolved: ${preview.unresolvedCount}'),
          Text(
            'Already present: ${preview.count(BrokerageImportClassification.alreadyImported)}',
          ),
          Text(
            'Duplicates: ${preview.count(BrokerageImportClassification.semanticDuplicate) + preview.count(BrokerageImportClassification.possibleDuplicate)}',
          ),
          Text(
            'Invalid: ${preview.count(BrokerageImportClassification.invalid)}',
          ),
        ],
      ),
    ),
  );
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.bookId,
    required this.instruments,
    required this.controller,
  });

  final BrokerageImportDraft draft;
  final String bookId;
  final List<AssetDefinition> instruments;
  final BrokerageImportController controller;

  @override
  Widget build(BuildContext context) {
    final compatible = instruments
        .where(
          (instrument) =>
              !instrument.isDeleted &&
              instrument.bookId == bookId &&
              instrument.normalizedCurrencyCode == draft.currencyCode,
        )
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: draft.included,
                  onChanged: draft.canChangeInclusion
                      ? (value) => controller.setIncluded(
                          draft.sourceRowNumber,
                          value ?? false,
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    'Row ${draft.sourceRowNumber} · ${draft.sourceInstrument.isEmpty ? 'No instrument' : draft.sourceInstrument}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(draft.classification.name),
              ],
            ),
            DropdownButtonFormField<BrokerageActivityType>(
              key: Key('brokerage-row-${draft.sourceRowNumber}-activity'),
              initialValue: draft.activityType,
              decoration: InputDecoration(
                labelText: draft.activityType == null
                    ? 'Activity · UNRESOLVED (${draft.rawActivity})'
                    : 'Activity',
              ),
              items: [
                for (final value in BrokerageActivityType.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.resolveActivity(
                    draft.sourceRowNumber,
                    value,
                    bookId: bookId,
                  );
                }
              },
            ),
            if (draft.needsInstrumentResolution) ...[
              const SizedBox(height: 8),
              Text(
                'Unknown instrument: ${draft.sourceInstrument.isEmpty ? 'blank' : draft.sourceInstrument}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DropdownButton<AssetDefinition>(
                    hint: const Text('Map to existing'),
                    items: [
                      for (final instrument in compatible)
                        DropdownMenuItem(
                          value: instrument,
                          child: Text(instrument.displayName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        controller.mapInstrument(
                          draft.sourceRowNumber,
                          value,
                          bookId: bookId,
                        );
                      }
                    },
                  ),
                  if (draft.sourceInstrument.trim().isNotEmpty)
                    OutlinedButton(
                      key: Key(
                        'brokerage-row-${draft.sourceRowNumber}-create-instrument',
                      ),
                      onPressed: () => controller.createInstrument(
                        draft.sourceRowNumber,
                        bookId: bookId,
                      ),
                      child: Text('Create ${draft.sourceInstrument}'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${draft.currencyCode} ${draft.grossAmount} · '
              '${draft.date.year}-${draft.date.month.toString().padLeft(2, '0')}-${draft.date.day.toString().padLeft(2, '0')}',
            ),
            if (draft.quantity != null)
              Text(
                'Quantity ${draft.quantity} · Price ${draft.executionPrice ?? 0}',
              ),
            if (draft.feeAmount > 0 || draft.taxAmount > 0)
              Text('Fee ${draft.feeAmount} · Tax ${draft.taxAmount}'),
            for (final issue in draft.issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue.message,
                  style: TextStyle(
                    color: issue.blocking
                        ? Theme.of(context).colorScheme.error
                        : violet,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _unchanged = Object();
