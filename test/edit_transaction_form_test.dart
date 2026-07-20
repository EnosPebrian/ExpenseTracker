import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/edit/transaction_form.dart';

void main() {
  testWidgets('Edit Transaction changes project through searchable selection', (
    tester,
  ) async {
    Transaction? submitted;
    final transaction = Transaction(
      projectId: 'life',
      title: 'Groceries',
      category: 'Konsumsi',
      account: 'Cash Enos',
      date: DateTime(2026, 7, 19, 9, 30),
      amount: 125000,
      type: TransactionType.expense,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: const TransactionFormOptions(
              accounts: ['Cash Enos', 'BNI Enos'],
              expenseCategories: ['Konsumsi', 'Transportasi'],
              incomeCategories: ['Gaji Enos'],
              projects: ['Life', 'Tebu Nai'],
            ),
            onSubmit: (value) async => submitted = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Life'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'tebu');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Tebu Nai'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.id, transaction.id);
    expect(submitted!.projectId, 'tebu-nai');
  });
  testWidgets('Edit Transaction remains open and displays persistence error', (
    tester,
  ) async {
    final transaction = Transaction(
      projectId: 'life',
      title: 'Groceries',
      category: 'Konsumsi',
      account: 'Cash Enos',
      date: DateTime(2026, 7, 19, 9, 30),
      amount: 125000,
      type: TransactionType.expense,
    );

    var submitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: const TransactionFormOptions(
              accounts: ['Cash Enos', 'BNI Enos'],
              expenseCategories: ['Konsumsi', 'Transportasi'],
              incomeCategories: ['Gaji Enos'],
              projects: ['Life', 'Tebu Nai'],
            ),
            onSubmit: (value) async {
              submitCount++;

              throw StateError('database unavailable');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(submitCount, 1);

    expect(find.text('Edit transaction'), findsOneWidget);

    expect(find.textContaining('database unavailable'), findsOneWidget);

    expect(find.text('Save changes'), findsOneWidget);
  });
}
