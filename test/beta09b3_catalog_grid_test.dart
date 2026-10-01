import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_grid_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_grid_batch.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/grid/grid_bulk_dialog.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/grid/grid_batch_review.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/grid/transaction_grid.dart';
import 'beta09b1_transaction_grid_test.dart' as f;

void main() {
  testWidgets('catalog picker locks while save is pending', (t) async {
    await t.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final completion = Completer<void>();
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionGrid(
            rows: [f.row()],
            policy: f.policy(),
            onSave: (_) {
              calls++;
              return completion.future;
            },
          ),
        ),
      ),
    );
    await t.tap(find.text('Food').last);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(calls, 1);
    expect(
      t.widget<TextField>(find.byKey(const Key('grid-catalog-input'))).enabled,
      isFalse,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byKey(const Key('grid-catalog-input')), findsOneWidget);
    completion.complete();
    await t.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets(
    'historical same-name category is not preselected as a replacement',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1800, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var writes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionGrid(
              rows: [f.row().copyWith(categoryId: 'historical-id')],
              policy: f.policy(),
              onSave: (_) async {
                writes++;
              },
            ),
          ),
        ),
      );
      await t.tap(find.text('Food').last);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(writes, 0);
      expect(
        find.textContaining('Select an existing category'),
        findsOneWidget,
      );
    },
  );
  testWidgets('bulk income picker excludes expenses', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: GridBulkDialog(
          rows: [f.row().copyWith(type: TransactionType.income)],
          policy: f.policy(),
        ),
      ),
    );
    await t.tap(find.byTooltip('Show choices'));
    await t.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
  });
  for (final field in [
    TransactionGridField.account,
    TransactionGridField.project,
  ]) {
    testWidgets('bulk ${field.label} lists compatible catalog', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: GridBulkDialog(rows: [f.row()], policy: f.policy()),
        ),
      );
      await t.tap(find.text('Category'));
      await t.pumpAndSettle();
      await t.tap(find.text(field.label).last);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Show choices'));
      await t.pumpAndSettle();
      if (field == TransactionGridField.account) {
        expect(find.text('Bank'), findsOneWidget);
        expect(find.text('USD'), findsNothing);
      } else {
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('(No project)'), findsOneWidget);
      }
    });
  }
  testWidgets('plural toolbar and coordinated editor stay safe', (t) async {
    await t.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var opened = 0;
    var writes = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionGrid(
            rows: [
              f.row(),
              f.row(1).copyWith(type: TransactionType.transfer),
            ],
            policy: f.policy(),
            onOpen: (_) => opened++,
            onSave: (_) async {
              writes++;
            },
          ),
        ),
      ),
    );
    await t.tap(find.text('Expense 0'));
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(find.text('Expense 1'));
    await t.pumpAndSettle();
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('Bulk edit 2 rows'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(opened, 1);
    expect(writes, 0);
    expect(find.byKey(const Key('grid-catalog-input')), findsNothing);
  });
  test('unknown choice cannot create master data', () {
    final p = f.policy();
    expect(
      () => p.prepareChoice(
        f.row(),
        TransactionGridField.category,
        const GridCatalogChoice('new', 'Unknown', 'Unknown'),
      ),
      throwsException,
    );
    expect(p.expenseCategories, {'Food': 'food'});
    expect(p.projects, {'Home': 'home'});
    expect(p.accounts.length, 3);
  });
  for (final type in [TransactionType.expense, TransactionType.income]) {
    test('$type categories come only from their catalog', () {
      expect(
        f
            .policy()
            .choices([
              f.row().copyWith(type: type),
            ], TransactionGridField.category)
            .map((c) => c.value),
        [type == TransactionType.expense ? 'Food' : 'Salary'],
      );
    });
  }
  test('mixed categories block with explanation', () {
    final rows = [f.row(), f.row(1).copyWith(type: TransactionType.income)];
    expect(f.policy().choices(rows, TransactionGridField.category), isEmpty);
    expect(
      f.policy().catalogProblem(rows, TransactionGridField.category),
      contains('both Income and Expense'),
    );
  });
  test('Tithe is excluded', () {
    const book = '00000000-0000-4000-8000-000000000001';
    final p = TransactionGridPolicy(
      accounts: [],
      projects: {},
      incomeCategories: {},
      expenseCategories: {
        'Food': 'food',
        'Tithe': SystemCategoryIds.tithe(book),
      },
    );
    expect(
      p
          .choices([
            f.row().copyWith(bookId: book),
          ], TransactionGridField.category)
          .map((c) => c.value),
      ['Food'],
    );
  });
  test('account choices exclude foreign, deleted, currency and brokerage', () {
    final p = TransactionGridPolicy(
      accounts: [
        ...f.policy().accounts,
        Account(id: 'other', bookId: 'other', name: 'Other'),
        Account(
          id: 'gone',
          bookId: 'b',
          name: 'Gone',
          deletedAt: DateTime(2026),
        ),
        Account(
          id: 'broker',
          bookId: 'b',
          name: 'Broker',
          accountType: AccountType.brokerage,
        ),
      ],
      expenseCategories: {},
      incomeCategories: {},
      projects: {},
    );
    expect(
      p.choices([f.row()], TransactionGridField.account).map((c) => c.value),
      ['Bank', 'Cash'],
    );
    expect(
      p.choices([
        f.row().copyWith(account: 'Broker'),
      ], TransactionGridField.account),
      isEmpty,
    );
    expect(
      p.catalogProblem([
        f.row(),
        f.row(1).copyWith(account: 'USD'),
      ], TransactionGridField.account),
      'No account is compatible with all selected rows.',
    );
  });
  test('project catalog offers explicit safe clearing', () {
    final row = f.row().copyWith(projectId: 'home');
    final choices = f.policy().choices([row], TransactionGridField.project);
    expect(choices.map((c) => c.label), ['(No project)', 'Home']);
    expect(
      f
          .policy()
          .prepareChoice(row, TransactionGridField.project, choices.first)
          .projectId,
      isNull,
    );
    expect(f.policy().projects, {'Home': 'home'});
  });
  test('same-name replacement account cannot rebind reviewed choice', () async {
    final choice = f.policy().choices([
      f.row(),
    ], TransactionGridField.account).first;
    final plan = TransactionGridBatch.plan(
      rows: [f.row()],
      fields: [TransactionGridField.account],
      values: [
        ['Bank'],
      ],
      policy: f.policy(),
      choices: {TransactionGridField.account: choice},
    );
    var writes = 0;
    final p = TransactionGridPolicy(
      accounts: [
        for (final a in f.policy().accounts)
          a.name == 'Bank' ? a.copyWith(id: 'replacement') : a,
      ],
      expenseCategories: {},
      incomeCategories: {},
      projects: {},
    );
    final result = await GridBatchCommit.apply(
      plan,
      current: (_) => plan.edits.single.before,
      currentPolicy: () => p,
      save: (_) async {
        writes++;
      },
    );
    expect(writes, 0);
    expect(result.single.message, contains('Catalog changed'));
  });
  testWidgets('bulk category is searchable and requires selection', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: GridBulkDialog(rows: [f.row(), f.row(1)], policy: f.policy()),
      ),
    );
    expect(find.text('2 rows selected'), findsOneWidget);
    final review = find.widgetWithText(FilledButton, 'Review');
    expect(t.widget<FilledButton>(review).onPressed, isNull);
    await t.enterText(find.byKey(const Key('grid-catalog-input')), 'foo');
    await t.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    await t.tap(find.text('Food'));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(review).onPressed, isNotNull);
  });
  testWidgets('mixed bulk Category displays blocking explanation', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: GridBulkDialog(
          rows: [
            f.row(),
            f.row(1).copyWith(type: TransactionType.income),
          ],
          policy: f.policy(),
        ),
      ),
    );
    expect(find.textContaining('both Income and Expense'), findsOneWidget);
    expect(find.byKey(const Key('grid-catalog-input')), findsNothing);
  });
  for (final field in [
    TransactionGridField.reference,
    TransactionGridField.note,
  ]) {
    testWidgets('${field.label} remains text with explicit clear', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: GridBulkDialog(rows: [f.row()], policy: f.policy()),
        ),
      );
      await t.tap(find.text('Category'));
      await t.pumpAndSettle();
      await t.tap(find.text(field.label).last);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('grid-catalog-input')), findsNothing);
      await t.enterText(find.byType(TextField), 'Some text');
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Review'))
            .onPressed,
        isNotNull,
      );
      await t.tap(find.text('Clear value'));
      await t.pump();
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  }
  testWidgets('review shows human old/new values and row names', (t) async {
    final plan = TransactionGridBatch.plan(
      rows: [f.row().copyWith(projectId: 'home')],
      fields: [TransactionGridField.project],
      values: [
        [''],
      ],
      policy: f.policy(),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                GridBatchReview.confirm(context, plan, policy: f.policy()),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    for (final label in [
      '1 rows will change',
      'Description',
      'Field',
      'Old',
      'New',
      'Expense 0',
      'Project',
      'Home',
      '(No project)',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
  for (final field in [
    TransactionGridField.category,
    TransactionGridField.account,
    TransactionGridField.project,
  ]) {
    testWidgets(
      'inline ${field.label} uses picker and Tab saves; Escape cancels',
      (t) async {
        await t.binding.setSurfaceSize(const Size(1800, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final saved = <Transaction>[];
        final row = f.row().copyWith(projectId: 'home');
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TransactionGrid(
                rows: [row],
                policy: f.policy(),
                onSave: (r) async {
                  saved.add(r);
                },
              ),
            ),
          ),
        );
        expect(find.text('Edit 1 row'), findsNothing);
        final cell = field == TransactionGridField.category
            ? 'Food'
            : field == TransactionGridField.account
            ? 'Cash'
            : 'Home';
        await t.tap(find.text(cell).last);
        await t.pumpAndSettle();
        expect(find.text('Edit 1 row'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('grid-catalog-input')), findsOneWidget);
        await t.enterText(
          find.byKey(const Key('grid-catalog-input')),
          field == TransactionGridField.project
              ? '(No'
              : field == TransactionGridField.account
              ? 'Ban'
              : 'Foo',
        );
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        expect(saved, hasLength(1));
        if (field == TransactionGridField.project) {
          expect(saved.single.projectId, isNull);
        }
        await t.tap(find.text(cell).last);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(saved, hasLength(1));
      },
    );
  }
}
