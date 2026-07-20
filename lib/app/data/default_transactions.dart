import '../../features/transactions/domain/entities/transaction.dart';

List<Transaction> buildDefaultTransactions() {
  return [
    Transaction(
      title: 'Monthly groceries',
      category: 'Food & dining',
      account: 'Bank BCA',
      date: DateTime(2026, 7, 18, 9, 42),
      amount: 842500,
      type: TransactionType.expense,
    ),
    Transaction(
      title: 'Client retainer - July',
      category: 'Service income',
      account: 'Bank BCA',
      date: DateTime(2026, 7, 17),
      amount: 7500000,
      type: TransactionType.income,
    ),
    Transaction(
      title: 'Move to cash',
      category: 'Transfer',
      account: 'Bank BCA -> Cash',
      date: DateTime(2026, 7, 16),
      amount: 1000000,
      type: TransactionType.transfer,
    ),
    Transaction(
      title: 'Workspace subscription',
      category: 'Software',
      account: 'Jago',
      date: DateTime(2026, 7, 15),
      amount: 249000,
      type: TransactionType.expense,
    ),
    Transaction(
      title: 'Gold acquisition',
      category: 'Asset conversion',
      account: 'Bank BCA -> Gold Holdings',
      date: DateTime(2026, 7, 14),
      amount: 50000000,
      type: TransactionType.assetConversion,
      quantity: 20,
      unit: 'gram',
      unitPrice: 2500000,
    ),
  ];
}
