import 'package:flutter/foundation.dart';

import '../../../transactions/domain/entities/transaction.dart';
import '../../data/local_monthly_budget_repository.dart';
import '../../domain/entities/monthly_category_budget.dart';
import '../../domain/services/monthly_budget_calculator.dart';
import '../../domain/services/monthly_budget_copy_service.dart';

class MonthlyBudgetController extends ChangeNotifier {
  MonthlyBudgetController({required this.repository});

  final LocalMonthlyBudgetRepository repository;
  List<MonthlyCategoryBudget> _budgets = const [];
  Map<String, String> _categoryNames = const {};
  Set<String> _activeCategoryIds = const {};
  List<Transaction> _transactions = const [];
  Set<String> _pairedTransactionIds = const {};
  String? _bookId;
  String _currencyCode = 'IDR';
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? error;
  bool saving = false;
  bool copying = false;
  MonthlyBudgetCopyResult? lastCopyResult;

  List<MonthlyCategoryBudget> get budgets => List.unmodifiable(_budgets);
  Map<String, String> get categoryNames => Map.unmodifiable(_categoryNames);
  Map<String, String> get activeCategoryNames => Map.unmodifiable({
    for (final entry in _categoryNames.entries)
      if (_activeCategoryIds.contains(entry.key)) entry.key: entry.value,
  });

  MonthlyBudgetSummary get summary => MonthlyBudgetCalculator.calculate(
    month: month,
    budgets: _budgets,
    transactions: _transactions,
    categoryNamesById: _categoryNames,
    pairedTransactionIds: _pairedTransactionIds,
  );

  Future<void> load({
    required String? bookId,
    required Map<String, String> categoryNames,
    required Set<String> activeCategoryIds,
    required String currencyCode,
    required List<Transaction> transactions,
    Set<String> pairedTransactionIds = const {},
  }) async {
    _bookId = bookId;
    _categoryNames = Map.of(categoryNames);
    _activeCategoryIds = Set.of(activeCategoryIds);
    _currencyCode = currencyCode;
    _transactions = List.of(transactions);
    _pairedTransactionIds = Set.of(pairedTransactionIds);
    _budgets = bookId == null
        ? const []
        : await repository.getAll(includeDeleted: true, bookId: bookId);
    error = null;
    notifyListeners();
  }

  void setMonth(DateTime value) {
    month = DateTime(value.year, value.month);
    notifyListeners();
  }

  void updateTransactions(
    List<Transaction> value, {
    Set<String> pairedTransactionIds = const {},
  }) {
    _transactions = List.of(value);
    _pairedTransactionIds = Set.of(pairedTransactionIds);
  }

  Future<MonthlyBudgetCopyPreview> previewCopy(DateTime sourceMonth) {
    final bookId = _bookId;
    if (bookId == null) throw StateError('No household is active.');
    return repository.previewCopy(
      bookId: bookId,
      sourceMonth: sourceMonth,
      targetMonth: month,
    );
  }

  Future<MonthlyBudgetCopyResult> copyBudgets(
    MonthlyBudgetCopyPreview preview,
  ) async {
    if (copying) throw StateError('A budget copy is already running.');
    if (preview.bookId != _bookId || preview.targetMonth != month) {
      throw StateError('The active household or target month changed.');
    }
    copying = true;
    notifyListeners();
    try {
      final result = await repository.copy(preview);
      _budgets = await repository.getAll(
        includeDeleted: true,
        bookId: preview.bookId,
      );
      lastCopyResult = result;
      error = null;
      return result;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      copying = false;
      notifyListeners();
    }
  }

  Future<void> save({
    MonthlyCategoryBudget? existing,
    required String categoryId,
    required int limitMinor,
    String? note,
  }) async {
    final bookId = _bookId;
    if (bookId == null) throw StateError('No household is active.');
    if (limitMinor <= 0) {
      throw StateError('Budget amount must be greater than zero.');
    }
    if ((note ?? '').length > 120) throw StateError('Budget note is too long.');
    final now = DateTime.now();
    if (saving) return;
    saving = true;
    notifyListeners();
    try {
      final candidate = existing == null
          ? MonthlyCategoryBudget(
              bookId: bookId,
              categoryId: categoryId,
              monthStart: month,
              limitMinor: limitMinor,
              currencyCode: _currencyCode,
              note: note?.trim().isEmpty == true ? null : note?.trim(),
              syncStatus: 'pending',
            )
          : existing.copyWith(
              limitMinor: limitMinor,
              note: note?.trim(),
              clearNote: note?.trim().isEmpty ?? true,
              updatedAt: now,
              version: existing.version + 1,
              syncStatus: 'pending',
            );
      final saved = await repository.save(candidate);
      _budgets = [
        for (final item in _budgets)
          if (item.id != existing?.id && item.id != saved.id) item,
        saved,
      ];
      error = null;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> delete(MonthlyCategoryBudget budget) async {
    await repository.delete(budget);
    final now = DateTime.now();
    _budgets = [
      for (final item in _budgets)
        item.id == budget.id
            ? item.copyWith(
                deletedAt: now,
                updatedAt: now,
                version: item.version + 1,
                syncStatus: 'pending',
              )
            : item,
    ];
    notifyListeners();
  }
}
