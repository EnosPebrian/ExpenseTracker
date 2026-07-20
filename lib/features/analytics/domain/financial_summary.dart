import '../../transactions/domain/entities/transaction.dart';

class CategorySpending {
  const CategorySpending({
    required this.category,
    required this.amount,
    required this.share,
  });

  final String category;
  final int amount;

  /// Value from 0 to 1.
  final double share;
}

class FinancialSummary {
  const FinancialSummary({
    required this.periodStart,
    required this.periodEndExclusive,
    required this.recordedBalance,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.monthlyNetCashFlow,
    required this.savingsRate,
    required this.titheRate,
    required this.monthlyTithe,
    required this.activityCount,
    required this.spendingByCategory,
  });

  final DateTime periodStart;
  final DateTime periodEndExclusive;

  /// All recorded income minus all recorded expenses.
  ///
  /// Transfers and asset conversions do not change this value.
  final int recordedBalance;

  final int monthlyIncome;
  final int monthlyExpenses;
  final int monthlyNetCashFlow;

  /// Decimal representation, for example 0.30 means 30%.
  final double savingsRate;

  /// Decimal representation, for example 0.13 means 13%.
  final double titheRate;

  final int monthlyTithe;

  /// All transaction types recorded within the period.
  final int activityCount;

  final List<CategorySpending> spendingByCategory;

  CategorySpending? get topCategory {
    if (spendingByCategory.isEmpty) {
      return null;
    }

    return spendingByCategory.first;
  }

  factory FinancialSummary.calculate({
    required Iterable<Transaction> transactions,
    required DateTime referenceDate,
    double titheRate = 0.13,
  }) {
    if (titheRate < 0 || titheRate > 1) {
      throw ArgumentError.value(
        titheRate,
        'titheRate',
        'Tithe rate must be between 0 and 1.',
      );
    }

    final periodStart = DateTime(referenceDate.year, referenceDate.month);

    final periodEndExclusive = DateTime(
      referenceDate.year,
      referenceDate.month + 1,
    );

    final activeTransactions = transactions
        .where((transaction) => transaction.deletedAt == null)
        .toList(growable: false);

    var allTimeIncome = 0;
    var allTimeExpenses = 0;

    for (final transaction in activeTransactions) {
      switch (transaction.type) {
        case TransactionType.income:
          allTimeIncome += transaction.amount;

        case TransactionType.expense:
          allTimeExpenses += transaction.amount;

        case TransactionType.transfer:
        case TransactionType.assetConversion:
          break;
      }
    }

    final periodTransactions = activeTransactions
        .where((transaction) {
          return !transaction.date.isBefore(periodStart) &&
              transaction.date.isBefore(periodEndExclusive);
        })
        .toList(growable: false);

    var monthlyIncome = 0;
    var monthlyExpenses = 0;

    final categoryTotals = <String, int>{};

    for (final transaction in periodTransactions) {
      switch (transaction.type) {
        case TransactionType.income:
          monthlyIncome += transaction.amount;

        case TransactionType.expense:
          monthlyExpenses += transaction.amount;

          categoryTotals.update(
            transaction.category,
            (current) => current + transaction.amount,
            ifAbsent: () => transaction.amount,
          );

        case TransactionType.transfer:
        case TransactionType.assetConversion:
          break;
      }
    }

    final monthlyNetCashFlow = monthlyIncome - monthlyExpenses;

    final savingsRate = monthlyIncome == 0
        ? 0.0
        : monthlyNetCashFlow / monthlyIncome;

    final spendingByCategory =
        categoryTotals.entries
            .map(
              (entry) => CategorySpending(
                category: entry.key,
                amount: entry.value,
                share: monthlyExpenses == 0 ? 0 : entry.value / monthlyExpenses,
              ),
            )
            .toList()
          ..sort((left, right) => right.amount.compareTo(left.amount));

    return FinancialSummary(
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      recordedBalance: allTimeIncome - allTimeExpenses,
      monthlyIncome: monthlyIncome,
      monthlyExpenses: monthlyExpenses,
      monthlyNetCashFlow: monthlyNetCashFlow,
      savingsRate: savingsRate,
      titheRate: titheRate,
      monthlyTithe: (monthlyIncome * titheRate).round(),
      activityCount: periodTransactions.length,
      spendingByCategory: List<CategorySpending>.unmodifiable(
        spendingByCategory,
      ),
    );
  }
}
