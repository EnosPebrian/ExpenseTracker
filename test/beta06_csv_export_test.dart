import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/csv_export_service.dart';

import 'support/beta06_fixture.dart';

void main() {
  const service = CsvExportService();

  test('CSV ZIP contains normalized files and neutralizes formulas', () {
    final bundle = service.create(beta06Snapshot(), const CsvExportFilter());
    final archive = ZipDecoder().decodeBytes(bundle.bytes, verify: true);
    final rawFiles = {
      for (final file in archive.files.where((file) => file.isFile))
        file.name: file.readBytes()!,
    };
    final files = rawFiles.map(
      (name, bytes) => MapEntry(name, utf8.decode(bytes)),
    );

    expect(bundle.recordCount, 2);
    expect(
      files.keys,
      containsAll(const [
        'household.csv',
        'members.csv',
        'accounts.csv',
        'categories.csv',
        'projects.csv',
        'asset_definitions.csv',
        'transactions.csv',
        'asset_activity.csv',
        'summary.csv',
        'README.txt',
      ]),
    );
    expect(rawFiles['transactions.csv']!.take(3), [0xEF, 0xBB, 0xBF]);
    expect(files['transactions.csv'], contains("'=SUM(A1:A2)"));
    expect(files['transactions.csv'], contains('2500000'));
    expect(files['README.txt'], contains('not a full application backup'));
  });

  test('CSV filters date, type, project, member, account and category', () {
    final snapshot = beta06Snapshot();
    final filtered = service.create(
      snapshot,
      CsvExportFilter(
        startDate: DateTime(2026, 7, 29),
        endDateInclusive: DateTime(2026, 7, 29),
        transactionTypes: const {'expense'},
        accountId: 'account-cash',
        categoryId: 'category-expense',
        projectId: 'project-home',
        memberId: 'member-owner',
      ),
    );
    expect(filtered.recordCount, 1);
  });

  test('CSV escapes punctuation and preserves exact asset quantity', () {
    final snapshot = beta06Snapshot();
    snapshot['transactions']![1]['title'] = 'Line, one\n"quoted"';
    snapshot['transactions']!.add({
      ...snapshot['transactions']!.first,
      'id': 'asset-activity',
      'title': 'Gold purchase',
      'transaction_type': 'assetConversion',
      'category': '',
      'account': 'Cash -> Gold',
      'amount': 1000000,
      'asset_definition_id': 'asset-gold',
      'asset_action': 'buy',
      'quantity': 0.12345678,
      'unit': 'gram',
      'unit_price': 8100000,
      'fee_amount': 0,
    });

    final archive = ZipDecoder().decodeBytes(
      service.create(snapshot, const CsvExportFilter()).bytes,
      verify: true,
    );
    String content(String name) => utf8.decode(
      archive.files.singleWhere((file) => file.name == name).readBytes()!,
    );

    expect(content('transactions.csv'), contains('"Line, one\n""quoted"""'));
    expect(content('asset_activity.csv'), contains('0.12345678'));
  });

  test('deleted rows are excluded unless explicitly requested', () {
    final snapshot = beta06Snapshot();
    snapshot['transactions']!.first['deleted_at'] = 1;

    expect(service.create(snapshot, const CsvExportFilter()).recordCount, 1);
    expect(
      service
          .create(snapshot, const CsvExportFilter(includeDeleted: true))
          .recordCount,
      2,
    );
  });

  test('missing historical category does not omit the transaction', () {
    final snapshot = beta06Snapshot();
    snapshot['transactions']!.first['category'] = 'Removed category';
    final archive = ZipDecoder().decodeBytes(
      service.create(snapshot, const CsvExportFilter()).bytes,
      verify: true,
    );
    final csv = utf8.decode(
      archive.files
          .singleWhere((file) => file.name == 'transactions.csv')
          .readBytes()!,
    );
    expect(csv, contains('transaction-income'));
    expect(csv, contains(',Cash,,Removed category,'));
    expect(service.create(snapshot, const CsvExportFilter()).recordCount, 2);
  });

  test('soft-deleted category remains resolvable in CSV', () {
    final snapshot = beta06Snapshot();
    snapshot['categories']!.first['deleted_at'] = 2;
    final archive = ZipDecoder().decodeBytes(
      service
          .create(snapshot, const CsvExportFilter(includeDeleted: true))
          .bytes,
      verify: true,
    );
    final csv = utf8.decode(
      archive.files
          .singleWhere((file) => file.name == 'transactions.csv')
          .readBytes()!,
    );
    expect(csv, contains(',category-income,Salary,'));
  });
}
