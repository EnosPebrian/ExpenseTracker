import '../../analytics/domain/financial_summary.dart';
import '../../budgets/domain/entities/monthly_category_budget.dart';
import '../../budgets/domain/services/monthly_budget_calculator.dart';
import '../../master_data/domain/entities/account.dart';
import '../../master_data/domain/entities/financial_book.dart';
import '../../master_data/domain/services/account_balance_calculator.dart';
import '../../tithe/domain/tithe_policy.dart';
import '../../transactions/domain/entities/internal_transfer_link.dart';
import '../../transactions/domain/entities/transaction.dart';
import 'financial_statement.dart';

class FinancialStatementGenerator {
  const FinancialStatementGenerator({this.tithePolicy, this.clock});

  final TithePolicy? tithePolicy;
  final DateTime Function()? clock;

  FinancialStatement generate({
    required FinancialStatementType type,
    required FinancialStatementScope scope,
    required DateTime selectedPeriod,
    required FinancialBook book,
    required List<Account> accounts,
    required List<Transaction> transactions,
    required List<InternalTransferLink> transferLinks,
    required List<MonthlyCategoryBudget> budgets,
    required Map<String, String> categoryNamesById,
    String? accountId,
    bool localDataWarning = false,
  }) {
    final period = type == FinancialStatementType.monthly
        ? StatementPeriod.month(selectedPeriod)
        : StatementPeriod.year(selectedPeriod.year);
    final selectedAccount = scope == FinancialStatementScope.account
        ? accounts.where((account) => account.id == accountId).firstOrNull
        : null;
    if (scope == FinancialStatementScope.account && selectedAccount == null) {
      throw StateError('Select an account before generating the statement.');
    }

    final activeLinks = transferLinks
        .where((link) => link.deletedAt == null)
        .toList(growable: false);
    final linkedByTransaction = <String, InternalTransferLink>{
      for (final link in activeLinks)
        for (final id in link.transactionIds) id: link,
    };
    final sourceTransactions = transactions
        .where((transaction) => transaction.deletedAt == null)
        .where(
          (transaction) =>
              transaction.bookId == null || transaction.bookId == book.id,
        )
        .where(
          (transaction) =>
              selectedAccount == null ||
              AccountBalanceCalculator.belongsToAccount(
                selectedAccount,
                transaction,
              ),
        )
        .toList(growable: false);
    final periodTransactions = sourceTransactions
        .where(
          (transaction) =>
              !transaction.date.isBefore(period.start) &&
              transaction.date.isBefore(period.endExclusive),
        )
        .toList(growable: false);

    final scopedAccounts = selectedAccount == null
        ? accounts
              .where(
                (account) =>
                    account.bookId == null || account.bookId == book.id,
              )
              .where(
                (account) =>
                    account.deletedAt == null ||
                    sourceTransactions.any(
                      (transaction) =>
                          AccountBalanceCalculator.belongsToAccount(
                            account,
                            transaction,
                          ),
                    ),
              )
              .toList(growable: false)
        : <Account>[selectedAccount];
    final accountByName = {
      for (final account in accounts)
        account.name.trim().toLowerCase(): account,
    };
    final accountById = {for (final account in accounts) account.id: account};
    final accountSummaries = scopedAccounts
        .map(
          (account) => _accountSummary(
            account: account,
            transactions: sourceTransactions,
            periodTransactions: periodTransactions,
            period: period,
            linkedByTransaction: linkedByTransaction,
          ),
        )
        .toList(growable: false);

    final currencies = <String>{
      for (final account in scopedAccounts) account.currencyCode,
      if (scopedAccounts.isEmpty) book.baseCurrencyCode,
    }.toList()..sort();
    final monthlySummaries = type == FinancialStatementType.annual
        ? _monthlySummaries(
            period: period,
            currencies: currencies,
            transactions: sourceTransactions,
            accountByName: accountByName,
            baseCurrency: book.baseCurrencyCode,
            transferLinks: activeLinks,
          )
        : const <MonthlyStatementSummary>[];
    final currencySummaries = currencies
        .map((currency) {
          final currencyTransactions = sourceTransactions
              .where(
                (transaction) =>
                    _currencyFor(
                      transaction,
                      accountByName,
                      book.baseCurrencyCode,
                    ) ==
                    currency,
              )
              .toList(growable: false);
          final summary = FinancialSummary.forPeriod(
            transactions: currencyTransactions,
            periodStart: period.start,
            periodEndExclusive: period.endExclusive,
            tithePolicy: tithePolicy ?? TithePolicy.defaultPolicy,
            transferLinks: activeLinks,
          );
          final currencyAccounts = accountSummaries.where(
            (account) => account.currencyCode == currency,
          );
          final transferTotals = _transferTotals(
            currency: currency,
            period: period,
            transactions: periodTransactions,
            links: activeLinks,
          );
          final annualTithe = type == FinancialStatementType.annual
              ? monthlySummaries
                    .where((month) => month.currencyCode == currency)
                    .fold<int>(0, (total, month) => total + month.tithe)
              : summary.periodTithe;
          return CurrencyStatementSummary(
            currencyCode: currency,
            openingBalance: currencyAccounts.fold(
              0,
              (total, account) => total + account.openingBalance,
            ),
            closingBalance: currencyAccounts.fold(
              0,
              (total, account) => total + account.closingBalance,
            ),
            income: summary.periodIncome,
            expense: summary.periodExpenses,
            tithe: annualTithe,
            transfersIn: transferTotals.$1,
            transfersOut: transferTotals.$2,
          );
        })
        .toList(growable: false);

    final monthCount = type == FinancialStatementType.annual ? 12 : 1;
    final pairedIds = linkedByTransaction.keys.toSet();
    final incomeCategories = _categorySummaries(
      type: TransactionType.income,
      transactions: periodTransactions,
      pairedIds: pairedIds,
      accountByName: accountByName,
      baseCurrency: book.baseCurrencyCode,
      monthCount: monthCount,
    );
    final expenseCategories = _categorySummaries(
      type: TransactionType.expense,
      transactions: periodTransactions,
      pairedIds: pairedIds,
      accountByName: accountByName,
      baseCurrency: book.baseCurrencyCode,
      monthCount: monthCount,
    );
    final budgetSummaries = selectedAccount == null
        ? _budgetSummaries(
            period: period,
            budgets: budgets,
            transactions: sourceTransactions,
            categoryNamesById: categoryNamesById,
            pairedIds: pairedIds,
          )
        : const <BudgetStatementSummary>[];
    final rows = _ledgerRows(
      periodTransactions: periodTransactions,
      account: selectedAccount,
      period: period,
      linkedByTransaction: linkedByTransaction,
      accountById: accountById,
      accountByName: accountByName,
      baseCurrency: book.baseCurrencyCode,
      initialRunningBalance: selectedAccount == null
          ? null
          : accountSummaries.single.openingBalance,
    );

    return FinancialStatement(
      type: type,
      scope: scope,
      period: period,
      generatedAt: (clock ?? DateTime.now)(),
      householdName: book.name,
      scopeLabel: selectedAccount?.name ?? book.name,
      currencySummaries: currencySummaries,
      accountSummaries: accountSummaries,
      incomeCategories: incomeCategories,
      expenseCategories: expenseCategories,
      budgets: budgetSummaries,
      monthlySummaries: monthlySummaries,
      transactions: rows,
      localDataWarning: localDataWarning,
      yearEndNetWorthNote: type == FinancialStatementType.annual
          ? 'Historical year-end asset valuation is unavailable; no net-worth estimate is shown.'
          : null,
    );
  }

  AccountStatementSummary _accountSummary({
    required Account account,
    required List<Transaction> transactions,
    required List<Transaction> periodTransactions,
    required StatementPeriod period,
    required Map<String, InternalTransferLink> linkedByTransaction,
  }) {
    final opening = AccountBalanceCalculator.calculateAsOf(
      account: account,
      transactions: transactions,
      endExclusive: period.start,
    );
    final closing = AccountBalanceCalculator.calculateAsOf(
      account: account,
      transactions: transactions,
      endExclusive: period.endExclusive,
    );
    var inflow = 0;
    var outflow = 0;
    var transfersIn = 0;
    var transfersOut = 0;
    for (final transaction in periodTransactions) {
      if (!AccountBalanceCalculator.belongsToAccount(account, transaction)) {
        continue;
      }
      final link = linkedByTransaction[transaction.id];
      if (link != null) {
        if (link.incomingTransactionId == transaction.id) {
          transfersIn += transaction.amount;
        } else {
          transfersOut += transaction.amount;
        }
        continue;
      }
      final effect = AccountBalanceCalculator.cashEffect(transaction);
      if (effect >= 0) {
        inflow += effect;
      } else {
        outflow += -effect;
      }
    }
    return AccountStatementSummary(
      accountId: account.id,
      accountName: account.name,
      currencyCode: account.currencyCode,
      openingBalance: opening,
      closingBalance: closing,
      inflow: inflow,
      outflow: outflow,
      transfersIn: transfersIn,
      transfersOut: transfersOut,
    );
  }

  List<MonthlyStatementSummary> _monthlySummaries({
    required StatementPeriod period,
    required List<String> currencies,
    required List<Transaction> transactions,
    required Map<String, Account> accountByName,
    required String baseCurrency,
    required List<InternalTransferLink> transferLinks,
  }) {
    final result = <MonthlyStatementSummary>[];
    for (var month = 1; month <= 12; month++) {
      final start = DateTime(period.start.year, month);
      final end = DateTime(period.start.year, month + 1);
      for (final currency in currencies) {
        final summary = FinancialSummary.forPeriod(
          transactions: transactions.where(
            (transaction) =>
                _currencyFor(transaction, accountByName, baseCurrency) ==
                currency,
          ),
          periodStart: start,
          periodEndExclusive: end,
          tithePolicy: tithePolicy ?? TithePolicy.defaultPolicy,
          transferLinks: transferLinks,
        );
        result.add(
          MonthlyStatementSummary(
            month: start,
            currencyCode: currency,
            income: summary.periodIncome,
            expense: summary.periodExpenses,
            tithe: summary.periodTithe,
          ),
        );
      }
    }
    return result;
  }

  (int, int) _transferTotals({
    required String currency,
    required StatementPeriod period,
    required List<Transaction> transactions,
    required List<InternalTransferLink> links,
  }) {
    final byId = {
      for (final transaction in transactions) transaction.id: transaction,
    };
    var incoming = 0;
    var outgoing = 0;
    for (final link in links.where((link) => link.currencyCode == currency)) {
      final outgoingTransaction = byId[link.outgoingTransactionId];
      final incomingTransaction = byId[link.incomingTransactionId];
      if (outgoingTransaction != null &&
          !outgoingTransaction.date.isBefore(period.start) &&
          outgoingTransaction.date.isBefore(period.endExclusive)) {
        outgoing += link.amount;
      }
      if (incomingTransaction != null &&
          !incomingTransaction.date.isBefore(period.start) &&
          incomingTransaction.date.isBefore(period.endExclusive)) {
        incoming += link.amount;
      }
    }
    return (incoming, outgoing);
  }

  List<CategoryStatementSummary> _categorySummaries({
    required TransactionType type,
    required List<Transaction> transactions,
    required Set<String> pairedIds,
    required Map<String, Account> accountByName,
    required String baseCurrency,
    required int monthCount,
  }) {
    final totals = <(String, String), int>{};
    final currencyTotals = <String, int>{};
    for (final transaction in transactions) {
      if (transaction.type != type || pairedIds.contains(transaction.id)) {
        continue;
      }
      final currency = _currencyFor(transaction, accountByName, baseCurrency);
      final key = (
        transaction.category.trim().isEmpty ? 'Other' : transaction.category,
        currency,
      );
      totals[key] = (totals[key] ?? 0) + transaction.amount;
      currencyTotals[currency] =
          (currencyTotals[currency] ?? 0) + transaction.amount;
    }
    final result = totals.entries
        .map(
          (entry) => CategoryStatementSummary(
            category: entry.key.$1,
            currencyCode: entry.key.$2,
            amount: entry.value,
            share: (currencyTotals[entry.key.$2] ?? 0) == 0
                ? 0
                : entry.value / currencyTotals[entry.key.$2]!,
            monthlyAverage: entry.value ~/ monthCount,
          ),
        )
        .toList();
    result.sort((left, right) {
      final currency = left.currencyCode.compareTo(right.currencyCode);
      return currency != 0 ? currency : right.amount.compareTo(left.amount);
    });
    return result;
  }

  List<BudgetStatementSummary> _budgetSummaries({
    required StatementPeriod period,
    required List<MonthlyCategoryBudget> budgets,
    required List<Transaction> transactions,
    required Map<String, String> categoryNamesById,
    required Set<String> pairedIds,
  }) {
    final totals = <(String, String), (int, int)>{};
    var month = period.start;
    while (month.isBefore(period.endExclusive)) {
      final summary = MonthlyBudgetCalculator.calculate(
        month: month,
        budgets: budgets,
        transactions: transactions,
        categoryNamesById: categoryNamesById,
        pairedTransactionIds: pairedIds,
      );
      for (final item in summary.categories) {
        final key = (item.categoryName, item.budget.currencyCode);
        final current = totals[key] ?? (0, 0);
        totals[key] = (
          current.$1 + item.budget.limitMinor,
          current.$2 + item.spentMinor,
        );
      }
      month = DateTime(month.year, month.month + 1);
    }
    final result = totals.entries
        .map(
          (entry) => BudgetStatementSummary(
            category: entry.key.$1,
            currencyCode: entry.key.$2,
            budget: entry.value.$1,
            actual: entry.value.$2,
          ),
        )
        .toList();
    result.sort((left, right) => right.actual.compareTo(left.actual));
    return result;
  }

  List<StatementTransactionRow> _ledgerRows({
    required List<Transaction> periodTransactions,
    required Account? account,
    required StatementPeriod period,
    required Map<String, InternalTransferLink> linkedByTransaction,
    required Map<String, Account> accountById,
    required Map<String, Account> accountByName,
    required String baseCurrency,
    required int? initialRunningBalance,
  }) {
    final sorted = List<Transaction>.of(periodTransactions)
      ..sort((left, right) {
        final date = left.date.compareTo(right.date);
        if (date != 0) return date;
        final created = left.createdAt.compareTo(right.createdAt);
        return created != 0 ? created : left.id.compareTo(right.id);
      });
    var running = account == null ? null : initialRunningBalance;
    final rows = <StatementTransactionRow>[];
    for (final transaction in sorted) {
      final link = linkedByTransaction[transaction.id];
      var description = transaction.title;
      late final StatementTransactionKind kind;
      final effect = AccountBalanceCalculator.cashEffect(transaction);
      if (link != null) {
        if (link.incomingTransactionId == transaction.id) {
          kind = StatementTransactionKind.transferIn;
          description =
              'Transfer from ${accountById[link.sourceAccountId]?.name ?? 'another account'}';
        } else {
          kind = StatementTransactionKind.transferOut;
          description =
              'Transfer to ${accountById[link.destinationAccountId]?.name ?? 'another account'}';
        }
      } else {
        kind = switch (transaction.type) {
          TransactionType.income => StatementTransactionKind.income,
          TransactionType.expense => StatementTransactionKind.expense,
          TransactionType.transfer => StatementTransactionKind.legacyTransfer,
          TransactionType.assetConversion =>
            StatementTransactionKind.assetMovement,
        };
      }
      if (running != null) running += effect;
      rows.add(
        StatementTransactionRow(
          transactionId: transaction.id,
          date: transaction.date,
          account: transaction.account,
          description: description,
          category: kind == StatementTransactionKind.legacyTransfer
              ? 'Legacy transfer (direction unavailable)'
              : transaction.category,
          currencyCode: _currencyFor(transaction, accountByName, baseCurrency),
          kind: kind,
          amount: transaction.amount,
          balanceEffect: effect,
          runningBalance: running,
        ),
      );
    }
    return rows;
  }

  static String _currencyFor(
    Transaction transaction,
    Map<String, Account> accountByName,
    String fallback,
  ) {
    for (final account in accountByName.values) {
      if (AccountBalanceCalculator.belongsToAccount(account, transaction)) {
        return account.currencyCode;
      }
    }
    return fallback;
  }
}
