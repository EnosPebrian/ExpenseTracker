import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

Transaction _income(int amount) => Transaction(
  title: 'Salary',
  category: 'Income',
  account: 'Cash Enos',
  date: DateTime(2026, 7, 1),
  amount: amount,
  type: TransactionType.income,
);

void main() {
  test('empty assets and liabilities produce zero position values', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: const [],
    );

    expect(summary.totalAssets, 0);
    expect(summary.totalLiabilities, 0);
    expect(summary.netWorth, 0);
    expect(summary.cash, 0);
    expect(summary.availableCash, 0);
    expect(summary.availableCashAfterPendingTithe, 0);
    expect(summary.assetAllocation, isEmpty);
    expect(summary.liabilityTotals, isEmpty);
  });

  test('calculates mixed asset classes and allocation percentages', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [_income(10000000)],
      assets: const [
        FinancialAsset(type: 'Cash', amount: 5000000),
        FinancialAsset(type: 'Gold', amount: 3000000),
        FinancialAsset(type: 'Stocks', amount: 2000000),
      ],
    );

    expect(summary.totalAssets, 10000000);
    expect(summary.cash, 5000000);
    expect(summary.assetAllocation.map((item) => item.type), [
      'Cash',
      'Gold',
      'Stocks',
    ]);
    expect(summary.assetAllocation.map((item) => item.share), [0.5, 0.3, 0.2]);
  });

  test('calculates liabilities, net worth, and cash available after tithe', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: [_income(10000000)],
      assets: const [FinancialAsset(type: 'Cash', amount: 5000000)],
      liabilities: const [
        FinancialLiability(type: 'Credit card', amount: 1000000),
        FinancialLiability(type: 'Family loan', amount: 500000),
      ],
    );

    expect(summary.totalLiabilities, 1500000);
    expect(summary.netWorth, 3500000);
    expect(summary.availableCash, 3500000);
    expect(summary.pendingTithe, 1300000);
    expect(summary.availableCashAfterPendingTithe, 2200000);
    expect(summary.liabilityTotals.map((item) => item.amount), [
      1000000,
      500000,
    ]);
  });

  test('groups repeated asset and liability types case-insensitively', () {
    final summary = FinancialSummary.calculate(
      referenceDate: DateTime(2026, 7, 20),
      transactions: const [],
      assets: const [
        FinancialAsset(type: 'Cash', amount: 1000),
        FinancialAsset(type: 'cash', amount: 500),
      ],
      liabilities: const [
        FinancialLiability(type: 'Loan', amount: 700),
        FinancialLiability(type: 'loan', amount: 300),
      ],
    );

    expect(summary.assetAllocation, hasLength(1));
    expect(summary.assetAllocation.single.amount, 1500);
    expect(summary.liabilityTotals, hasLength(1));
    expect(summary.liabilityTotals.single.amount, 1000);
  });
}
