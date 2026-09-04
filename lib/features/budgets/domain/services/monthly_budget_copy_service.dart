import '../entities/monthly_category_budget.dart';

enum MonthlyBudgetCopyMode { addMissingOnly }

class MonthlyBudgetCopyOptions {
  const MonthlyBudgetCopyOptions({
    this.mode = MonthlyBudgetCopyMode.addMissingOnly,
  });

  final MonthlyBudgetCopyMode mode;
}

class BudgetCopyCategory {
  const BudgetCopyCategory({
    required this.id,
    required this.bookId,
    required this.name,
    required this.active,
  });

  final String id;
  final String bookId;
  final String name;
  final bool active;
}

enum MonthlyBudgetCopyRowStatus {
  willBeAdded,
  alreadyPresent,
  categoryUnavailable,
}

enum BudgetCategoryUnavailableReason { archived, missing }

class MonthlyBudgetCopyRow {
  const MonthlyBudgetCopyRow({
    required this.sourceBudget,
    required this.categoryName,
    required this.status,
    this.unavailableReason,
  });

  final MonthlyCategoryBudget sourceBudget;
  final String categoryName;
  final MonthlyBudgetCopyRowStatus status;
  final BudgetCategoryUnavailableReason? unavailableReason;
}

class MonthlyBudgetCopyPreview {
  const MonthlyBudgetCopyPreview({
    required this.bookId,
    required this.sourceMonth,
    required this.targetMonth,
    required this.rows,
    required this.existingTargetCount,
    required this.existingTargetTotalMinor,
    required this.expectedTargetTotalMinor,
  });

  final String bookId;
  final DateTime sourceMonth;
  final DateTime targetMonth;
  final List<MonthlyBudgetCopyRow> rows;
  final int existingTargetCount;
  final int existingTargetTotalMinor;
  final int expectedTargetTotalMinor;

  int get sourceBudgetCount => rows.length;
  int get budgetsToAdd => rows
      .where((row) => row.status == MonthlyBudgetCopyRowStatus.willBeAdded)
      .length;
  int get alreadyPresent => rows
      .where((row) => row.status == MonthlyBudgetCopyRowStatus.alreadyPresent)
      .length;
  int get unavailableCategories => rows
      .where(
        (row) => row.status == MonthlyBudgetCopyRowStatus.categoryUnavailable,
      )
      .length;
  int get eligibleToCopy => budgetsToAdd + alreadyPresent;
  int get skipped => alreadyPresent + unavailableCategories;
  List<String> get warnings => [
    for (final row in rows)
      if (row.unavailableReason == BudgetCategoryUnavailableReason.archived)
        '${row.categoryName} is archived and will not be copied.'
      else if (row.unavailableReason == BudgetCategoryUnavailableReason.missing)
        'A source budget references a missing category and will not be copied.',
  ];
}

class MonthlyBudgetCopyResult {
  const MonthlyBudgetCopyResult({
    required this.preview,
    required this.copiedBudgets,
    required this.finalTargetCount,
    required this.finalTargetTotalMinor,
  });

  final MonthlyBudgetCopyPreview preview;
  final List<MonthlyCategoryBudget> copiedBudgets;
  final int finalTargetCount;
  final int finalTargetTotalMinor;

  int get sourceBudgetCount => preview.sourceBudgetCount;
  int get eligibleToCopy => preview.eligibleToCopy;
  int get copied => copiedBudgets.length;
  int get alreadyPresent =>
      preview.alreadyPresent + (preview.budgetsToAdd - copied);
  int get unavailableCategories => preview.unavailableCategories;
  int get skipped => alreadyPresent + unavailableCategories;
}

class MonthlyBudgetCopyService {
  const MonthlyBudgetCopyService();

  DateTime normalizeMonth(DateTime value) => DateTime(value.year, value.month);

  MonthlyBudgetCopyPreview preview({
    required String bookId,
    required DateTime sourceMonth,
    required DateTime targetMonth,
    required List<MonthlyCategoryBudget> sourceBudgets,
    required List<MonthlyCategoryBudget> targetBudgets,
    required Map<String, BudgetCopyCategory> categoriesById,
    MonthlyBudgetCopyOptions options = const MonthlyBudgetCopyOptions(),
  }) {
    if (options.mode != MonthlyBudgetCopyMode.addMissingOnly) {
      throw StateError('Only add-missing budget copies are supported.');
    }
    final source = normalizeMonth(sourceMonth);
    final target = normalizeMonth(targetMonth);
    if (source == target) {
      throw StateError('Source and target months must be different.');
    }
    final activeSource = sourceBudgets.where(
      (budget) => budget.deletedAt == null && budget.monthStart == source,
    );
    final activeTarget = targetBudgets.where(
      (budget) => budget.deletedAt == null && budget.monthStart == target,
    );
    for (final budget in [...activeSource, ...activeTarget]) {
      if (budget.bookId != bookId) {
        throw StateError('Cross-household budget references cannot be copied.');
      }
    }
    final targetByCategory = {
      for (final budget in activeTarget) budget.categoryId: budget,
    };
    final rows = <MonthlyBudgetCopyRow>[];
    for (final budget in activeSource) {
      final category = categoriesById[budget.categoryId];
      if (category != null && category.bookId != bookId) {
        throw StateError('Cross-household categories cannot be copied.');
      }
      if (category == null) {
        rows.add(
          MonthlyBudgetCopyRow(
            sourceBudget: budget,
            categoryName: 'Missing category',
            status: MonthlyBudgetCopyRowStatus.categoryUnavailable,
            unavailableReason: BudgetCategoryUnavailableReason.missing,
          ),
        );
      } else if (!category.active) {
        rows.add(
          MonthlyBudgetCopyRow(
            sourceBudget: budget,
            categoryName: category.name,
            status: MonthlyBudgetCopyRowStatus.categoryUnavailable,
            unavailableReason: BudgetCategoryUnavailableReason.archived,
          ),
        );
      } else {
        rows.add(
          MonthlyBudgetCopyRow(
            sourceBudget: budget,
            categoryName: category.name,
            status: targetByCategory.containsKey(budget.categoryId)
                ? MonthlyBudgetCopyRowStatus.alreadyPresent
                : MonthlyBudgetCopyRowStatus.willBeAdded,
          ),
        );
      }
    }
    rows.sort((a, b) => a.categoryName.compareTo(b.categoryName));
    final existingTotal = activeTarget.fold<int>(
      0,
      (total, budget) => total + budget.limitMinor,
    );
    final addedTotal = rows
        .where((row) => row.status == MonthlyBudgetCopyRowStatus.willBeAdded)
        .fold<int>(0, (total, row) => total + row.sourceBudget.limitMinor);
    return MonthlyBudgetCopyPreview(
      bookId: bookId,
      sourceMonth: source,
      targetMonth: target,
      rows: List.unmodifiable(rows),
      existingTargetCount: activeTarget.length,
      existingTargetTotalMinor: existingTotal,
      expectedTargetTotalMinor: existingTotal + addedTotal,
    );
  }

  List<MonthlyCategoryBudget> createCandidates(
    MonthlyBudgetCopyPreview preview,
  ) => [
    for (final row in preview.rows)
      if (row.status == MonthlyBudgetCopyRowStatus.willBeAdded)
        MonthlyCategoryBudget(
          bookId: preview.bookId,
          categoryId: row.sourceBudget.categoryId,
          monthStart: preview.targetMonth,
          limitMinor: row.sourceBudget.limitMinor,
          currencyCode: row.sourceBudget.currencyCode,
          note: row.sourceBudget.note,
          syncStatus: 'pending',
        ),
  ];

  MonthlyBudgetCopyResult complete({
    required MonthlyBudgetCopyPreview preview,
    required List<MonthlyCategoryBudget> copiedBudgets,
    required List<MonthlyCategoryBudget> finalTargetBudgets,
  }) => MonthlyBudgetCopyResult(
    preview: preview,
    copiedBudgets: List.unmodifiable(copiedBudgets),
    finalTargetCount: finalTargetBudgets
        .where((budget) => budget.deletedAt == null)
        .length,
    finalTargetTotalMinor: finalTargetBudgets
        .where((budget) => budget.deletedAt == null)
        .fold(0, (total, budget) => total + budget.limitMinor),
  );
}
