import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/tithe/domain/tithe_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

Transaction _transaction({
  required String title,
  required TransactionType type,
  required int amount,
  required DateTime date,
  String category = 'General',
  DateTime? deletedAt,
}) {
  return Transaction(
    title: title,
    category: category,
    account: 'Cash Enos',
    date: date,
    amount: amount,
    type: type,
    deletedAt: deletedAt,
  );
}

void main() {
  test('calculates current month income, expenses, and net cash flow', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [
        _transaction(
          title: 'Salary',
          type: TransactionType.income,
          amount: 10000000,
          date: DateTime(2026, 7, 1),
        ),
        _transaction(
          title: 'Food',
          type: TransactionType.expense,
          amount: 2500000,
          date: DateTime(2026, 7, 10),
        ),
        _transaction(
          title: 'Rent',
          type: TransactionType.expense,
          amount: 1500000,
          date: DateTime(2026, 7, 31, 23, 59),
        ),
        _transaction(
          title: 'Old income',
          type: TransactionType.income,
          amount: 9000000,
          date: DateTime(2026, 6, 30),
        ),
      ],
    );

    expect(summary.monthlyIncome, 10000000);
    expect(summary.monthlyExpenses, 4000000);
    expect(summary.monthlyNetCashFlow, 6000000);
    expect(summary.savingsRate, 0.6);
    expect(summary.activityCount, 3);
  });

  test('transfers and asset conversions do not affect cash flow totals', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [
        _transaction(
          title: 'Salary',
          type: TransactionType.income,
          amount: 5000000,
          date: DateTime(2026, 7, 1),
        ),
        _transaction(
          title: 'Transfer',
          type: TransactionType.transfer,
          amount: 2000000,
          date: DateTime(2026, 7, 2),
        ),
        _transaction(
          title: 'Buy gold',
          type: TransactionType.assetConversion,
          amount: 3000000,
          date: DateTime(2026, 7, 3),
        ),
      ],
    );

    expect(summary.monthlyIncome, 5000000);
    expect(summary.monthlyExpenses, 0);
    expect(summary.monthlyNetCashFlow, 5000000);

    // They are still genuine ledger activities.
    expect(summary.activityCount, 3);
  });

  test('recorded balance uses all active income and expenses', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [
        _transaction(
          title: 'June income',
          type: TransactionType.income,
          amount: 8000000,
          date: DateTime(2026, 6, 1),
        ),
        _transaction(
          title: 'July income',
          type: TransactionType.income,
          amount: 5000000,
          date: DateTime(2026, 7, 1),
        ),
        _transaction(
          title: 'June expense',
          type: TransactionType.expense,
          amount: 2000000,
          date: DateTime(2026, 6, 10),
        ),
        _transaction(
          title: 'Deleted expense',
          type: TransactionType.expense,
          amount: 4000000,
          date: DateTime(2026, 7, 10),
          deletedAt: DateTime(2026, 7, 11),
        ),
      ],
    );

    expect(summary.recordedBalance, 11000000);
  });

  test('spending categories are sorted and contain accurate shares', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [
        _transaction(
          title: 'Rent',
          type: TransactionType.expense,
          amount: 3000000,
          date: DateTime(2026, 7, 1),
          category: 'Housing',
        ),
        _transaction(
          title: 'Lunch',
          type: TransactionType.expense,
          amount: 1000000,
          date: DateTime(2026, 7, 2),
          category: 'Food',
        ),
        _transaction(
          title: 'Dinner',
          type: TransactionType.expense,
          amount: 1000000,
          date: DateTime(2026, 7, 3),
          category: 'Food',
        ),
      ],
    );

    expect(summary.spendingByCategory.map((item) => item.category).toList(), [
      'Housing',
      'Food',
    ]);

    expect(summary.topCategory?.amount, 3000000);
    expect(summary.topCategory?.share, 0.6);
    expect(summary.spendingByCategory[1].share, 0.4);
  });

  test('calculates tithe and safely handles zero income', () {
    final withIncome = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      titheRate: TithePolicy.defaultPolicy.rateFor(DateTime(2026, 7, 20)),
      transactions: [
        _transaction(
          title: 'Income',
          type: TransactionType.income,
          amount: 10000000,
          date: DateTime(2026, 7, 1),
        ),
      ],
    );

    final withoutIncome = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [
        _transaction(
          title: 'Expense',
          type: TransactionType.expense,
          amount: 1000000,
          date: DateTime(2026, 7, 1),
        ),
      ],
    );

    expect(withIncome.monthlyTithe, 1300000);
    expect(
      withIncome.titheRate,
      TithePolicy.defaultPolicy.rateFor(DateTime(2026, 7, 20)),
    );
    expect(withIncome.savingsRate, 1);

    expect(withoutIncome.monthlyTithe, 0);
    expect(withoutIncome.savingsRate, 0);
    expect(withoutIncome.monthlyNetCashFlow, -1000000);
  });
}
