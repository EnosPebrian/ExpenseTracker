import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/reports/presentation/controllers/financial_statement_controller.dart';
import 'package:pilgrim_tracker/features/reports/presentation/screens/reports_page.dart';
import 'package:pilgrim_tracker/features/reports/presentation/screens/statements_screen.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  testWidgets('Reports exposes Statements navigation', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            summary: FinancialSummary.calculate(
              transactions: const [],
              referenceDate: DateTime(2026, 8),
            ),
            onOpenStatements: () => opened = true,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('reports-statements')));
    await tester.tap(find.byKey(const Key('reports-statements')));
    expect(opened, isTrue);
  });

  for (final size in const [Size(390, 844), Size(1200, 900)]) {
    testWidgets('Statements generate monthly household preview at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = Account(
        id: 'account',
        bookId: 'book',
        name: 'Cash',
        openingBalance: 1000,
        openingBalanceDate: DateTime(2026, 1),
      );
      final controller = FinancialStatementController(
        book: FinancialBook(id: 'book', name: 'Household'),
        accounts: [account],
        transactions: [
          Transaction(
            id: 'income',
            bookId: 'book',
            title: 'Salary',
            category: 'Salary',
            account: 'Cash',
            date: DateTime(2026, 8, 1),
            amount: 5000,
            type: TransactionType.income,
          ),
        ],
        transferLinks: const [],
        budgets: const [],
        categoryNamesById: const {},
        initialPeriod: DateTime(2026, 8),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: StatementsScreen(controller: controller)),
      );
      expect(find.byKey(const Key('statement-type-selector')), findsOneWidget);
      expect(find.byKey(const Key('statement-scope-selector')), findsOneWidget);
      expect(find.byKey(const Key('statement-month-selector')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('statement-generate')));
      await tester.tap(find.byKey(const Key('statement-generate')));
      await tester.pump();
      expect(find.byKey(const Key('statement-preview')), findsOneWidget);
      expect(find.text('IDR 6.000'), findsWidgets);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('statement-export-pdf')), findsOneWidget);
    });
  }

  testWidgets('Annual account selection generates running-balance preview', (
    tester,
  ) async {
    final account = Account(
      id: 'account',
      bookId: 'book',
      name: 'Cash',
      openingBalance: 1000,
      openingBalanceDate: DateTime(2026, 1),
    );
    final controller = FinancialStatementController(
      book: FinancialBook(id: 'book', name: 'Household'),
      accounts: [account],
      transactions: const [],
      transferLinks: const [],
      budgets: const [],
      categoryNamesById: const {},
      initialPeriod: DateTime(2026, 8),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: StatementsScreen(controller: controller)),
    );
    await tester.tap(find.text('Annual'));
    await tester.pump();
    await tester.tap(find.text('Account'));
    await tester.pump();
    expect(find.byKey(const Key('statement-account-selector')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('statement-generate')));
    await tester.tap(find.byKey(const Key('statement-generate')));
    await tester.pump();
    expect(find.text('No transactions during this period.'), findsWidgets);
    expect(
      find.text(
        'Historical year-end asset valuation is unavailable; no net-worth estimate is shown.',
      ),
      findsOneWidget,
    );
  });
}
