import '../../../core/database/local_store.dart';
import '../domain/entities/monthly_category_budget.dart';
import '../domain/services/monthly_budget_copy_service.dart';

class LocalMonthlyBudgetRepository {
  const LocalMonthlyBudgetRepository(
    this.store, {
    this.copyService = const MonthlyBudgetCopyService(),
  });

  final LocalStore store;
  final MonthlyBudgetCopyService copyService;

  Future<List<MonthlyCategoryBudget>> getAll({
    bool includeDeleted = false,
    String? bookId,
  }) async => (await store.getMonthlyCategoryBudgets(
    includeDeleted: includeDeleted,
    bookId: bookId,
  )).map(MonthlyCategoryBudget.fromRecord).toList();

  Future<List<MonthlyCategoryBudget>> getForMonth({
    required String bookId,
    required DateTime month,
    bool includeDeleted = false,
  }) async => (await store.getMonthlyCategoryBudgets(
    includeDeleted: includeDeleted,
    bookId: bookId,
    monthStart:
        '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}-01',
  )).map(MonthlyCategoryBudget.fromRecord).toList();

  Future<MonthlyCategoryBudget?> find({
    required String bookId,
    required String categoryId,
    required DateTime month,
    bool includeDeleted = false,
  }) async {
    final rows = await getAll(includeDeleted: includeDeleted, bookId: bookId);
    for (final budget in rows) {
      if (budget.categoryId == categoryId &&
          budget.monthStart.year == month.year &&
          budget.monthStart.month == month.month) {
        return budget;
      }
    }
    return null;
  }

  Future<MonthlyCategoryBudget> save(MonthlyCategoryBudget budget) async =>
      MonthlyCategoryBudget.fromRecord(
        await store.upsertMonthlyCategoryBudget(budget.toRecord()),
      );

  Future<void> delete(MonthlyCategoryBudget budget) =>
      store.softDeleteMonthlyCategoryBudget(
        budget.id,
        DateTime.now().millisecondsSinceEpoch,
      );

  Future<MonthlyBudgetCopyPreview> previewCopy({
    required String bookId,
    required DateTime sourceMonth,
    required DateTime targetMonth,
  }) async {
    final source = await getForMonth(bookId: bookId, month: sourceMonth);
    final target = await getForMonth(bookId: bookId, month: targetMonth);
    final categoryRows = await store.getBudgetCopyCategoryRecords(
      source.map((budget) => budget.categoryId),
    );
    return copyService.preview(
      bookId: bookId,
      sourceMonth: sourceMonth,
      targetMonth: targetMonth,
      sourceBudgets: source,
      targetBudgets: target,
      categoriesById: {
        for (final row in categoryRows)
          row['id'] as String: BudgetCopyCategory(
            id: row['id'] as String,
            bookId: row['book_id'] as String,
            name: row['name'] as String,
            active: row['deleted_at'] == null,
          ),
      },
    );
  }

  Future<MonthlyBudgetCopyResult> copy(MonthlyBudgetCopyPreview preview) async {
    final candidates = copyService.createCandidates(preview);
    final copiedRecords = await store.copyMonthlyCategoryBudgets(
      candidates.map((budget) => budget.toRecord()).toList(),
    );
    final finalBudgets = await getForMonth(
      bookId: preview.bookId,
      month: preview.targetMonth,
    );
    return copyService.complete(
      preview: preview,
      copiedBudgets: copiedRecords
          .map(MonthlyCategoryBudget.fromRecord)
          .toList(),
      finalTargetBudgets: finalBudgets,
    );
  }
}
