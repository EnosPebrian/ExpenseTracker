import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/filters/transaction_filter.dart';

Transaction _transaction({
  required String title,
  required DateTime date,
  String category = 'Konsumsi',
  String account = 'Cash Enos',
  String? projectId = 'life',
}) {
  return Transaction(
    projectId: projectId,
    title: title,
    category: category,
    account: account,
    date: date,
    amount: 125000,
    type: TransactionType.expense,
  );
}

void main() {
  test('month bounds cover the complete reference month', () {
    final reference = DateTime(2026, 7, 19);

    expect(transactionMonthStart(reference), DateTime(2026, 7, 1));

    expect(transactionMonthEnd(reference), DateTime(2026, 7, 31));
  });

  test('filter includes complete boundary days and excludes outside dates', () {
    final transactions = [
      _transaction(title: 'Before range', date: DateTime(2026, 6, 30, 23, 59)),
      _transaction(title: 'First day', date: DateTime(2026, 7, 1)),
      _transaction(title: 'Last day', date: DateTime(2026, 7, 31, 23, 59)),
      _transaction(title: 'After range', date: DateTime(2026, 8, 1)),
    ];

    final result = filterTransactions(
      transactions: transactions,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
    );

    expect(result.map((item) => item.title), ['First day', 'Last day']);
  });

  test('search matches title, category, account, project, and type', () {
    final transactions = [
      _transaction(
        title: 'Morning coffee',
        date: DateTime(2026, 7, 10),
        category: 'Dining',
        account: 'BNI Enos',
        projectId: 'tebu-nai',
      ),
      _transaction(
        title: 'Fuel',
        date: DateTime(2026, 7, 11),
        category: 'Transportasi',
      ),
    ];

    final byAccount = filterTransactions(
      transactions: transactions,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
      query: 'bni',
    );

    final byProject = filterTransactions(
      transactions: transactions,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
      query: 'TEBU',
    );

    final byCategory = filterTransactions(
      transactions: transactions,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
      query: 'transportasi',
    );

    expect(byAccount.single.title, 'Morning coffee');

    expect(byProject.single.title, 'Morning coffee');

    expect(byCategory.single.title, 'Fuel');
  });

  test('selecting From after To moves To to the same date', () {
    final range = updateTransactionFrom(
      selectedFrom: DateTime(2026, 8, 10),
      currentTo: DateTime(2026, 7, 31),
    );

    expect(range.from, DateTime(2026, 8, 10));

    expect(range.to, DateTime(2026, 8, 10));
  });

  test('selecting To before From moves From to the same date', () {
    final range = updateTransactionTo(
      currentFrom: DateTime(2026, 7, 15),
      selectedTo: DateTime(2026, 7, 5),
    );

    expect(range.from, DateTime(2026, 7, 5));

    expect(range.to, DateTime(2026, 7, 5));
  });

  test('valid range keeps the opposite boundary unchanged', () {
    final fromResult = updateTransactionFrom(
      selectedFrom: DateTime(2026, 7, 5),
      currentTo: DateTime(2026, 7, 20),
    );

    final toResult = updateTransactionTo(
      currentFrom: DateTime(2026, 7, 5),
      selectedTo: DateTime(2026, 7, 20),
    );

    expect(fromResult.from, DateTime(2026, 7, 5));
    expect(fromResult.to, DateTime(2026, 7, 20));

    expect(toResult.from, DateTime(2026, 7, 5));
    expect(toResult.to, DateTime(2026, 7, 20));
  });
}
