import '../../transactions/domain/entities/transaction.dart';
import '../../tithe/domain/tithe_policy.dart';

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

class FinancialAsset {
  const FinancialAsset({
    required this.type,
    int? amount,
    int? value,
    this.isCash = false,
  }) : amount = amount ?? value ?? 0;

  final String type;
  final int amount;
  final bool isCash;

  int get value => amount;
}

class FinancialLiability {
  const FinancialLiability({required this.type, int? amount, int? value})
    : amount = amount ?? value ?? 0;

  final String type;
  final int amount;

  int get value => amount;
}

typedef AssetBalance = FinancialAsset;
typedef LiabilityBalance = FinancialLiability;

class AssetAllocation {
  const AssetAllocation({
    required this.type,
    required this.amount,
    required this.share,
  });

  final String type;
  final int amount;

  /// Value from 0 to 1 of total assets.
  final double share;

  double get percentage => share * 100;
}

typedef AssetAllocationByType = AssetAllocation;

class LiabilityTotal {
  const LiabilityTotal({required this.type, required this.amount});

  final String type;
  final int amount;
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
    this.totalAssets = 0,
    this.totalLiabilities = 0,
    this.netWorth = 0,
    this.cash = 0,
    this.availableCash = 0,
    this.availableCashAfterPendingTithe = 0,
    this.assetAllocation = const [],
    this.liabilityTotals = const [],
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

  /// Decimal representation of the applied percentage.
  final double titheRate;

  final int monthlyTithe;

  int get periodIncome => monthlyIncome;

  int get periodExpenses => monthlyExpenses;

  int get periodNetCashFlow => monthlyNetCashFlow;

  int get periodTithe => monthlyTithe;

  /// All transaction types recorded within the period.
  final int activityCount;

  final List<CategorySpending> spendingByCategory;

  final int totalAssets;
  final int totalLiabilities;
  final int netWorth;
  final int cash;
  final int availableCash;
  final int availableCashAfterPendingTithe;
  final List<AssetAllocation> assetAllocation;
  final List<LiabilityTotal> liabilityTotals;

  int get pendingTithe => monthlyTithe;

  int get totalCash => cash;

  int get availableAfterTithe => availableCashAfterPendingTithe;

  List<LiabilityTotal> get liabilitiesByType => liabilityTotals;

  CategorySpending? get topCategory {
    if (spendingByCategory.isEmpty) {
      return null;
    }

    return spendingByCategory.first;
  }

  factory FinancialSummary.calculate({
    required Iterable<Transaction> transactions,
    required DateTime referenceDate,
    TithePolicy? tithePolicy,
    double? titheRate,
    Iterable<FinancialAsset> assets = const [],
    Iterable<FinancialLiability> liabilities = const [],
  }) {
    return FinancialSummary.forPeriod(
      transactions: transactions,
      periodStart: DateTime(referenceDate.year, referenceDate.month),
      periodEndExclusive: DateTime(referenceDate.year, referenceDate.month + 1),
      tithePolicy: tithePolicy,
      titheRate: titheRate,
      assets: assets,
      liabilities: liabilities,
    );
  }

  factory FinancialSummary.forPeriod({
    required Iterable<Transaction> transactions,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    TithePolicy? tithePolicy,
    double? titheRate,
    Iterable<FinancialAsset> assets = const [],
    Iterable<FinancialLiability> liabilities = const [],
  }) {
    if (!periodEndExclusive.isAfter(periodStart)) {
      throw ArgumentError('The financial period end must be after its start.');
    }

    final resolvedTitheRate =
        titheRate ??
        (tithePolicy ?? TithePolicy.defaultPolicy).rateFor(periodStart);

    if (resolvedTitheRate < 0 || resolvedTitheRate > 1) {
      throw ArgumentError.value(
        resolvedTitheRate,
        'titheRate',
        'Tithe rate must be between 0 and 1.',
      );
    }

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

    var periodIncome = 0;
    var periodExpenses = 0;

    final categoryTotals = <String, int>{};

    for (final transaction in periodTransactions) {
      switch (transaction.type) {
        case TransactionType.income:
          periodIncome += transaction.amount;

        case TransactionType.expense:
          periodExpenses += transaction.amount;

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

    final periodNetCashFlow = periodIncome - periodExpenses;

    final savingsRate = periodIncome == 0
        ? 0.0
        : periodNetCashFlow / periodIncome;

    final spendingByCategory =
        categoryTotals.entries
            .map(
              (entry) => CategorySpending(
                category: entry.key,
                amount: entry.value,
                share: periodExpenses == 0 ? 0 : entry.value / periodExpenses,
              ),
            )
            .toList()
          ..sort((left, right) => right.amount.compareTo(left.amount));

    final assetTotals = <String, ({String type, int amount})>{};
    var totalAssets = 0;
    var cash = 0;
    for (final asset in assets) {
      final type = asset.type.trim().isEmpty ? 'Other' : asset.type.trim();
      final key = type.toLowerCase();
      final current = assetTotals[key];
      assetTotals[key] = (
        type: current?.type ?? type,
        amount: (current?.amount ?? 0) + asset.amount,
      );
      totalAssets += asset.amount;
      if (asset.isCash || key == 'cash') {
        cash += asset.amount;
      }
    }

    final liabilityTotalsByType = <String, ({String type, int amount})>{};
    var totalLiabilities = 0;
    for (final liability in liabilities) {
      final type = liability.type.trim().isEmpty
          ? 'Other liabilities'
          : liability.type.trim();
      final key = type.toLowerCase();
      final current = liabilityTotalsByType[key];
      liabilityTotalsByType[key] = (
        type: current?.type ?? type,
        amount: (current?.amount ?? 0) + liability.amount,
      );
      totalLiabilities += liability.amount;
    }

    final assetAllocation =
        assetTotals.values
            .map(
              (entry) => AssetAllocation(
                type: entry.type,
                amount: entry.amount,
                share: totalAssets == 0 ? 0 : entry.amount / totalAssets,
              ),
            )
            .toList()
          ..sort((left, right) => right.amount.compareTo(left.amount));

    final liabilityTotalsByClass =
        liabilityTotalsByType.values
            .map(
              (entry) => LiabilityTotal(type: entry.type, amount: entry.amount),
            )
            .toList()
          ..sort((left, right) => right.amount.compareTo(left.amount));
    final availableCash = cash - totalLiabilities;

    return FinancialSummary(
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      recordedBalance: allTimeIncome - allTimeExpenses,
      monthlyIncome: periodIncome,
      monthlyExpenses: periodExpenses,
      monthlyNetCashFlow: periodNetCashFlow,
      savingsRate: savingsRate,
      titheRate: resolvedTitheRate,
      monthlyTithe: (periodIncome * resolvedTitheRate).round(),
      activityCount: periodTransactions.length,
      spendingByCategory: List<CategorySpending>.unmodifiable(
        spendingByCategory,
      ),
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      netWorth: totalAssets - totalLiabilities,
      cash: cash,
      availableCash: availableCash,
      availableCashAfterPendingTithe:
          availableCash - (periodIncome * resolvedTitheRate).round(),
      assetAllocation: List<AssetAllocation>.unmodifiable(assetAllocation),
      liabilityTotals: List<LiabilityTotal>.unmodifiable(
        liabilityTotalsByClass,
      ),
    );
  }
}
