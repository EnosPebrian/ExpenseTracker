import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../domain/financial_statement.dart';
import '../controllers/financial_statement_controller.dart';

class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key, required this.controller});

  final FinancialStatementController controller;

  static Future<void> show(
    BuildContext context,
    FinancialStatementController controller,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StatementsScreen(controller: controller),
      ),
    );
    controller.dispose();
  }

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  FinancialStatementController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Financial Statements')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Monthly & Annual Statements',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Generate a deterministic statement from financial data stored on this device.',
          ),
          const SizedBox(height: 18),
          _StatementControls(controller: controller),
          if (controller.error case final error?) ...[
            const SizedBox(height: 12),
            Text(error, style: const TextStyle(color: Colors.red)),
          ],
          if (controller.statement case final statement?) ...[
            const SizedBox(height: 20),
            _StatementPreview(statement: statement),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('statement-export-pdf'),
                onPressed: controller.exporting ? null : controller.exportPdf,
                icon: controller.exporting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              ),
            ),
          ],
          if (controller.lastSave case final saved?) ...[
            const SizedBox(height: 10),
            Text(
              'Saved ${saved.fileName} to ${saved.destinationDisplayValue}.',
            ),
          ],
        ],
      ),
    );
  }
}

class _StatementControls extends StatelessWidget {
  const _StatementControls({required this.controller});

  final FinancialStatementController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = constraints.maxWidth >= 760
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statement setup',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: SegmentedButton<FinancialStatementType>(
                        key: const Key('statement-type-selector'),
                        segments: const [
                          ButtonSegment(
                            value: FinancialStatementType.monthly,
                            label: Text('Monthly'),
                          ),
                          ButtonSegment(
                            value: FinancialStatementType.annual,
                            label: Text('Annual'),
                          ),
                        ],
                        selected: {controller.type},
                        onSelectionChanged: (values) =>
                            controller.setType(values.single),
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: SegmentedButton<FinancialStatementScope>(
                        key: const Key('statement-scope-selector'),
                        segments: const [
                          ButtonSegment(
                            value: FinancialStatementScope.household,
                            label: Text('Household'),
                          ),
                          ButtonSegment(
                            value: FinancialStatementScope.account,
                            label: Text('Account'),
                          ),
                        ],
                        selected: {controller.scope},
                        onSelectionChanged: (values) =>
                            controller.setScope(values.single),
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: Row(
                        children: [
                          if (controller.type == FinancialStatementType.monthly)
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: const Key('statement-month-selector'),
                                initialValue: controller.selectedPeriod.month,
                                decoration: const InputDecoration(
                                  labelText: 'Month',
                                ),
                                isExpanded: true,
                                items: [
                                  for (var month = 1; month <= 12; month++)
                                    DropdownMenuItem(
                                      value: month,
                                      child: Text(
                                        StatementPeriod.monthNames[month - 1],
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) controller.setMonth(value);
                                },
                              ),
                            ),
                          if (controller.type == FinancialStatementType.monthly)
                            const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: const Key('statement-year-selector'),
                              initialValue: controller.selectedPeriod.year,
                              decoration: const InputDecoration(
                                labelText: 'Year',
                              ),
                              isExpanded: true,
                              items: [
                                for (final year in controller.availableYears)
                                  DropdownMenuItem(
                                    value: year,
                                    child: Text('$year'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) controller.setYear(value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.scope == FinancialStatementScope.account)
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String>(
                          key: const Key('statement-account-selector'),
                          initialValue: controller.selectedAccountId,
                          decoration: const InputDecoration(
                            labelText: 'Account',
                          ),
                          isExpanded: true,
                          items: [
                            for (final account in controller.selectableAccounts)
                              DropdownMenuItem(
                                value: account.id,
                                child: Text(
                                  '${account.name} (${account.currencyCode})',
                                ),
                              ),
                          ],
                          onChanged: controller.setAccount,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('statement-generate'),
                  onPressed: controller.generating ? null : controller.generate,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Generate Statement'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatementPreview extends StatelessWidget {
  const _StatementPreview({required this.statement});

  final FinancialStatement statement;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('statement-preview'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statement.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text('${statement.period.label} - ${statement.scopeLabel}'),
            if (statement.localDataWarning) ...[
              const SizedBox(height: 10),
              const _InfoBanner(
                text:
                    'Statement reflects data currently available on this device.',
              ),
            ],
            const SizedBox(height: 16),
            for (final summary in statement.currencySummaries)
              _CurrencySummaryCard(summary: summary),
            if (statement.isEmpty) ...[
              const SizedBox(height: 12),
              const _InfoBanner(text: 'No transactions during this period.'),
            ],
            const SizedBox(height: 16),
            _Section(
              title: 'Accounts',
              child: _AccountSummaryTable(rows: statement.accountSummaries),
            ),
            if (statement.monthlySummaries.isNotEmpty)
              _Section(
                title: 'Month-by-month',
                child: _MonthlySummaryTable(rows: statement.monthlySummaries),
              ),
            if (statement.incomeCategories.isNotEmpty)
              _Section(
                title: 'Income by category',
                child: _CategoryTable(rows: statement.incomeCategories),
              ),
            if (statement.expenseCategories.isNotEmpty)
              _Section(
                title: 'Expense by category',
                child: _CategoryTable(rows: statement.expenseCategories),
              ),
            if (statement.budgets.isNotEmpty)
              _Section(
                title: 'Budget vs actual',
                child: _BudgetTable(rows: statement.budgets),
              ),
            if (statement.yearEndNetWorthNote case final note?)
              _InfoBanner(text: note),
            const SizedBox(height: 16),
            Text(
              'Transaction ledger',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (statement.transactions.isNotEmpty)
              _LedgerTable(rows: statement.transactions.take(200).toList()),
            if (statement.transactions.length > 200)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Preview shows 200 of ${statement.transactions.length} rows. The PDF includes the complete ledger.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrencySummaryCard extends StatelessWidget {
  const _CurrencySummaryCard({required this.summary});
  final CurrencyStatementSummary summary;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F7FC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.currencyCode,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            _Metric('Opening', summary.openingBalance, summary.currencyCode),
            _Metric('Income', summary.income, summary.currencyCode),
            _Metric('Expense', summary.expense, summary.currencyCode),
            _Metric('Net cash flow', summary.netCashFlow, summary.currencyCode),
            _Metric('Tithe', summary.tithe, summary.currencyCode),
            _Metric('Transfers in', summary.transfersIn, summary.currencyCode),
            _Metric(
              'Transfers out',
              summary.transfersOut,
              summary.currencyCode,
            ),
            _Metric('Closing', summary.closingBalance, summary.currencyCode),
          ],
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.currency);
  final String label;
  final int value;
  final String currency;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          '$currency ${money(value)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF1EEFF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text),
  );
}

Widget _scrollingTable(DataTable table) =>
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);

class _AccountSummaryTable extends StatelessWidget {
  const _AccountSummaryTable({required this.rows});
  final List<AccountStatementSummary> rows;

  @override
  Widget build(BuildContext context) => _scrollingTable(
    DataTable(
      columns: const [
        DataColumn(label: Text('Account')),
        DataColumn(label: Text('Currency')),
        DataColumn(label: Text('Opening')),
        DataColumn(label: Text('Inflow')),
        DataColumn(label: Text('Outflow')),
        DataColumn(label: Text('Transfers')),
        DataColumn(label: Text('Closing')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(row.accountName)),
              DataCell(Text(row.currencyCode)),
              DataCell(Text(money(row.openingBalance))),
              DataCell(Text(money(row.inflow))),
              DataCell(Text(money(row.outflow))),
              DataCell(Text(money(row.transfersIn - row.transfersOut))),
              DataCell(Text(money(row.closingBalance))),
            ],
          ),
      ],
    ),
  );
}

class _MonthlySummaryTable extends StatelessWidget {
  const _MonthlySummaryTable({required this.rows});
  final List<MonthlyStatementSummary> rows;

  @override
  Widget build(BuildContext context) => _scrollingTable(
    DataTable(
      columns: const [
        DataColumn(label: Text('Month')),
        DataColumn(label: Text('Currency')),
        DataColumn(label: Text('Income')),
        DataColumn(label: Text('Expense')),
        DataColumn(label: Text('Net')),
        DataColumn(label: Text('Tithe')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(StatementPeriod.monthNames[row.month.month - 1])),
              DataCell(Text(row.currencyCode)),
              DataCell(Text(money(row.income))),
              DataCell(Text(money(row.expense))),
              DataCell(Text(money(row.netCashFlow))),
              DataCell(Text(money(row.tithe))),
            ],
          ),
      ],
    ),
  );
}

class _CategoryTable extends StatelessWidget {
  const _CategoryTable({required this.rows});
  final List<CategoryStatementSummary> rows;

  @override
  Widget build(BuildContext context) => _scrollingTable(
    DataTable(
      columns: const [
        DataColumn(label: Text('Category')),
        DataColumn(label: Text('Currency')),
        DataColumn(label: Text('Amount')),
        DataColumn(label: Text('Share')),
        DataColumn(label: Text('Monthly average')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(row.category)),
              DataCell(Text(row.currencyCode)),
              DataCell(Text(money(row.amount))),
              DataCell(Text('${(row.share * 100).toStringAsFixed(1)}%')),
              DataCell(Text(money(row.monthlyAverage))),
            ],
          ),
      ],
    ),
  );
}

class _BudgetTable extends StatelessWidget {
  const _BudgetTable({required this.rows});
  final List<BudgetStatementSummary> rows;

  @override
  Widget build(BuildContext context) => _scrollingTable(
    DataTable(
      columns: const [
        DataColumn(label: Text('Category')),
        DataColumn(label: Text('Currency')),
        DataColumn(label: Text('Budget')),
        DataColumn(label: Text('Actual')),
        DataColumn(label: Text('Remaining')),
        DataColumn(label: Text('Usage')),
        DataColumn(label: Text('Status')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(row.category)),
              DataCell(Text(row.currencyCode)),
              DataCell(Text(money(row.budget))),
              DataCell(Text(money(row.actual))),
              DataCell(Text(money(row.remaining))),
              DataCell(Text('${(row.usage * 100).toStringAsFixed(1)}%')),
              DataCell(Text(row.status)),
            ],
          ),
      ],
    ),
  );
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.rows});
  final List<StatementTransactionRow> rows;

  @override
  Widget build(BuildContext context) => _scrollingTable(
    DataTable(
      columns: const [
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Account')),
        DataColumn(label: Text('Description')),
        DataColumn(label: Text('Category / type')),
        DataColumn(label: Text('Currency')),
        DataColumn(label: Text('Movement')),
        DataColumn(label: Text('Running balance')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_date(row.date))),
              DataCell(Text(row.account)),
              DataCell(Text(row.description)),
              DataCell(Text(_kind(row.kind, row.category))),
              DataCell(Text(row.currencyCode)),
              DataCell(Text(money(row.balanceEffect))),
              DataCell(
                Text(
                  row.runningBalance == null ? '—' : money(row.runningBalance!),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _kind(StatementTransactionKind kind, String fallback) =>
      switch (kind) {
        StatementTransactionKind.income => fallback,
        StatementTransactionKind.expense => fallback,
        StatementTransactionKind.transferIn => 'Transfer in',
        StatementTransactionKind.transferOut => 'Transfer out',
        StatementTransactionKind.legacyTransfer => 'Legacy transfer',
        StatementTransactionKind.assetMovement => 'Asset movement',
      };
}
