import '../../domain/entities/transaction.dart';

DateTime transactionMonthStart(DateTime reference) {
  return DateTime(reference.year, reference.month);
}

DateTime transactionMonthEnd(DateTime reference) {
  return DateTime(reference.year, reference.month + 1, 0);
}

class TransactionDateRange {
  const TransactionDateRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;
}

TransactionDateRange updateTransactionFrom({
  required DateTime selectedFrom,
  required DateTime currentTo,
}) {
  final from = _dateOnly(selectedFrom);
  final to = _dateOnly(currentTo);

  if (from.isAfter(to)) {
    return TransactionDateRange(from: from, to: from);
  }

  return TransactionDateRange(from: from, to: to);
}

TransactionDateRange updateTransactionTo({
  required DateTime currentFrom,
  required DateTime selectedTo,
}) {
  final from = _dateOnly(currentFrom);
  final to = _dateOnly(selectedTo);

  if (to.isBefore(from)) {
    return TransactionDateRange(from: to, to: to);
  }

  return TransactionDateRange(from: from, to: to);
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

List<Transaction> filterTransactions({
  required Iterable<Transaction> transactions,
  required DateTime from,
  required DateTime to,
  String query = '',
}) {
  final normalizedFrom = DateTime(from.year, from.month, from.day);

  final normalizedToExclusive = DateTime(
    to.year,
    to.month,
    to.day,
  ).add(const Duration(days: 1));

  final normalizedQuery = query.trim().toLowerCase();

  return transactions
      .where((transaction) {
        final matchesDate =
            !transaction.date.isBefore(normalizedFrom) &&
            transaction.date.isBefore(normalizedToExclusive);

        if (!matchesDate) {
          return false;
        }

        if (normalizedQuery.isEmpty) {
          return true;
        }

        final searchableText = [
          transaction.title,
          transaction.category,
          transaction.account,
          transaction.projectId ?? '',
          transaction.type.name,
        ].join(' ').toLowerCase();

        return searchableText.contains(normalizedQuery);
      })
      .toList(growable: false);
}
