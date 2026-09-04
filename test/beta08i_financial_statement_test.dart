import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/budgets/domain/entities/monthly_category_budget.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/reports/data/financial_statement_pdf_renderer.dart';
import 'package:pilgrim_tracker/features/reports/domain/financial_statement.dart';
import 'package:pilgrim_tracker/features/reports/domain/financial_statement_generator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  group('BETA-08I financial statement generator', () {
    test(
      'monthly household reuses reporting, transfer, tithe, and balance semantics',
      () {
        final fixture = _fixture();
        final statement = fixture.generate();

        expect(statement.type, FinancialStatementType.monthly);
        expect(statement.scope, FinancialStatementScope.household);
        final idr = statement.currencySummaries.single;
        expect(idr.openingBalance, 10000000);
        expect(idr.income, 8000000);
        expect(idr.expense, 1500000);
        expect(idr.netCashFlow, 6500000);
        expect(idr.tithe, 1040000);
        expect(idr.transfersIn, 2000000);
        expect(idr.transfersOut, 2000000);
        expect(idr.closingBalance, 16500000);
        expect(
          statement.accountSummaries.every((item) => item.balancesReconcile),
          isTrue,
        );
        expect(statement.expenseCategories.map((item) => item.amount), [
          1000000,
          500000,
        ]);
      },
    );

    test(
      'account statement exposes transfer movement and reconciled running balance',
      () {
        final fixture = _fixture();
        final statement = fixture.generate(
          scope: FinancialStatementScope.account,
          accountId: fixture.accountA.id,
        );

        final summary = statement.accountSummaries.single;
        expect(summary.openingBalance, 10000000);
        expect(summary.inflow, 8000000);
        expect(summary.outflow, 1500000);
        expect(summary.transfersOut, 2000000);
        expect(summary.closingBalance, 14500000);
        expect(summary.balancesReconcile, isTrue);
        expect(statement.transactions.last.runningBalance, 14500000);
        expect(
          statement.transactions
              .where((row) => row.kind == StatementTransactionKind.transferOut)
              .single
              .description,
          'Transfer to Grace Bank',
        );
      },
    );

    test('budget actual excludes canonical transfer legs', () {
      final fixture = _fixture(
        groceryAmount: 4000000,
        utilityAmount: 0,
        groceryBudget: 5000000,
      );
      final budget = fixture.generate().budgets.single;
      expect(budget.budget, 5000000);
      expect(budget.actual, 4000000);
      expect(budget.remaining, 1000000);
      expect(budget.usage, .8);
    });

    test('multi-currency household summaries never combine currencies', () {
      final fixture = _fixture(includeUsd: true);
      final statement = fixture.generate();
      expect(statement.currencySummaries.map((item) => item.currencyCode), [
        'IDR',
        'USD',
      ]);
      expect(
        statement.currencySummaries
            .singleWhere((item) => item.currencyCode == 'USD')
            .income,
        2000,
      );
      expect(
        statement.currencySummaries
            .singleWhere((item) => item.currencyCode == 'IDR')
            .income,
        8000000,
      );
    });

    test(
      'month boundaries, deleted rows, and leap day use local calendar dates',
      () {
        final fixture = _fixture(
          extraTransactions: [
            _transaction(
              'july',
              DateTime(2026, 7, 31),
              99,
              TransactionType.income,
            ),
            _transaction(
              'september',
              DateTime(2026, 9),
              77,
              TransactionType.income,
            ),
            _transaction(
              'deleted',
              DateTime(2026, 8, 31),
              88,
              TransactionType.income,
              deletedAt: DateTime(2026, 9),
            ),
          ],
        );
        final august = fixture.generate();
        expect(
          august.transactions.any((row) => row.transactionId == 'july'),
          isFalse,
        );
        expect(
          august.transactions.any((row) => row.transactionId == 'september'),
          isFalse,
        );
        expect(
          august.transactions.any((row) => row.transactionId == 'deleted'),
          isFalse,
        );

        final leapFixture = _fixture(
          month: DateTime(2028, 2),
          replaceTransactions: [
            _transaction(
              'leap',
              DateTime(2028, 2, 29),
              100,
              TransactionType.income,
            ),
            _transaction(
              'march',
              DateTime(2028, 3),
              200,
              TransactionType.income,
            ),
          ],
        );
        expect(
          leapFixture.generate().transactions.single.transactionId,
          'leap',
        );
      },
    );

    test(
      'annual statement includes twelve zero-capable monthly rows and aggregates categories',
      () {
        final transactions = <Transaction>[
          for (var month = 1; month <= 12; month++)
            _transaction(
              'income-$month',
              DateTime(2026, month, 2),
              month * 1000,
              TransactionType.income,
              category: 'Salary',
            ),
          for (var month = 1; month <= 12; month++)
            _transaction(
              'expense-$month',
              DateTime(2026, month, 3),
              month * 100,
              TransactionType.expense,
              category: 'Food',
            ),
        ];
        final fixture = _fixture(replaceTransactions: transactions);
        final statement = fixture.generate(type: FinancialStatementType.annual);
        expect(statement.monthlySummaries.length, 12);
        expect(statement.currencySummaries.single.income, 78000);
        expect(statement.currencySummaries.single.expense, 7800);
        expect(statement.incomeCategories.single.amount, 78000);
        expect(statement.expenseCategories.single.monthlyAverage, 650);
        expect(statement.period.start, DateTime(2026));
        expect(statement.period.endExclusive, DateTime(2027));
      },
    );

    test('empty period generates stable balances and a valid PDF', () async {
      final fixture = _fixture(
        replaceTransactions: const [],
        month: DateTime(2030, 4),
      );
      final statement = fixture.generate();
      expect(statement.isEmpty, isTrue);
      expect(statement.accountSummaries.first.openingBalance, 10000000);
      expect(statement.accountSummaries.first.closingBalance, 10000000);

      final renderer = FinancialStatementPdfRenderer();
      final bytes = await renderer.render(statement);
      expect(bytes.length, greaterThan(1000));
      expect(latin1.decode(bytes.take(4).toList()), '%PDF');
    });

    test(
      'PDF paginates a large ledger and sanitizes account filenames',
      () async {
        final transactions = <Transaction>[
          for (var index = 0; index < 5000; index++)
            _transaction(
              'large-$index',
              DateTime(2026, (index % 12) + 1, (index % 28) + 1),
              index + 1,
              index.isEven ? TransactionType.income : TransactionType.expense,
            ),
        ];
        final fixture = _fixture(replaceTransactions: transactions);
        final statement = fixture.generate(
          type: FinancialStatementType.annual,
          scope: FinancialStatementScope.account,
          accountId: fixture.accountA.id,
        );
        expect(statement.transactions.length, 5000);
        final renderer = FinancialStatementPdfRenderer();
        expect(
          renderer.suggestedFileName(statement),
          'PilgrimTracker_Enos-Bank_Annual_Statement_2026.pdf',
        );
        expect(
          FinancialStatementPdfRenderer.sanitizeFileSegment(' BCA / Enos:*? '),
          'BCA-Enos',
        );
        final bytes = await renderer.render(statement);
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(raw).length,
          greaterThan(1),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'legacy transfer stays visible but has no fabricated balance direction',
      () {
        final legacy = _transaction(
          'legacy',
          DateTime(2026, 8, 10),
          300000,
          TransactionType.transfer,
          category: 'Transfer',
        );
        final fixture = _fixture(replaceTransactions: [legacy]);
        final statement = fixture.generate(
          scope: FinancialStatementScope.account,
          accountId: fixture.accountA.id,
        );
        final row = statement.transactions.single;
        expect(row.kind, StatementTransactionKind.legacyTransfer);
        expect(row.balanceEffect, 0);
        expect(statement.accountSummaries.single.closingBalance, 10000000);
      },
    );
  });
}

class _Fixture {
  _Fixture({
    required this.month,
    required this.book,
    required this.accounts,
    required this.transactions,
    required this.links,
    required this.budgets,
  });

  final DateTime month;
  final FinancialBook book;
  final List<Account> accounts;
  final List<Transaction> transactions;
  final List<InternalTransferLink> links;
  final List<MonthlyCategoryBudget> budgets;

  Account get accountA => accounts.first;

  FinancialStatement generate({
    FinancialStatementType type = FinancialStatementType.monthly,
    FinancialStatementScope scope = FinancialStatementScope.household,
    String? accountId,
  }) => const FinancialStatementGenerator().generate(
    type: type,
    scope: scope,
    selectedPeriod: month,
    book: book,
    accounts: accounts,
    transactions: transactions,
    transferLinks: links,
    budgets: budgets,
    categoryNamesById: const {'groceries-category': 'Groceries'},
    accountId: accountId,
  );
}

_Fixture _fixture({
  DateTime? month,
  int groceryAmount = 1000000,
  int utilityAmount = 500000,
  int? groceryBudget = 5000000,
  bool includeUsd = false,
  List<Transaction> extraTransactions = const [],
  List<Transaction>? replaceTransactions,
}) {
  final selectedMonth = month ?? DateTime(2026, 8);
  final book = FinancialBook(
    id: 'book',
    name: 'Enos & Grace',
    baseCurrencyCode: 'IDR',
  );
  final accountA = Account(
    id: 'account-a',
    bookId: book.id,
    name: 'Enos Bank',
    accountType: AccountType.bank,
    currencyCode: 'IDR',
    openingBalance: 10000000,
    openingBalanceDate: DateTime(2026, 1),
  );
  final accountB = Account(
    id: 'account-b',
    bookId: book.id,
    name: 'Grace Bank',
    accountType: AccountType.bank,
    currencyCode: 'IDR',
    openingBalance: 0,
    openingBalanceDate: DateTime(2026, 1),
  );
  final outgoing = _transaction(
    'transfer-out',
    DateTime(2026, 8, 20),
    2000000,
    TransactionType.expense,
    account: accountA.name,
    category: 'Transfer',
  );
  final incoming = _transaction(
    'transfer-in',
    DateTime(2026, 8, 20),
    2000000,
    TransactionType.income,
    account: accountB.name,
    category: 'Transfer',
  );
  final defaultTransactions = <Transaction>[
    _transaction(
      'salary',
      DateTime(2026, 8, 2),
      8000000,
      TransactionType.income,
      account: accountA.name,
      category: 'Salary',
    ),
    if (groceryAmount > 0)
      _transaction(
        'groceries',
        DateTime(2026, 8, 5),
        groceryAmount,
        TransactionType.expense,
        account: accountA.name,
        category: 'Groceries',
      ),
    if (utilityAmount > 0)
      _transaction(
        'utilities',
        DateTime(2026, 8, 8),
        utilityAmount,
        TransactionType.expense,
        account: accountA.name,
        category: 'Utilities',
      ),
    outgoing,
    incoming,
    ...extraTransactions,
  ];
  final accounts = <Account>[accountA, accountB];
  final transactions = replaceTransactions ?? defaultTransactions;
  final links = replaceTransactions == null
      ? [
          InternalTransferLink(
            id: 'link',
            bookId: book.id,
            outgoingTransactionId: outgoing.id,
            incomingTransactionId: incoming.id,
            sourceAccountId: accountA.id,
            destinationAccountId: accountB.id,
            currencyCode: 'IDR',
            amount: 2000000,
          ),
        ]
      : <InternalTransferLink>[];
  if (includeUsd) {
    final usd = Account(
      id: 'account-usd',
      bookId: book.id,
      name: 'USD Wallet',
      currencyCode: 'USD',
      openingBalance: 1000,
      openingBalanceDate: DateTime(2026, 1),
    );
    accounts.add(usd);
    transactions.add(
      _transaction(
        'usd-income',
        DateTime(2026, 8, 3),
        2000,
        TransactionType.income,
        account: usd.name,
        category: 'Consulting',
      ),
    );
  }
  return _Fixture(
    month: selectedMonth,
    book: book,
    accounts: accounts,
    transactions: transactions,
    links: links,
    budgets: groceryBudget == null
        ? const []
        : [
            MonthlyCategoryBudget(
              id: 'budget',
              bookId: book.id,
              categoryId: 'groceries-category',
              monthStart: DateTime(2026, 8),
              limitMinor: groceryBudget,
              currencyCode: 'IDR',
            ),
          ],
  );
}

Transaction _transaction(
  String id,
  DateTime date,
  int amount,
  TransactionType type, {
  String account = 'Enos Bank',
  String category = 'General',
  DateTime? deletedAt,
}) => Transaction(
  id: id,
  bookId: 'book',
  title: id,
  category: category,
  account: account,
  date: date,
  amount: amount,
  type: type,
  createdAt: date.add(const Duration(minutes: 1)),
  updatedAt: date.add(const Duration(minutes: 1)),
  deletedAt: deletedAt,
);
