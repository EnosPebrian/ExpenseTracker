import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:pilgrim_tracker/features/tithe/domain/tithe_summary.dart';
import 'package:pilgrim_tracker/features/tithe/presentation/screens/tithe_page.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/edit/transaction_form.dart';

const bookId = 'a2000000-0000-0000-0000-000000000001';

TitheSummary snapshot({
  int due = 0,
  int paid = 0,
  List<Transaction> recent = const [],
}) => TitheSummary(
  bookId: bookId,
  currencyCode: 'IDR',
  asOf: DateTime(2026, 9, 8),
  currentMonth: TithePeriodSummary(
    due: due,
    paid: paid,
    paymentCount: recent.length,
  ),
  yearToDate: TithePeriodSummary(
    due: due,
    paid: paid,
    paymentCount: recent.length,
  ),
  cumulative: TithePeriodSummary(
    due: due,
    paid: paid,
    paymentCount: recent.length,
  ),
  recentPayments: recent,
);

Widget page(
  TitheSummary summary, {
  VoidCallback? onRecord,
  ValueChanged<Transaction>? onOpen,
}) => MaterialApp(
  home: Scaffold(
    body: TithePage(
      summary: summary,
      onRecordPayment: onRecord ?? () {},
      onOpenPayment: onOpen,
    ),
  ),
);

void main() {
  testWidgets('empty state explains how tithe begins', (tester) async {
    await tester.pumpWidget(page(snapshot()));
    expect(find.byKey(const Key('tithe-empty-payments')), findsOneWidget);
    expect(find.textContaining('No tithe obligation'), findsOneWidget);
  });

  testWidgets('outstanding state is prominent', (tester) async {
    await tester.pumpWidget(page(snapshot(due: 1300, paid: 700)));
    expect(find.text('Outstanding'), findsOneWidget);
    expect(find.text('Rp 600'), findsWidgets);
  });

  testWidgets('advance state is explicit and not clamped', (tester) async {
    await tester.pumpWidget(page(snapshot(due: 1000, paid: 1200)));
    expect(find.text('Advance / Credit'), findsOneWidget);
    expect(find.byKey(const Key('tithe-advance')), findsOneWidget);
    expect(find.text('Rp 200'), findsOneWidget);
  });

  testWidgets('record payment action is wired', (tester) async {
    var tapped = false;
    await tester.pumpWidget(page(snapshot(), onRecord: () => tapped = true));
    final action = find.byKey(const Key('record-tithe-payment'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(tapped, isTrue);
  });

  testWidgets('recent payment opens ordinary transaction detail callback', (
    tester,
  ) async {
    final transaction = Transaction(
      id: 'payment',
      bookId: bookId,
      title: 'Tithe payment',
      category: 'Tithe',
      categoryId: SystemCategoryIds.tithe(bookId),
      account: 'BCA',
      date: DateTime(2026, 9, 4),
      amount: 500000,
      type: TransactionType.expense,
    );
    Transaction? opened;
    await tester.pumpWidget(
      page(
        snapshot(paid: 500000, recent: [transaction]),
        onOpen: (value) => opened = value,
      ),
    );
    final payment = find.byKey(const Key('tithe-payment-payment'));
    await tester.ensureVisible(payment);
    await tester.tap(payment);
    expect(opened?.id, 'payment');
  });

  testWidgets('narrow Android-style layout renders without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page(snapshot(due: 1300, paid: 700)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Windows-style layout remains width constrained', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page(snapshot(due: 1300, paid: 700)));
    expect(find.byType(ConstrainedBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dedicated payment form locks type and category', (tester) async {
    final transaction = Transaction(
      bookId: bookId,
      title: 'Tithe payment',
      category: 'Tithe',
      categoryId: SystemCategoryIds.tithe(bookId),
      account: 'Cash',
      date: DateTime(2026, 9, 8),
      amount: 100,
      type: TransactionType.expense,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: const TransactionFormOptions(
              accounts: ['Cash'],
              expenseCategories: ['Tithe'],
              incomeCategories: ['Salary'],
              projects: [],
            ),
            lockType: true,
            lockedCategoryId: SystemCategoryIds.tithe(bookId),
            onSubmit: (_) async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('locked-tithe-category')), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<TransactionType>>(
            find.byType(SegmentedButton<TransactionType>),
          )
          .onSelectionChanged,
      isNull,
    );
  });
}
