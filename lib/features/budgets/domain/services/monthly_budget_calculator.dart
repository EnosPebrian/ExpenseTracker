import '../../../transactions/domain/entities/transaction.dart';
import '../entities/monthly_category_budget.dart';

enum BudgetThreshold { onTrack, nearLimit, overspent }

class CategoryBudgetResult {
  const CategoryBudgetResult({
    required this.budget,
    required this.categoryName,
    required this.spentMinor,
  });

  final MonthlyCategoryBudget budget;
  final String categoryName;
  final int spentMinor;

  int get remainingMinor =>
      (budget.limitMinor - spentMinor).clamp(0, budget.limitMinor).toInt();
  int get overspentMinor =>
      (spentMinor - budget.limitMinor).clamp(0, spentMinor).toInt();
  double get usedRatio => spentMinor / budget.limitMinor;
  BudgetThreshold get threshold => usedRatio >= 1
      ? BudgetThreshold.overspent
      : usedRatio >= .8
      ? BudgetThreshold.nearLimit
      : BudgetThreshold.onTrack;
}

class MonthlyBudgetSummary {
  const MonthlyBudgetSummary({
    required this.monthStart,
    required this.categories,
    required this.unbudgetedSpendMinor,
  });

  final DateTime monthStart;
  final List<CategoryBudgetResult> categories;
  final int unbudgetedSpendMinor;

  int get totalLimitMinor =>
      categories.fold(0, (v, e) => v + e.budget.limitMinor);
  int get budgetedSpendMinor => categories.fold(0, (v, e) => v + e.spentMinor);
  int get totalSpendMinor => budgetedSpendMinor + unbudgetedSpendMinor;
  int get remainingMinor =>
      categories.fold(0, (value, result) => value + result.remainingMinor);
  int get overspentMinor =>
      categories.fold(0, (value, result) => value + result.overspentMinor);
}

class MonthlyBudgetCalculator {
  const MonthlyBudgetCalculator._();

  static MonthlyBudgetSummary calculate({
    required DateTime month,
    required List<MonthlyCategoryBudget> budgets,
    required List<Transaction> transactions,
    required Map<String, String> categoryNamesById,
    Set<String> pairedTransactionIds = const {},
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final active = budgets.where(
      (budget) =>
          budget.deletedAt == null &&
          budget.monthStart.year == start.year &&
          budget.monthStart.month == start.month,
    );
    final names = <String, MonthlyCategoryBudget>{};
    for (final budget in active) {
      final name = categoryNamesById[budget.categoryId];
      if (name == null || name.trim().isEmpty) {
        throw StateError('Budget ${budget.id} references a missing category.');
      }
      names[name.toLowerCase()] = budget;
    }
    final spent = <String, int>{};
    var unbudgeted = 0;
    for (final transaction in transactions) {
      if (pairedTransactionIds.contains(transaction.id) ||
          transaction.deletedAt != null ||
          transaction.type != TransactionType.expense ||
          transaction.date.isBefore(start) ||
          !transaction.date.isBefore(end)) {
        continue;
      }
      final budget = names[transaction.category.trim().toLowerCase()];
      if (budget == null) {
        unbudgeted += transaction.amount;
      } else {
        spent[budget.id] = (spent[budget.id] ?? 0) + transaction.amount;
      }
    }
    final results =
        active
            .map(
              (budget) => CategoryBudgetResult(
                budget: budget,
                categoryName: categoryNamesById[budget.categoryId]!,
                spentMinor: spent[budget.id] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => a.categoryName.compareTo(b.categoryName));
    return MonthlyBudgetSummary(
      monthStart: start,
      categories: results,
      unbudgetedSpendMinor: unbudgeted,
    );
  }
}
