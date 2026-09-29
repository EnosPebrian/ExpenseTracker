import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_grid_policy.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/grid/transaction_grid.dart';

Transaction row([int i = 0]) => Transaction(
  id: 'r$i',
  bookId: 'b',
  title: 'Expense $i',
  category: 'Food',
  categoryId: 'food',
  account: 'Cash',
  date: DateTime(2026, 9, 1),
  amount: 100,
  type: TransactionType.expense,
);
TransactionGridPolicy policy() => TransactionGridPolicy(
  accounts: [
    Account(id: 'a', bookId: 'b', name: 'Cash', accountType: AccountType.cash),
    Account(id: 'b', bookId: 'b', name: 'Bank', accountType: AccountType.bank),
    Account(id: 'usd', bookId: 'b', name: 'USD', currencyCode: 'USD'),
  ],
  expenseCategories: const {'Food': 'food'},
  incomeCategories: const {'Salary': 'salary'},
  projects: const {'Home': 'home'},
);

void main() {
  test('System Tithe identity cannot be edited or assigned inline', () {
    const book = '00000000-0000-4000-8000-000000000001';
    final tithe = SystemCategoryIds.tithe(book);
    expect(
      policy().canEdit(row().copyWith(bookId: book, categoryId: tithe)),
      isFalse,
    );
    final p = TransactionGridPolicy(
      accounts: const [],
      expenseCategories: {'Tithe': tithe},
      incomeCategories: const {},
      projects: const {},
    );
    expect(
      () => p.prepare(
        row().copyWith(bookId: book),
        TransactionGridField.category,
        'Tithe',
      ),
      throwsException,
    );
  });
  testWidgets(
    'pending save prevents double submission and retains server error',
    (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionGrid(
              rows: [row()],
              policy: policy(),
              onSave: (_) {
                calls++;
                return completion.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Expense 0'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('grid-editor')),
        'Pending edit',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 1);
      completion.completeError(StateError('Save rejected'));
      await tester.pump();
      expect(find.textContaining('Save rejected'), findsOneWidget);
      expect(find.byKey(const Key('grid-editor')), findsOneWidget);
    },
  );
  test(
    'ordinary edit preserves identity and validates date, amount and metadata',
    () {
      final p = policy();
      final r = row();
      expect(
        p.prepare(r, TransactionGridField.description, 'Changed').id,
        r.id,
      );
      expect(
        p.prepare(r, TransactionGridField.date, '2026-09-15').date,
        DateTime(2026, 9, 15),
      );
      expect(
        () => p.prepare(r, TransactionGridField.date, '2026-02-30'),
        throwsException,
      );
      expect(
        () => p.prepare(r, TransactionGridField.amount, '-1'),
        throwsException,
      );
      expect(
        () => p.prepare(r, TransactionGridField.amount, '1.2'),
        throwsException,
      );
      expect(
        () => p.prepare(r, TransactionGridField.description, ''),
        throwsException,
      );
      expect(p.prepare(r, TransactionGridField.note, ' note ').note, 'note');
      expect(
        p.prepare(r, TransactionGridField.reference, '').reference,
        isNull,
      );
    },
  );
  test('catalog identities, no implicit creation or currency conversion', () {
    final p = policy();
    final r = row();
    expect(
      p.prepare(r, TransactionGridField.category, 'food').categoryId,
      'food',
    );
    expect(
      p.prepare(r, TransactionGridField.project, 'Home').projectId,
      'home',
    );
    expect(p.prepare(r, TransactionGridField.project, '').projectId, isNull);
    expect(p.prepare(r, TransactionGridField.account, 'bank').account, 'Bank');
    expect(
      () => p.prepare(r, TransactionGridField.category, 'Unknown'),
      throwsException,
    );
    expect(
      () => p.prepare(r, TransactionGridField.account, 'USD'),
      throwsException,
    );
  });
  test('coordinated financial rows never inline edit', () {
    for (final r in [
      row().copyWith(type: TransactionType.transfer),
      row().copyWith(type: TransactionType.assetConversion),
      row().copyWith(type: TransactionType.investment),
      row().copyWith(relatedTransactionId: 'parent'),
      row().copyWith(feeAmount: 10),
      row().copyWith(assetDefinitionId: 'asset'),
      row().copyWith(brokerageAccountId: 'broker'),
    ]) {
      expect(policy().canEdit(r), isFalse);
      expect(
        () => policy().prepare(r, TransactionGridField.note, 'edit'),
        throwsException,
      );
    }
  });
  for (final count in [1000, 5000]) {
    testWidgets('$count rows virtualize and keep header visible', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionGrid(
              rows: List.generate(count, row),
              policy: policy(),
              onSave: (_) async {},
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith('grid-row-'),
            )
            .evaluate()
            .length,
        lessThan(40),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(find.text('Description'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'keyboard edit commits once; invalid draft remains; Escape cancels',
    (tester) async {
      Transaction? saved;
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionGrid(
              rows: [row()],
              policy: policy(),
              onSave: (v) async {
                saved = v;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Expense 0'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('grid-editor')), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved, isNull);
      expect(find.byKey(const Key('grid-error')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('grid-editor')), 'Edited');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved?.title, 'Edited');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('grid-editor')), findsNothing);
    },
  );
}
