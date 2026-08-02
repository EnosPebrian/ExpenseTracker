import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';

/// Test-only sample data. Production code cannot import files under `test/`.
Future<void> installDemoFinancialFixture(
  TransactionRepository repository,
) async {
  for (final transaction in buildDemoTransactionsForTest()) {
    await repository.save(transaction);
  }
}

List<Transaction> buildDemoTransactionsForTest() => [
  Transaction(
    id: 'test-demo-monthly-groceries',
    title: 'Monthly groceries',
    category: 'Food & dining',
    account: 'Bank BCA',
    date: DateTime(2026, 7, 18, 9, 42),
    amount: 842500,
    type: TransactionType.expense,
  ),
  Transaction(
    id: 'test-demo-client-retainer',
    title: 'Client retainer - July',
    category: 'Service income',
    account: 'Bank BCA',
    date: DateTime(2026, 7, 17),
    amount: 7500000,
    type: TransactionType.income,
  ),
];
