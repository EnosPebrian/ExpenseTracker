import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/services/account_balance_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  test(
    'opening balances remain isolated from reports, tithe, and portfolio',
    () {
      final transactions = [
        Transaction(
          title: 'Salary',
          category: 'Salary',
          projectId: 'project-life',
          account: 'Cash',
          date: DateTime(2026, 7, 2),
          amount: 1000,
          type: TransactionType.income,
        ),
        Transaction(
          title: 'Food',
          category: 'Food',
          projectId: 'project-life',
          account: 'Cash',
          date: DateTime(2026, 7, 3),
          amount: 200,
          type: TransactionType.expense,
        ),
        Transaction(
          title: 'Buy gold',
          category: 'Asset',
          projectId: 'project-life',
          account: 'Cash',
          date: DateTime(2026, 7, 4),
          amount: 500,
          type: TransactionType.assetConversion,
          assetAction: AssetAction.buy,
          assetName: 'Gold',
          quantity: 5,
          unit: 'gram',
          unitPrice: 100,
        ),
      ];
      final before = FinancialSummary.calculate(
        transactions: transactions,
        referenceDate: DateTime(2026, 7, 26),
      );
      final portfolioBefore = AssetPortfolioCalculator.calculate(
        transactions: transactions,
      );

      final account = Account(
        name: 'Cash',
        openingBalance: 9000,
        openingBalanceDate: DateTime(2026, 7, 1),
      );
      expect(
        AccountBalanceCalculator.calculate(
          account: account,
          transactions: transactions,
        ),
        9300,
      );

      final after = FinancialSummary.calculate(
        transactions: transactions,
        referenceDate: DateTime(2026, 7, 26),
      );
      final portfolioAfter = AssetPortfolioCalculator.calculate(
        transactions: transactions,
      );

      expect(after.monthlyIncome, before.monthlyIncome);
      expect(after.monthlyExpenses, before.monthlyExpenses);
      expect(after.monthlyNetCashFlow, before.monthlyNetCashFlow);
      expect(after.activityCount, before.activityCount);
      expect(after.monthlyTithe, before.monthlyTithe);
      expect(
        after.spendingByCategory.map((item) => (item.category, item.amount)),
        before.spendingByCategory.map((item) => (item.category, item.amount)),
      );
      expect(portfolioAfter.holdings.single.quantity, 5);
      expect(portfolioAfter.totalCostBasis, portfolioBefore.totalCostBasis);
      expect(
        portfolioAfter.totalRealizedGain,
        portfolioBefore.totalRealizedGain,
      );
      expect(
        portfolioAfter.totalUnrealizedGain,
        portfolioBefore.totalUnrealizedGain,
      );
    },
  );
}
