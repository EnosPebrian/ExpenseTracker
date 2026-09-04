import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/budgets/data/local_monthly_budget_repository.dart';
import 'package:pilgrim_tracker/features/budgets/domain/entities/monthly_category_budget.dart';
import 'package:pilgrim_tracker/features/budgets/domain/services/monthly_budget_calculator.dart';
import 'package:pilgrim_tracker/features/budgets/presentation/controllers/monthly_budget_controller.dart';
import 'package:pilgrim_tracker/features/budgets/presentation/screens/budgets_page.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('monthly budget calculation', () {
    final month = DateTime(2026, 8);
    final budget = MonthlyCategoryBudget(
      id: 'budget-food',
      bookId: 'book-1',
      categoryId: 'category-food',
      monthStart: month,
      limitMinor: 10000,
      currencyCode: 'IDR',
    );

    test('uses exact 80 and 100 percent threshold boundaries', () {
      expect(_result(budget, 7999).threshold, BudgetThreshold.onTrack);
      expect(_result(budget, 8000).threshold, BudgetThreshold.nearLimit);
      expect(_result(budget, 9999).threshold, BudgetThreshold.nearLimit);
      expect(_result(budget, 10000).threshold, BudgetThreshold.overspent);
      expect(_result(budget, 12000).remainingMinor, 0);
      expect(_result(budget, 12000).overspentMinor, 2000);
    });

    test('entity normalizes month and round-trips exact value semantics', () {
      final normalized = MonthlyCategoryBudget(
        id: 'budget-map',
        bookId: 'book-1',
        categoryId: 'category-food',
        monthStart: DateTime(2026, 8, 29, 23, 59),
        limitMinor: 123456,
        currencyCode: 'IDR',
        note: 'Exact plan',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

      expect(normalized.monthKey, '2026-08-01');
      expect(
        MonthlyCategoryBudget.fromRecord(normalized.toRecord()),
        normalized,
      );
      expect(normalized.copyWith(limitMinor: 200000).limitMinor, 200000);
      expect(
        () => MonthlyCategoryBudget(
          bookId: 'book-1',
          categoryId: 'category-food',
          monthStart: month,
          limitMinor: 0,
          currencyCode: 'IDR',
        ),
        throwsArgumentError,
      );
    });

    test('counts only active local-month expenses for the household', () {
      final transactions = [
        _expense(
          'first owner',
          2500,
          DateTime(2026, 8, 1),
          enteredByMemberId: 'member-enos',
        ),
        _expense(
          'second owner',
          1500,
          DateTime(2026, 8, 31, 23, 59),
          enteredByMemberId: 'member-grace',
        ),
        _expense(
          'linked fee expense',
          500,
          DateTime(2026, 8, 3),
          relationType: TransactionRelationType.assetFeeExpense,
        ),
        _expense('previous month', 9000, DateTime(2026, 7, 31, 23, 59)),
        _expense('next month', 9000, DateTime(2026, 9, 1)),
        _expense(
          'deleted',
          9000,
          DateTime(2026, 8, 2),
          deletedAt: DateTime(2026, 8, 3),
        ),
        Transaction(
          title: 'income',
          category: 'Food',
          account: 'Cash',
          date: DateTime(2026, 8, 2),
          amount: 9000,
          type: TransactionType.income,
        ),
        Transaction(
          title: 'transfer',
          category: 'Food',
          account: 'Cash to Bank',
          date: DateTime(2026, 8, 2),
          amount: 9000,
          type: TransactionType.transfer,
        ),
        Transaction(
          title: 'asset conversion',
          category: 'Food',
          account: 'Cash to Gold',
          date: DateTime(2026, 8, 2),
          amount: 9000,
          type: TransactionType.assetConversion,
        ),
      ];

      final summary = MonthlyBudgetCalculator.calculate(
        month: month,
        budgets: [budget],
        transactions: transactions,
        categoryNamesById: const {'category-food': 'Food'},
      );

      expect(summary.categories.single.spentMinor, 4500);
      expect(summary.totalSpendMinor, 4500);
      expect(summary.remainingMinor, 5500);
      expect(summary.overspentMinor, 0);
    });

    test('empty month is zero safe', () {
      final summary = MonthlyBudgetCalculator.calculate(
        month: month,
        budgets: const [],
        transactions: const [],
        categoryNamesById: const {},
      );
      expect(summary.totalLimitMinor, 0);
      expect(summary.totalSpendMinor, 0);
      expect(summary.remainingMinor, 0);
      expect(summary.overspentMinor, 0);
      expect(summary.unbudgetedSpendMinor, 0);
    });

    test('reports unbudgeted spend and preserves category snapshots', () {
      final summary = MonthlyBudgetCalculator.calculate(
        month: month,
        budgets: [budget],
        transactions: [
          _expense(
            'old snapshot',
            3000,
            DateTime(2026, 8, 4),
            category: 'Food',
          ),
          _expense('unbudgeted', 1200, DateTime(2026, 8, 5), category: 'Fuel'),
        ],
        categoryNamesById: const {'category-food': 'Groceries'},
      );

      expect(summary.categories.single.spentMinor, 0);
      expect(summary.unbudgetedSpendMinor, 4200);
    });
  });

  test(
    'SQLite 21 persists one active budget and reuses a tombstoned ID',
    () async {
      final fixture = await _Fixture.create('native');
      addTearDown(fixture.dispose);
      final store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      expect(native.LocalStore.schemaVersion, 25);

      final categoryId = await _prepareStore(store);
      final first = _budgetRecord('budget-first', categoryId);
      await store.upsertMonthlyCategoryBudget(first);

      await expectLater(
        store.upsertMonthlyCategoryBudget(
          _budgetRecord('budget-duplicate', categoryId),
        ),
        throwsStateError,
      );
      expect(
        (await store.getEligibleSyncOperations(
          'book-1',
        )).where((row) => row['entity_type'] == 'monthly_category_budgets'),
        hasLength(1),
      );
      await store.softDeleteMonthlyCategoryBudget(
        first['id']! as String,
        DateTime(2026, 8, 3).millisecondsSinceEpoch,
      );
      final restored = await store.upsertMonthlyCategoryBudget(
        _budgetRecord('budget-new-id', categoryId, limitMinor: 250000),
      );

      expect(restored['id'], 'budget-first');
      final rows = await store.getMonthlyCategoryBudgets(includeDeleted: true);
      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], isNull);
      expect(rows.single['limit_minor'], 250000);
      expect(rows.single['version'], 3);
      await expectLater(
        store.upsertMonthlyCategoryBudget({
          ...restored,
          'month_start': '2026-09-01',
        }),
        throwsStateError,
      );
      var budgetOperations = (await store.getEligibleSyncOperations(
        'book-1',
      )).where((row) => row['entity_type'] == 'monthly_category_budgets');
      expect(budgetOperations, hasLength(3));

      await store.db.update(
        'categories',
        {'deleted_at': 1785801600000},
        where: 'id = ?',
        whereArgs: [categoryId],
      );
      final editedHistorical = await store.upsertMonthlyCategoryBudget({
        ...restored,
        'limit_minor': 260000,
        'version': 4,
      });
      expect(editedHistorical['limit_minor'], 260000);
      budgetOperations = (await store.getEligibleSyncOperations(
        'book-1',
      )).where((row) => row['entity_type'] == 'monthly_category_budgets');
      expect(budgetOperations, hasLength(4));
    },
  );

  test(
    'remote budget apply is scoped and creates no local outbox echo',
    () async {
      final fixture = await _Fixture.create('remote-budget');
      addTearDown(fixture.dispose);
      final store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      final categoryId = await _prepareStore(store);
      await store.setSyncInitializationState('book-1', 'ready');
      final outboxBefore = await store.getEligibleSyncOperations('book-1');

      await store.applyRemoteSyncBatch(
        'book-1',
        changes: [
          {
            'entity_type': 'monthly_category_budgets',
            'entity_id': 'remote-budget',
            'payload': _budgetRecord('remote-budget', categoryId),
          },
        ],
        finalSequence: 9,
      );

      expect(
        await store.getMonthlyCategoryBudgets(bookId: 'book-1'),
        hasLength(1),
      );
      expect(await store.getMonthlyCategoryBudgets(bookId: 'foreign'), isEmpty);
      expect(
        await store.getEligibleSyncOperations('book-1'),
        hasLength(outboxBefore.length),
      );
    },
  );

  test('budget survives close and reopen within its household scope', () async {
    final fixture = await _Fixture.create('reopen-budget');
    addTearDown(fixture.dispose);
    var store = native.LocalStore(databasePath: fixture.path);
    await store.initialize();
    final categoryId = await _prepareStore(store);
    await store.upsertMonthlyCategoryBudget(
      _budgetRecord('reopen-budget', categoryId),
    );
    await store.close();

    store = native.LocalStore(databasePath: fixture.path);
    await store.initialize();
    addTearDown(store.close);
    expect(
      await store.getMonthlyCategoryBudgets(bookId: 'book-1'),
      hasLength(1),
    );
    expect(
      await store.getMonthlyCategoryBudgets(bookId: 'other-book'),
      isEmpty,
    );
  });

  test(
    'SQLite 20 upgrades additively to current without financial data loss',
    () async {
      final fixture = await _Fixture.create('migration');
      addTearDown(fixture.dispose);
      var store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      await store.db.execute('DROP TABLE monthly_category_budgets');
      await store.db.execute('PRAGMA user_version = 20');
      await store.close();

      store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);

      final version = await store.db.rawQuery('PRAGMA user_version');
      final tables = await store.db.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'monthly_category_budgets'],
      );
      expect(version.single['user_version'], 25);
      expect(tables, hasLength(1));
    },
  );

  test(
    'web persistence enforces category, uniqueness, and note limits',
    () async {
      final store = web.LocalStore(databasePath: 'beta07a-web');
      await store.initialize();
      final categoryId = await _prepareStore(store);
      await store.upsertMonthlyCategoryBudget(
        _budgetRecord('budget-web', categoryId),
      );

      await expectLater(
        store.upsertMonthlyCategoryBudget(
          _budgetRecord('duplicate-web', categoryId),
        ),
        throwsStateError,
      );
      await expectLater(
        store.upsertMonthlyCategoryBudget({
          ..._budgetRecord('long-note', categoryId),
          'note': List.filled(121, 'x').join(),
        }),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'budget page creates a formatted zero-spend budget',
    (tester) async {
      late _Fixture fixture;
      late LocalStore store;
      late String categoryId;
      late MonthlyBudgetController controller;
      await tester.runAsync(() async {
        fixture = await _Fixture.create('widget');
        store = LocalStore(databasePath: fixture.path);
        await store.initialize();
        categoryId = await _prepareStore(store);
        final repository = LocalMonthlyBudgetRepository(store);
        await repository.save(
          MonthlyCategoryBudget(
            id: 'widget-budget',
            bookId: 'book-1',
            categoryId: categoryId,
            monthStart: DateTime(2026, 9),
            limitMinor: 200000,
            currencyCode: 'IDR',
          ),
        );
        controller = MonthlyBudgetController(repository: repository);
        await controller.load(
          bookId: 'book-1',
          categoryNames: {categoryId: 'Food'},
          activeCategoryIds: {categoryId},
          currencyCode: 'IDR',
          transactions: const [],
        );
      });
      controller.setMonth(DateTime(2026, 9));
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BudgetsPage(controller: controller, currencyCode: 'IDR'),
            ),
          ),
        ),
      );
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('No spending'), findsOneWidget);
      expect(find.textContaining('IDR 200.000'), findsWidgets);

      final menu = find.byType(PopupMenuButton<String>);
      await tester.ensureVisible(menu);
      await tester.pump();
      await tester.tap(menu);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, '300000');
      expect(find.text('300.000'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.runAsync(() async {
        await store.close();
        await fixture.dispose();
      });
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

CategoryBudgetResult _result(MonthlyCategoryBudget budget, int spent) =>
    CategoryBudgetResult(
      budget: budget,
      categoryName: 'Food',
      spentMinor: spent,
    );

Transaction _expense(
  String title,
  int amount,
  DateTime date, {
  String category = 'Food',
  DateTime? deletedAt,
  String? enteredByMemberId,
  TransactionRelationType relationType = TransactionRelationType.none,
}) => Transaction(
  enteredByMemberId: enteredByMemberId,
  title: title,
  category: category,
  account: 'Cash',
  date: date,
  amount: amount,
  type: TransactionType.expense,
  relationType: relationType,
  deletedAt: deletedAt,
);

Future<String> _prepareStore(dynamic store) async {
  const created = 1785542400000;
  await store.upsertFinancialBook({
    'id': 'book-1',
    'name': 'Budget household',
    'base_currency_code': 'IDR',
    'created_at': created,
    'updated_at': created,
    'deleted_at': null,
    'version': 1,
    'device_id': 'device-1',
    'sync_status': 'synced',
    'remote_linked_at': created,
  });
  store.setActiveBookId('book-1');
  await store.saveMasterName('categories', 'Food', categoryType: 'expense');
  final categories = await store.getCategoryRecords(categoryType: 'expense');
  return categories.single['id'] as String;
}

Map<String, Object?> _budgetRecord(
  String id,
  String categoryId, {
  int limitMinor = 200000,
}) => {
  'id': id,
  'book_id': 'book-1',
  'category_id': categoryId,
  'month_start': '2026-08-01',
  'limit_minor': limitMinor,
  'currency_code': 'IDR',
  'note': null,
  'created_at': 1785542400000,
  'updated_at': 1785542400000,
  'deleted_at': null,
  'version': 1,
  'device_id': 'device-1',
  'sync_status': 'pending',
};

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta07a-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
