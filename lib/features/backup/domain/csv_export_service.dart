import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'backup_models.dart';
import 'household_backup_integrity.dart';

class CsvExportService {
  const CsvExportService();

  int estimateTransactionCount(
    Map<String, List<Map<String, Object?>>> snapshot,
    CsvExportFilter filter,
  ) => _filteredTransactions(snapshot, filter).length;

  CreatedCsvBundle create(
    Map<String, List<Map<String, Object?>>> source,
    CsvExportFilter filter,
  ) {
    final snapshot = HouseholdBackupIntegrity.sanitize(source);
    HouseholdBackupIntegrity.validate(snapshot);
    final transactions = _filteredTransactions(snapshot, filter);
    final visible = <String, List<Map<String, Object?>>>{
      for (final entry in snapshot.entries)
        entry.key: filter.includeDeleted
            ? entry.value
            : entry.value
                  .where((record) => record['deleted_at'] == null)
                  .toList(growable: false),
      'transactions': transactions,
    };

    final files = <String, Uint8List>{
      'household.csv': _csv(
        const [
          'book_id',
          'name',
          'base_currency_code',
          'created_at',
          'updated_at',
          'deleted_at',
          'version',
        ],
        visible['household']!.map(
          (row) => [
            _text(row['id']),
            _text(row['name']),
            _text(row['base_currency_code']),
            _date(row['created_at']),
            _date(row['updated_at']),
            _date(row['deleted_at']),
            _raw(row['version']),
          ],
        ),
      ),
      'members.csv': _entityCsv(visible['members']!, const [
        'id',
        'book_id',
        'display_name',
        'role',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
      ]),
      'accounts.csv': _entityCsv(visible['accounts']!, const [
        'id',
        'book_id',
        'owner_member_id',
        'name',
        'account_type',
        'currency_code',
        'opening_balance',
        'opening_balance_date',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
      ]),
      'categories.csv': _entityCsv(visible['categories']!, const [
        'id',
        'book_id',
        'name',
        'category_type',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
      ]),
      'projects.csv': _entityCsv(visible['projects']!, const [
        'id',
        'book_id',
        'name',
        'status',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
      ]),
      'asset_definitions.csv': _entityCsv(visible['asset_definitions']!, const [
        'id',
        'book_id',
        'display_name',
        'asset_kind',
        'symbol',
        'provider_code',
        'provider_symbol',
        'exchange_code',
        'currency_code',
        'unit',
        'lot_size',
        'online_pricing_enabled',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
      ]),
      'budgets.csv': _budgetsCsv(visible, visible['budgets']!),
      'transactions.csv': _transactionsCsv(visible, transactions),
      'transfer_links.csv': _entityCsv(visible['transfer_links']!, const [
        'id',
        'book_id',
        'outgoing_transaction_id',
        'incoming_transaction_id',
        'source_account_id',
        'destination_account_id',
        'currency_code',
        'amount',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
      ]),
      'asset_activity.csv': _assetActivityCsv(transactions),
      'summary.csv': _summaryCsv(
        transactions,
        visible['transfer_links']!,
        visible['budgets']!,
        filter,
      ),
      'README.txt': Uint8List.fromList(
        utf8.encode(
          'Pilgrim Tracker CSV export\r\n\r\n'
          'This ZIP is a human-readable data export, not a full application '
          'backup. Use an encrypted .ptbackup file for disaster recovery.\r\n'
          'CSV files are UTF-8 with a BOM for reliable Excel detection. '
          'Dates use ISO-8601 and money remains exact integer minor units.\r\n'
          'User-entered text beginning with =, +, -, or @ is prefixed with an '
          'apostrophe to prevent spreadsheet formula execution.\r\n',
        ),
      ),
    };

    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return CreatedCsvBundle(
      bytes: ZipEncoder().encodeBytes(archive),
      recordCount: transactions.length,
    );
  }

  static Uint8List _transactionsCsv(
    Map<String, List<Map<String, Object?>>> snapshot,
    List<Map<String, Object?>> transactions,
  ) {
    const headers = [
      'transaction_id',
      'book_id',
      'date',
      'type',
      'description',
      'amount_minor',
      'amount_display',
      'currency_code',
      'account_id',
      'account_name',
      'category_id',
      'category_name',
      'project_id',
      'project_name',
      'entered_by_member_id',
      'entered_by_name',
      'related_transaction_id',
      'transfer_link_id',
      'transfer_direction',
      'fee_amount_minor',
      'fee_treatment',
      'asset_definition_id',
      'asset_symbol',
      'asset_quantity',
      'asset_unit_price',
      'deleted_at',
      'created_at',
      'updated_at',
      'version',
    ];
    final accounts = _byName(snapshot['accounts']!, 'name');
    final categories = _byName(snapshot['categories']!, 'name');
    final projects = _byId(snapshot['projects']!);
    final members = _byId(snapshot['members']!);
    final household = snapshot['household']!.single;
    final currency = household['base_currency_code'];
    final transferByTransactionId = <String, (String, String)>{};
    for (final link in snapshot['transfer_links']!) {
      if (link['deleted_at'] != null) continue;
      final id = link['id'] as String;
      transferByTransactionId[link['outgoing_transaction_id'] as String] = (
        id,
        'outgoing',
      );
      transferByTransactionId[link['incoming_transaction_id'] as String] = (
        id,
        'incoming',
      );
    }

    return _csv(
      headers,
      transactions.map((row) {
        final accountName = _cashAccount(row);
        final account = accounts[accountName.toLowerCase()];
        final categoryName = row['category']?.toString() ?? '';
        final category = categories[categoryName.toLowerCase()];
        final project = projects[row['project_id']];
        final member = members[row['entered_by_member_id']];
        final amount = (row['amount'] as int?) ?? 0;
        final transfer = transferByTransactionId[row['id']];
        return [
          _text(row['id']),
          _text(row['book_id']),
          _date(row['transaction_date']),
          _raw(row['transaction_type']),
          _text(row['title']),
          _raw(amount),
          _raw(amount),
          _text(currency),
          _text(account?['id']),
          _text(accountName),
          _text(category?['id']),
          _text(categoryName),
          _text(row['project_id']),
          _text(project?['name']),
          _text(row['entered_by_member_id']),
          _text(member?['display_name']),
          _text(row['related_transaction_id']),
          _text(transfer?.$1),
          _text(transfer?.$2),
          _raw(row['fee_amount'] ?? 0),
          _raw(row['fee_treatment'] ?? 'none'),
          _text(row['asset_definition_id']),
          _text(row['asset_symbol']),
          _raw(_exactDecimal(row['quantity'])),
          _raw(row['unit_price']),
          _date(row['deleted_at']),
          _date(row['created_at']),
          _date(row['updated_at']),
          _raw(row['version']),
        ];
      }),
    );
  }

  static Uint8List _assetActivityCsv(List<Map<String, Object?>> transactions) =>
      _csv(
        const [
          'transaction_id',
          'date',
          'action',
          'asset_definition_id',
          'asset_name',
          'asset_symbol',
          'quantity',
          'unit',
          'unit_price_minor',
          'gross_amount_minor',
          'fee_amount_minor',
          'fee_treatment',
          'deleted_at',
        ],
        transactions
            .where((row) => row['transaction_type'] == 'assetConversion')
            .map(
              (row) => [
                _text(row['id']),
                _date(row['transaction_date']),
                _raw(row['asset_action']),
                _text(row['asset_definition_id']),
                _text(row['asset_name']),
                _text(row['asset_symbol']),
                _raw(_exactDecimal(row['quantity'])),
                _text(row['unit']),
                _raw(row['unit_price']),
                _raw(row['amount']),
                _raw(row['fee_amount'] ?? 0),
                _raw(row['fee_treatment'] ?? 'none'),
                _date(row['deleted_at']),
              ],
            ),
      );

  static Uint8List _budgetsCsv(
    Map<String, List<Map<String, Object?>>> snapshot,
    List<Map<String, Object?>> budgets,
  ) {
    final categories = _byId(snapshot['categories']!);
    final ordered = budgets.map(Map<String, Object?>.of).toList()
      ..sort((left, right) {
        final month = (left['month_start'] as String).compareTo(
          right['month_start'] as String,
        );
        if (month != 0) return month;
        final category = (left['category_id'] as String).compareTo(
          right['category_id'] as String,
        );
        return category != 0
            ? category
            : (left['id'] as String).compareTo(right['id'] as String);
      });
    return _csv(
      const [
        'budget_id',
        'book_id',
        'month_start',
        'category_id',
        'category_name',
        'limit_minor',
        'limit_display',
        'currency_code',
        'note',
        'deleted_at',
        'created_at',
        'updated_at',
        'version',
      ],
      ordered.map((row) {
        final category = categories[row['category_id']];
        final amount = (row['limit_minor'] as num).toInt();
        final currency = row['currency_code'];
        return [
          _text(row['id']),
          _text(row['book_id']),
          _raw(row['month_start']),
          _text(row['category_id']),
          _text(category?['name'] ?? 'Missing category'),
          _raw(amount),
          _raw('$currency $amount'),
          _text(currency),
          _text(row['note']),
          _date(row['deleted_at']),
          _date(row['created_at']),
          _date(row['updated_at']),
          _raw(row['version']),
        ];
      }),
    );
  }

  static Uint8List _summaryCsv(
    List<Map<String, Object?>> transactions,
    List<Map<String, Object?>> transferLinks,
    List<Map<String, Object?>> budgets,
    CsvExportFilter filter,
  ) {
    var income = 0;
    var expenses = 0;
    final pairedIds = {
      for (final link in transferLinks.where(
        (row) => row['deleted_at'] == null,
      ))
        link['outgoing_transaction_id'],
      for (final link in transferLinks.where(
        (row) => row['deleted_at'] == null,
      ))
        link['incoming_transaction_id'],
    };
    for (final row in transactions.where((row) => row['deleted_at'] == null)) {
      if (pairedIds.contains(row['id'])) continue;
      if (row['transaction_type'] == 'income') {
        income += row['amount'] as int;
      }
      if (row['transaction_type'] == 'expense') {
        expenses += row['amount'] as int;
      }
    }
    final budgetRows = budgets.where((row) {
      if (row['deleted_at'] != null) return false;
      final month = DateTime.parse(row['month_start'] as String);
      final start = filter.startDate == null
          ? null
          : DateTime(filter.startDate!.year, filter.startDate!.month);
      final end = filter.endDateInclusive == null
          ? null
          : DateTime(
              filter.endDateInclusive!.year,
              filter.endDateInclusive!.month + 1,
            );
      return (start == null || !month.isBefore(start)) &&
          (end == null || month.isBefore(end));
    }).toList();
    final budgetLimit = budgetRows.fold<int>(
      0,
      (total, row) => total + (row['limit_minor'] as num).toInt(),
    );
    return _csv(
      const ['metric', 'value'],
      [
        [_raw('transaction_count'), _raw(transactions.length)],
        [_raw('income_minor'), _raw(income)],
        [_raw('expenses_minor'), _raw(expenses)],
        [_raw('cash_flow_minor'), _raw(income - expenses)],
        [_raw('budget_count'), _raw(budgetRows.length)],
        [_raw('budget_limit_minor'), _raw(budgetLimit)],
      ],
    );
  }

  static Uint8List _entityCsv(
    List<Map<String, Object?>> records,
    List<String> headers,
  ) => _csv(
    headers,
    records.map(
      (record) => headers
          .map((header) {
            final value = record[header];
            if (header.endsWith('_at') || header.endsWith('_date')) {
              return _date(value);
            }
            if (value is num || value is bool) return _raw(value);
            return _text(value);
          })
          .toList(growable: false),
    ),
  );

  static List<Map<String, Object?>> _filteredTransactions(
    Map<String, List<Map<String, Object?>>> snapshot,
    CsvExportFilter filter,
  ) {
    final account = filter.accountId == null
        ? null
        : snapshot['accounts']!.firstWhere(
                (row) => row['id'] == filter.accountId,
              )['name']
              as String;
    final category = filter.categoryId == null
        ? null
        : snapshot['categories']!.firstWhere(
                (row) => row['id'] == filter.categoryId,
              )['name']
              as String;
    final start = filter.startDate == null
        ? null
        : DateTime(
            filter.startDate!.year,
            filter.startDate!.month,
            filter.startDate!.day,
          ).millisecondsSinceEpoch;
    final endExclusive = filter.endDateInclusive == null
        ? null
        : DateTime(
            filter.endDateInclusive!.year,
            filter.endDateInclusive!.month,
            filter.endDateInclusive!.day + 1,
          ).millisecondsSinceEpoch;
    final result = (snapshot['transactions'] ?? const []).where((row) {
      final date = row['transaction_date'] as int;
      return (filter.includeDeleted || row['deleted_at'] == null) &&
          (start == null || date >= start) &&
          (endExclusive == null || date < endExclusive) &&
          (filter.transactionTypes.isEmpty ||
              filter.transactionTypes.contains(row['transaction_type'])) &&
          (account == null ||
              _cashAccount(row).toLowerCase() == account.toLowerCase()) &&
          (category == null || row['category'] == category) &&
          (filter.projectId == null || row['project_id'] == filter.projectId) &&
          (filter.memberId == null ||
              row['entered_by_member_id'] == filter.memberId);
    }).toList();
    result.sort((left, right) {
      final date = (left['transaction_date'] as int).compareTo(
        right['transaction_date'] as int,
      );
      return date != 0
          ? date
          : (left['id'] as String).compareTo(right['id'] as String);
    });
    return result;
  }

  static Map<Object?, Map<String, Object?>> _byId(
    List<Map<String, Object?>> records,
  ) => {for (final record in records) record['id']: record};

  static Map<String, Map<String, Object?>> _byName(
    List<Map<String, Object?>> records,
    String field,
  ) => {
    for (final record in records)
      (record[field] as String).toLowerCase(): record,
  };

  static String _cashAccount(Map<String, Object?> row) {
    final value = row['account']?.toString().trim() ?? '';
    final route = value.split('->').map((part) => part.trim()).toList();
    if (route.length != 2 || row['transaction_type'] != 'assetConversion') {
      return value;
    }
    return row['asset_action'] == 'sell' ? route.last : route.first;
  }

  static _CsvCell _text(Object? value) {
    final text = value?.toString() ?? '';
    final leftTrimmed = text.trimLeft();
    if (leftTrimmed.isNotEmpty && '=+-@'.contains(leftTrimmed[0])) {
      return _CsvCell("'$text");
    }
    return _CsvCell(text);
  }

  static _CsvCell _raw(Object? value) => _CsvCell(value?.toString() ?? '');

  static _CsvCell _date(Object? value) {
    if (value is! num) return const _CsvCell('');
    return _CsvCell(
      DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      ).toUtc().toIso8601String(),
    );
  }

  static String _exactDecimal(Object? value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    final decimal = (value as num).toDouble().toStringAsFixed(8);
    return decimal.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static Uint8List _csv(List<String> headers, Iterable<List<_CsvCell>> rows) {
    final buffer = StringBuffer()..writeln(headers.map(_quote).join(','));
    for (final row in rows) {
      buffer.writeln(row.map((cell) => _quote(cell.value)).join(','));
    }
    return Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(buffer.toString()),
    ]);
  }

  static String _quote(String value) => value.contains(RegExp('[,"\r\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;
}

class _CsvCell {
  const _CsvCell(this.value);
  final String value;
}
