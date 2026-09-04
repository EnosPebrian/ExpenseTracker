enum FinancialStatementType { monthly, annual }

enum FinancialStatementScope { household, account }

enum StatementTransactionKind {
  income,
  expense,
  transferIn,
  transferOut,
  legacyTransfer,
  assetMovement,
}

class StatementPeriod {
  const StatementPeriod({
    required this.start,
    required this.endExclusive,
    required this.label,
    required this.fileKey,
  });

  final DateTime start;
  final DateTime endExclusive;
  final String label;
  final String fileKey;

  factory StatementPeriod.month(DateTime month) {
    final start = DateTime(month.year, month.month);
    return StatementPeriod(
      start: start,
      endExclusive: DateTime(month.year, month.month + 1),
      label: '${monthNames[month.month - 1]} ${month.year}',
      fileKey:
          '${month.year.toString().padLeft(4, '0')}-'
          '${month.month.toString().padLeft(2, '0')}',
    );
  }

  factory StatementPeriod.year(int year) => StatementPeriod(
    start: DateTime(year),
    endExclusive: DateTime(year + 1),
    label: '$year',
    fileKey: '$year',
  );

  static const monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

class CurrencyStatementSummary {
  const CurrencyStatementSummary({
    required this.currencyCode,
    required this.openingBalance,
    required this.closingBalance,
    required this.income,
    required this.expense,
    required this.tithe,
    required this.transfersIn,
    required this.transfersOut,
  });

  final String currencyCode;
  final int openingBalance;
  final int closingBalance;
  final int income;
  final int expense;
  final int tithe;
  final int transfersIn;
  final int transfersOut;

  int get netCashFlow => income - expense;
  int get transferNet => transfersIn - transfersOut;
}

class AccountStatementSummary {
  const AccountStatementSummary({
    required this.accountId,
    required this.accountName,
    required this.currencyCode,
    required this.openingBalance,
    required this.closingBalance,
    required this.inflow,
    required this.outflow,
    required this.transfersIn,
    required this.transfersOut,
  });

  final String accountId;
  final String accountName;
  final String currencyCode;
  final int openingBalance;
  final int closingBalance;
  final int inflow;
  final int outflow;
  final int transfersIn;
  final int transfersOut;

  int get expectedClosing =>
      openingBalance + inflow - outflow + transfersIn - transfersOut;
  bool get balancesReconcile => expectedClosing == closingBalance;
}

class CategoryStatementSummary {
  const CategoryStatementSummary({
    required this.category,
    required this.currencyCode,
    required this.amount,
    required this.share,
    required this.monthlyAverage,
  });

  final String category;
  final String currencyCode;
  final int amount;
  final double share;
  final int monthlyAverage;
}

class BudgetStatementSummary {
  const BudgetStatementSummary({
    required this.category,
    required this.currencyCode,
    required this.budget,
    required this.actual,
  });

  final String category;
  final String currencyCode;
  final int budget;
  final int actual;

  int get remaining => budget - actual;
  double get usage => budget == 0 ? 0 : actual / budget;
  String get status => actual > budget
      ? 'Over budget'
      : usage >= .8
      ? 'Near limit'
      : 'On track';
}

class MonthlyStatementSummary {
  const MonthlyStatementSummary({
    required this.month,
    required this.currencyCode,
    required this.income,
    required this.expense,
    required this.tithe,
  });

  final DateTime month;
  final String currencyCode;
  final int income;
  final int expense;
  final int tithe;

  int get netCashFlow => income - expense;
}

class StatementTransactionRow {
  const StatementTransactionRow({
    required this.transactionId,
    required this.date,
    required this.account,
    required this.description,
    required this.category,
    required this.currencyCode,
    required this.kind,
    required this.amount,
    required this.balanceEffect,
    this.runningBalance,
  });

  final String transactionId;
  final DateTime date;
  final String account;
  final String description;
  final String category;
  final String currencyCode;
  final StatementTransactionKind kind;
  final int amount;
  final int balanceEffect;
  final int? runningBalance;
}

class FinancialStatement {
  FinancialStatement({
    required this.type,
    required this.scope,
    required this.period,
    required this.generatedAt,
    required this.householdName,
    required this.scopeLabel,
    required Iterable<CurrencyStatementSummary> currencySummaries,
    required Iterable<AccountStatementSummary> accountSummaries,
    required Iterable<CategoryStatementSummary> incomeCategories,
    required Iterable<CategoryStatementSummary> expenseCategories,
    required Iterable<BudgetStatementSummary> budgets,
    required Iterable<MonthlyStatementSummary> monthlySummaries,
    required Iterable<StatementTransactionRow> transactions,
    this.localDataWarning = false,
    this.yearEndNetWorthNote,
  }) : currencySummaries = List.unmodifiable(currencySummaries),
       accountSummaries = List.unmodifiable(accountSummaries),
       incomeCategories = List.unmodifiable(incomeCategories),
       expenseCategories = List.unmodifiable(expenseCategories),
       budgets = List.unmodifiable(budgets),
       monthlySummaries = List.unmodifiable(monthlySummaries),
       transactions = List.unmodifiable(transactions);

  final FinancialStatementType type;
  final FinancialStatementScope scope;
  final StatementPeriod period;
  final DateTime generatedAt;
  final String householdName;
  final String scopeLabel;
  final List<CurrencyStatementSummary> currencySummaries;
  final List<AccountStatementSummary> accountSummaries;
  final List<CategoryStatementSummary> incomeCategories;
  final List<CategoryStatementSummary> expenseCategories;
  final List<BudgetStatementSummary> budgets;
  final List<MonthlyStatementSummary> monthlySummaries;
  final List<StatementTransactionRow> transactions;
  final bool localDataWarning;
  final String? yearEndNetWorthNote;

  bool get isEmpty => transactions.isEmpty;
  String get title => type == FinancialStatementType.monthly
      ? 'Monthly Financial Statement'
      : 'Annual Financial Statement';
}
