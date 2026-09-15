import 'dart:convert';

/// Shared storage-boundary validation; contains no accounting calculations.
class BrokerageSettlementIntegrity {
  static void validate(
    Map<String, Object?> row,
    Iterable<Map<String, Object?>> accounts,
    Iterable<Map<String, Object?>> trades,
  ) {
    for (final key in [
      'id',
      'book_id',
      'brokerage_account_id',
      'source_fingerprint',
      'source_row_identity',
      'source_row_fingerprint',
      'currency_code',
    ]) {
      if (row[key] is! String || (row[key] as String).isEmpty) {
        throw StateError('Incomplete settlement evidence.');
      }
    }
    if (row['amount'] is! int ||
        (row['amount'] as int) <= 0 ||
        row['statement_date'] is! int ||
        !['BUY_SETTLEMENT', 'SELL_SETTLEMENT'].contains(row['settlement_type'])) {
      throw StateError('Invalid settlement source values.');
    }
    final account = accounts.where(
      (a) =>
          a['id'] == row['brokerage_account_id'] &&
          a['book_id'] == row['book_id'] &&
          a['account_type'] == 'brokerage' &&
          a['currency_code'] == row['currency_code'],
    );
    if (account.length != 1) {
      throw StateError(
        'Settlement brokerage account is missing or incompatible.',
      );
    }
    final links = jsonDecode(row['trade_ids_json'] as String);
    if (links is! List ||
        links.any((id) => id is! String) ||
        links.toSet().length != links.length) {
      throw StateError('Invalid settlement trade references.');
    }
    final byId = {for (final trade in trades) trade['id']: trade};
    for (final id in links) {
      final trade = byId[id];
      if (trade == null ||
          trade['book_id'] != row['book_id'] ||
          trade['brokerage_account_id'] != row['brokerage_account_id'] ||
          trade['brokerage_activity_type'] !=
              (row['settlement_type'] == 'BUY_SETTLEMENT' ? 'buy' : 'sell')) {
        throw StateError('Settlement references an incompatible trade.');
      }
    }
  }
}
