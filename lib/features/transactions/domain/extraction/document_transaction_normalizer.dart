import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../import/csv_value_parsers.dart';
import '../import/transaction_import_models.dart';
import 'document_extraction_models.dart';

class DocumentSourceFingerprint {
  const DocumentSourceFingerprint._();

  static Future<String> calculate(
    FinancialDocumentType type,
    List<FinancialDocumentSource> sources,
  ) async {
    if (sources.length == 1) {
      return _digest(sources.single.bytes);
    }
    final bytes = <int>[...utf8.encode(type.name), 0];
    for (final source in sources) {
      bytes
        ..addAll(_length(source.bytes.length))
        ..addAll(source.bytes);
    }
    return _digest(bytes);
  }

  static Future<String> _digest(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static List<int> _length(int value) => [
    value >> 24 & 0xff,
    value >> 16 & 0xff,
    value >> 8 & 0xff,
    value & 0xff,
  ];
}

class DocumentTransactionNormalizer {
  const DocumentTransactionNormalizer();

  static const headers = [
    'date',
    'description',
    'amount',
    'type',
    'category',
    'reference',
    'note',
  ];

  CsvParsedSource receipt({
    required ReceiptExtraction extraction,
    required String sourceFingerprint,
  }) {
    final merchant = extraction.merchant?.trim();
    final note = <String>[
      if (extraction.tax case final value?) 'Tax: $value',
      if (extraction.serviceCharge case final value?) 'Service: $value',
      if (extraction.discount case final value?) 'Discount: $value',
      if (extraction.documentType == 'invoice')
        'Confirm this invoice was paid before saving.',
    ].join(' · ');
    return CsvParsedSource(
      fileName: 'Receipt / invoice',
      fileFingerprint: sourceFingerprint,
      delimiter: ',',
      headers: headers,
      rows: [
        CsvSourceRow(
          rowNumber: 1,
          identityKey: 'receipt',
          merchantHint: merchant,
          values: [
            extraction.date ?? '',
            merchant == null || merchant.isEmpty ? 'Receipt expense' : merchant,
            extraction.total ?? '',
            'expense',
            '',
            extraction.reference ?? '',
            note,
          ],
        ),
      ],
      headerMode: CsvHeaderMode.firstRowHeaders,
    );
  }

  CsvParsedSource statement({
    required BankStatementExtraction extraction,
    required String sourceFingerprint,
  }) {
    final ordered = [...extraction.transactions]
      ..sort((a, b) {
        final page = (a.pageNumber ?? a.sourceIndex).compareTo(
          b.pageNumber ?? b.sourceIndex,
        );
        return page != 0 ? page : a.sourceIndex.compareTo(b.sourceIndex);
      });
    final occurrences = <String, int>{};
    final rows = <CsvSourceRow>[];
    for (var index = 0; index < ordered.length; index++) {
      final row = ordered[index];
      final date = row.transactionDate ?? row.postingDate ?? '';
      final description = _normalizeWhitespace(row.description);
      final canonical = [
        date,
        description.toLowerCase(),
        row.amount.trim(),
        row.direction,
        row.reference?.trim() ?? '',
      ].join('|');
      final occurrence = occurrences.update(
        canonical,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      rows.add(
        CsvSourceRow(
          rowNumber: index + 1,
          identityKey: '$canonical#$occurrence',
          values: [
            date,
            description,
            row.amount,
            row.direction == 'debit' ? 'expense' : 'income',
            '',
            row.reference ?? '',
            row.transactionDate == null && row.postingDate != null
                ? 'Posting date used; transaction date was unavailable.'
                : '',
          ],
        ),
      );
    }
    return CsvParsedSource(
      fileName: 'Bank statement',
      fileFingerprint: sourceFingerprint,
      delimiter: ',',
      headers: headers,
      rows: rows,
      headerMode: CsvHeaderMode.firstRowHeaders,
    );
  }

  static String _normalizeWhitespace(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class BankStatementReconciliation {
  const BankStatementReconciliation({
    required this.status,
    required this.debitTotal,
    required this.creditTotal,
    required this.expectedClosingBalance,
    required this.runningBalanceWarnings,
  });

  final BankStatementReconciliationStatus status;
  final int debitTotal;
  final int creditTotal;
  final int? expectedClosingBalance;
  final List<String> runningBalanceWarnings;

  static BankStatementReconciliation calculate(
    BankStatementExtraction extraction, {
    required String currencyCode,
    CsvMoneyParser parser = const CsvMoneyParser(),
  }) {
    int parse(String value) => parser.parse(
      value,
      currencyCode: currencyCode,
      decimalSeparator: CsvSeparator.period,
      thousandsSeparator: CsvSeparator.comma,
      stripCurrencySymbols: true,
      allowZero: true,
    );

    var debits = 0;
    var credits = 0;
    for (final row in extraction.transactions) {
      final amount = parse(row.amount).abs();
      row.direction == 'debit' ? debits += amount : credits += amount;
    }
    final opening = extraction.openingBalance;
    final closing = extraction.closingBalance;
    final expected = opening == null ? null : parse(opening) + credits - debits;
    final status = opening == null || closing == null
        ? BankStatementReconciliationStatus.insufficientInformation
        : expected == parse(closing)
        ? BankStatementReconciliationStatus.reconciled
        : BankStatementReconciliationStatus.mismatch;

    final runningWarnings = <String>[];
    int? previous;
    for (final row in extraction.transactions) {
      final running = row.runningBalance;
      if (running == null) continue;
      final current = parse(running);
      if (previous != null) {
        final amount = parse(row.amount).abs();
        final expectedRunning = row.direction == 'debit'
            ? previous - amount
            : previous + amount;
        if (expectedRunning != current) {
          runningWarnings.add(
            'Running balance differs at row ${row.sourceIndex}.',
          );
        }
      }
      previous = current;
    }
    return BankStatementReconciliation(
      status: status,
      debitTotal: debits,
      creditTotal: credits,
      expectedClosingBalance: expected,
      runningBalanceWarnings: runningWarnings,
    );
  }
}
