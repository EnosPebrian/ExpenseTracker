import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/financial_statement.dart';

class FinancialStatementPdfRenderer {
  const FinancialStatementPdfRenderer();

  Future<Uint8List> render(FinancialStatement statement) async {
    final document = pw.Document(
      title: '${statement.title} - ${statement.period.label}',
      author: 'Pilgrim Tracker',
      creator: 'Pilgrim Tracker',
      subject: statement.scopeLabel,
    );
    final accent = PdfColor.fromInt(0xFF6D54E8);
    final summarizeAnnualAccountLedger =
        statement.type == FinancialStatementType.annual &&
        statement.scope == FinancialStatementScope.account &&
        statement.transactions.length > 1000;
    pw.Widget header(pw.Context context) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'PILGRIM TRACKER',
            style: pw.TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
          pw.Text(
            statement.period.label,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    pw.Widget footer(pw.Context context) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Private financial statement',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 38, 34, 38),
        maxPages: 1000,
        header: header,
        footer: footer,
        build: (context) => [
          pw.SizedBox(height: 18),
          pw.Text(
            statement.title,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '${statement.period.label} - ${statement.scopeLabel}',
            style: pw.TextStyle(fontSize: 12, color: accent),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated ${_dateTime(statement.generatedAt)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          if (statement.localDataWarning) ...[
            pw.SizedBox(height: 10),
            _notice(
              'Statement reflects data currently available on this device.',
            ),
          ],
          pw.SizedBox(height: 18),
          _sectionTitle('Financial summary', accent),
          for (final summary in statement.currencySummaries)
            _currencySummary(summary),
          pw.SizedBox(height: 14),
          _sectionTitle('Account summary', accent),
          _accountTable(statement.accountSummaries),
          if (statement.monthlySummaries.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Month-by-month', accent),
            _monthlyTable(statement.monthlySummaries),
          ],
          if (statement.incomeCategories.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Income by category', accent),
            _categoryTable(statement.incomeCategories),
          ],
          if (statement.expenseCategories.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Expense by category', accent),
            _categoryTable(statement.expenseCategories),
          ],
          if (statement.budgets.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Budget vs actual', accent),
            _budgetTable(statement.budgets),
          ],
          if (statement.yearEndNetWorthNote case final note?) ...[
            pw.SizedBox(height: 14),
            _notice(note),
          ],
          if (statement.transactions.isEmpty) ...[
            pw.SizedBox(height: 16),
            _sectionTitle('Transaction ledger', accent),
            _notice('No transactions during this period.'),
          ],
        ],
      ),
    );
    if (summarizeAnnualAccountLedger) {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 38, 34, 38),
          maxPages: 4,
          header: header,
          footer: footer,
          build: (context) => [
            pw.SizedBox(height: 12),
            _sectionTitle('Transaction ledger summary', accent),
            _notice(
              '${statement.transactions.length} transactions are summarized '
              'by month for this annual account statement. Generate monthly '
              'statements for complete transaction-level ledgers.',
            ),
            pw.SizedBox(height: 10),
            _monthlyTable(statement.monthlySummaries),
          ],
        ),
      );
    }
    // Fixed ledger pages avoid the PDF table layout engine repeatedly scanning
    // a multi-thousand-row table while retaining every transaction.
    const rowsPerPage = 34;
    for (
      var offset = 0;
      !summarizeAnnualAccountLedger && offset < statement.transactions.length;
      offset += rowsPerPage
    ) {
      final end = (offset + rowsPerPage).clamp(
        0,
        statement.transactions.length,
      );
      final rows = statement.transactions.sublist(offset, end);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 38, 34, 38),
          build: (context) => pw.Column(
            children: [
              header(context),
              pw.SizedBox(height: 12),
              _sectionTitle('Transaction ledger', accent),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Rows ${offset + 1}-$end of ${statement.transactions.length}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              _ledgerRows(rows),
              pw.Spacer(),
              footer(context),
            ],
          ),
        ),
      );
    }
    return document.save();
  }

  String suggestedFileName(FinancialStatement statement) {
    final periodType = statement.type == FinancialStatementType.monthly
        ? 'Monthly'
        : 'Annual';
    final scope = statement.scope == FinancialStatementScope.household
        ? ''
        : '_${sanitizeFileSegment(statement.scopeLabel)}';
    return 'PilgrimTracker${scope}_${periodType}_Statement_${statement.period.fileKey}.pdf';
  }

  static String sanitizeFileSegment(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'Account' : cleaned;
  }

  static pw.Widget _sectionTitle(String value, PdfColor accent) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: accent,
      ),
    ),
  );

  static pw.Widget _notice(String value) => pw.Container(
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
  );

  static pw.Widget _currencySummary(
    CurrencyStatementSummary summary,
  ) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 7),
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          summary.currencyCode,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Wrap(
          spacing: 14,
          runSpacing: 5,
          children: [
            _metric('Opening', summary.openingBalance, summary.currencyCode),
            _metric('Income', summary.income, summary.currencyCode),
            _metric('Expense', summary.expense, summary.currencyCode),
            _metric('Net cash flow', summary.netCashFlow, summary.currencyCode),
            _metric('Tithe', summary.tithe, summary.currencyCode),
            _metric('Transfers in', summary.transfersIn, summary.currencyCode),
            _metric(
              'Transfers out',
              summary.transfersOut,
              summary.currencyCode,
            ),
            _metric('Closing', summary.closingBalance, summary.currencyCode),
          ],
        ),
      ],
    ),
  );

  static pw.Widget _metric(String label, int value, String currency) =>
      pw.SizedBox(
        width: 110,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
            pw.Text(
              _money(currency, value),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );

  static pw.Widget _accountTable(List<AccountStatementSummary> rows) => _table(
    headers: const [
      'Account',
      'Currency',
      'Opening',
      'Inflow',
      'Outflow',
      'Transfers',
      'Closing',
    ],
    rows: rows
        .map(
          (row) => [
            row.accountName,
            row.currencyCode,
            _number(row.openingBalance),
            _number(row.inflow),
            _number(row.outflow),
            _number(row.transfersIn - row.transfersOut),
            _number(row.closingBalance),
          ],
        )
        .toList(),
  );

  static pw.Widget _monthlyTable(List<MonthlyStatementSummary> rows) => _table(
    headers: const [
      'Month',
      'Currency',
      'Income',
      'Expense',
      'Net cash flow',
      'Tithe',
    ],
    rows: rows
        .map(
          (row) => [
            StatementPeriod.monthNames[row.month.month - 1],
            row.currencyCode,
            _number(row.income),
            _number(row.expense),
            _number(row.netCashFlow),
            _number(row.tithe),
          ],
        )
        .toList(),
  );

  static pw.Widget _categoryTable(List<CategoryStatementSummary> rows) =>
      _table(
        headers: const [
          'Category',
          'Currency',
          'Amount',
          'Share',
          'Monthly average',
        ],
        rows: rows
            .map(
              (row) => [
                row.category,
                row.currencyCode,
                _number(row.amount),
                '${(row.share * 100).toStringAsFixed(1)}%',
                _number(row.monthlyAverage),
              ],
            )
            .toList(),
      );

  static pw.Widget _budgetTable(List<BudgetStatementSummary> rows) => _table(
    headers: const [
      'Category',
      'Currency',
      'Budget',
      'Actual',
      'Remaining',
      'Usage',
      'Status',
    ],
    rows: rows
        .map(
          (row) => [
            row.category,
            row.currencyCode,
            _number(row.budget),
            _number(row.actual),
            _number(row.remaining),
            '${(row.usage * 100).toStringAsFixed(1)}%',
            row.status,
          ],
        )
        .toList(),
  );

  static pw.Widget _ledgerRows(List<StatementTransactionRow> rows) => pw.Column(
    children: [
      _ledgerRow(const [
        'Date',
        'Account',
        'Description',
        'Category / type',
        'Currency',
        'Amount',
        'Balance',
      ], header: true),
      for (final row in rows)
        _ledgerRow([
          _date(row.date),
          row.account,
          row.description,
          _kind(row),
          row.currencyCode,
          _number(row.balanceEffect),
          row.runningBalance == null ? '' : _number(row.runningBalance!),
        ]),
    ],
  );

  static pw.Widget _ledgerRow(List<String> cells, {bool header = false}) =>
      pw.Container(
        height: 15,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        decoration: pw.BoxDecoration(
          color: header ? PdfColors.grey200 : null,
          border: const pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey300, width: .35),
          ),
        ),
        child: pw.Row(
          children: [
            for (var index = 0; index < cells.length; index++)
              pw.Expanded(
                flex: const [9, 13, 22, 17, 8, 12, 13][index],
                child: pw.Text(
                  cells[index],
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: header ? pw.FontWeight.bold : null,
                  ),
                ),
              ),
          ],
        ),
      );

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    double fontSize = 8,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    headerStyle: pw.TextStyle(
      fontSize: fontSize,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: pw.TextStyle(fontSize: fontSize),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .4),
      bottom: pw.BorderSide(color: PdfColors.grey400, width: .5),
    ),
  );

  static String _kind(StatementTransactionRow row) => switch (row.kind) {
    StatementTransactionKind.income => row.category,
    StatementTransactionKind.expense => row.category,
    StatementTransactionKind.transferIn => 'Transfer in',
    StatementTransactionKind.transferOut => 'Transfer out',
    StatementTransactionKind.legacyTransfer => 'Legacy transfer',
    StatementTransactionKind.assetMovement => 'Asset movement',
  };

  static String _money(String currency, int value) =>
      '$currency ${_number(value)}';

  static String _number(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _dateTime(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
