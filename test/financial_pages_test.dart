import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:pilgrim_tracker/features/reports/presentation/screens/reports_page.dart';
import 'package:pilgrim_tracker/features/tithe/presentation/screens/tithe_page.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

FinancialSummary _summary() {
  return FinancialSummary.calculate(
    referenceDate: DateTime(2026, 7, 20),
    titheRate: 0.13,
    transactions: [
      Transaction(
        title: 'Salary',
        category: 'Salary',
        account: 'Cash Enos',
        date: DateTime(2026, 7, 1),
        amount: 10000000,
        type: TransactionType.income,
      ),
      Transaction(
        title: 'Rent',
        category: 'Housing',
        account: 'Cash Enos',
        date: DateTime(2026, 7, 2),
        amount: 3000000,
        type: TransactionType.expense,
      ),
      Transaction(
        title: 'Lunch',
        category: 'Food',
        account: 'Cash Enos',
        date: DateTime(2026, 7, 3),
        amount: 1000000,
        type: TransactionType.expense,
      ),
    ],
  );
}

void main() {
  testWidgets('Dashboard displays calculated financial metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Dashboard(
            transactions: const [],
            summary: _summary(),
            referenceDate: DateTime(2026, 7, 20),
            onOpen: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Recorded balance'), findsOneWidget);
    expect(find.text('Rp 10.000.000'), findsWidgets);
    expect(find.text('Rp 4.000.000'), findsWidgets);
    expect(find.text('Housing'), findsWidgets);
    expect(find.text('Calculated tithe'), findsOneWidget);
  });

  testWidgets('Reports displays calculated report values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportsPage(summary: _summary())),
      ),
    );

    expect(find.text('+Rp 6.000.000'), findsOneWidget);
    expect(find.text('60.0%'), findsOneWidget);
    expect(find.text('Housing'), findsOneWidget);
  });

  testWidgets('Tithe displays calculated monthly tithe', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TithePage(summary: _summary())),
      ),
    );

    expect(find.text('Rp 1.300.000'), findsOneWidget);
    expect(find.text('Rp 10.000.000'), findsOneWidget);
    expect(find.text('13.0%'), findsWidgets);
  });
}
