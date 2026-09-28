import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/csv_export_service.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_date_detection.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/data/csv_transaction_source_parser.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/csv_date_column_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/csv_value_parsers.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/import/csv_date_format_help.dart';
import 'support/beta06_fixture.dart';

Future<TransactionImportPreview> plan(
  List<String> dates, {
  CsvDateFormat format = CsvDateFormat.automatic,
}) async {
  final source = await const CsvTransactionSourceParser().parse(
    SelectedCsvFile(
      name: 'dates.csv',
      bytes: utf8.encode(
        'date,description,amount,type\n${dates.map((d) => '$d,Example,100,expense').join('\n')}',
      ),
    ),
  );
  return const TransactionImportPlanner().build(
    source: source,
    mapping: TransactionImportMapping(
      dateColumn: 0,
      descriptionColumn: 1,
      amountColumn: 2,
      typeColumn: 3,
      dateFormat: format,
    ),
    account: Account(id: 'a', bookId: 'b', name: 'Cash'),
    activeBookId: 'b',
    existingTransactions: const [],
    expenseCategories: const [],
    incomeCategories: const [],
  );
}

void main() {
  for (final fixture in [
    (['2026-02-01', '2026-02-13'], CsvDateFormat.yyyyMmDd),
    (['01/02/2026', '13/02/2026'], CsvDateFormat.ddMmYyyySlash),
    (['02/01/2026', '02/13/2026'], CsvDateFormat.mmDdYyyySlash),
  ]) {
    test(
      'whole column ${fixture.$2.name} shared by ordinary and brokerage',
      () async {
        expect(CsvDateColumnPolicy.detect(fixture.$1), fixture.$2);
        expect(BrokerageDateDetection.detect(fixture.$1), fixture.$2);
        final preview = await plan(fixture.$1);
        expect(
          preview.drafts.every((d) => d.issues.every((i) => !i.blocking)),
          isTrue,
        );
        expect(preview.drafts.map((d) => d.date), [
          DateTime(2026, 2, 1),
          DateTime(2026, 2, 13),
        ]);
        final explicit = await plan(fixture.$1, format: fixture.$2);
        expect(
          preview.drafts.map((d) => d.transactionId),
          explicit.drafts.map((d) => d.transactionId),
        );
      },
    );
  }
  test('ambiguous column blocks until one explicit session choice', () async {
    const dates = ['01/02/2026', '03/04/2026'];
    expect(CsvDateColumnPolicy.detect(dates), isNull);
    final blocked = await plan(dates);
    expect(blocked.readyCount, 0);
    expect(
      blocked.drafts.every(
        (d) => d.issues.any((i) => i.message.contains('ambiguous')),
      ),
      isTrue,
    );
    final resolved = await plan(dates, format: CsvDateFormat.mmDdYyyySlash);
    expect(resolved.drafts.map((d) => d.date), [
      DateTime(2026, 1, 2),
      DateTime(2026, 3, 4),
    ]);
    expect(
      resolved.drafts.map((d) => d.transactionId),
      blocked.drafts.map((d) => d.transactionId),
    );
  });
  for (final dates in [
    ['2026-02-01', '13/02/2026'],
    ['13/02/2026', '02/14/2026'],
    ['2026-02-30'],
    ['not a date'],
  ]) {
    test('invalid or mixed column blocks: $dates', () async {
      expect(CsvDateColumnPolicy.detect(dates), isNull);
      final preview = await plan(dates);
      expect(preview.readyCount, 0);
      expect(
        preview.drafts.every(
          (d) => d.classification == TransactionImportClassification.invalid,
        ),
        isTrue,
      );
    });
  }
  test('leap years are validated, ISO shape alone is insufficient', () {
    expect(CsvDateColumnPolicy.detect(['2024-02-29']), CsvDateFormat.yyyyMmDd);
    expect(CsvDateColumnPolicy.detect(['2026-02-29']), isNull);
    expect(BrokerageDateDetection.detect(['2026-02-29']), isNull);
  });
  test(
    'blank values do not decide format and required blank rows still block',
    () async {
      expect(
        CsvDateColumnPolicy.detect([' ', '13/02/2026']),
        CsvDateFormat.ddMmYyyySlash,
      );
      final preview = await plan(['', '13/02/2026']);
      expect(
        preview.drafts.first.classification,
        TransactionImportClassification.invalid,
      );
      expect(preview.drafts.last.date, DateTime(2026, 2, 13));
    },
  );
  test('other existing explicit formats remain supported', () {
    const parser = CsvTransactionDateParser();
    for (final pair in [
      ('2026/02/13', CsvDateFormat.yyyyMmDdSlash),
      ('13-02-2026', CsvDateFormat.ddMmYyyyDash),
      ('13 Feb 2026', CsvDateFormat.ddMmmYyyy),
      ('13 February 2026', CsvDateFormat.ddMmmmYyyy),
    ]) {
      expect(parser.parse(pair.$1, pair.$2), DateTime(2026, 2, 13));
    }
  });
  test(
    'generated transaction CSV uses ISO calendar dates and round-trips',
    () async {
      final snapshot = beta06Snapshot();
      final bundle = const CsvExportService().create(
        snapshot,
        const CsvExportFilter(),
      );
      final file = ZipDecoder()
          .decodeBytes(bundle.bytes)
          .files
          .singleWhere((f) => f.name == 'transactions.csv');
      final source = await const CsvTransactionSourceParser().parse(
        SelectedCsvFile(name: file.name, bytes: file.readBytes()!),
      );
      final dates = source.rows
          .map((r) => r.values[source.headers.indexOf('date')])
          .toList();
      expect(CsvDateColumnPolicy.detect(dates), CsvDateFormat.yyyyMmDd);
      expect(
        dates.every((d) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)),
        isTrue,
      );
      expect(
        dates,
        snapshot['transactions']!.map(
          (r) => DateTime.fromMillisecondsSinceEpoch(
            r['transaction_date'] as int,
          ).toIso8601String().split('T').first,
        ),
      );
      expect(
        source.rows.first.values[source.headers.indexOf('created_at')],
        contains('T'),
      );
    },
  );
  testWidgets(
    'one session-level explanation shows both ambiguous interpretations',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CsvDateFormatHelp(
              values: ['01/02/2026'],
              format: CsvDateFormat.automatic,
            ),
          ),
        ),
      );
      expect(find.textContaining('once for this import'), findsOneWidget);
      expect(find.textContaining('2026-02-01'), findsOneWidget);
      expect(find.textContaining('2026-01-02'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CsvDateFormatHelp(
              values: ['2026-02-01'],
              format: CsvDateFormat.automatic,
            ),
          ),
        ),
      );
      expect(find.textContaining('ambiguous'), findsNothing);
      expect(find.textContaining('Detected: YYYY-MM-DD (ISO)'), findsOneWidget);
    },
  );
}
