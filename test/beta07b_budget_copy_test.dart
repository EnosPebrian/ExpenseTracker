import 'dart:async';
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
import 'package:pilgrim_tracker/features/budgets/domain/services/monthly_budget_copy_service.dart';
import 'package:pilgrim_tracker/features/budgets/presentation/controllers/monthly_budget_controller.dart';
import 'package:pilgrim_tracker/features/budgets/presentation/screens/budgets_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('monthly budget copy planning', () {
    const service = MonthlyBudgetCopyService();

    test('normalizes month keys and rejects the same source and target', () {
      expect(service.normalizeMonth(DateTime(2026, 8, 31)), DateTime(2026, 8));
      expect(
        () => service.preview(
          bookId: 'book-1',
          sourceMonth: DateTime(2026, 8, 31),
          targetMonth: DateTime(2026, 8, 1),
          sourceBudgets: const [],
          targetBudgets: const [],
          categoriesById: const {},
        ),
        throwsStateError,
      );
    });

    test(
      'adds active missing targets and preserves plan fields with a new ID',
      () {
        final source = _budget(
          id: 'source-food',
          categoryId: 'food',
          month: DateTime(2026, 8),
          limit: 3000000,
          note: 'Household groceries',
        );
        final existingSource = _budget(
          id: 'source-fuel',
          categoryId: 'fuel',
          month: DateTime(2026, 8),
          limit: 1000000,
        );
        final target = _budget(
          id: 'target-fuel',
          categoryId: 'fuel',
          month: DateTime(2026, 9),
          limit: 750000,
          note: 'Keep this target value',
        );
        final preview = service.preview(
          bookId: 'book-1',
          sourceMonth: DateTime(2026, 8, 20),
          targetMonth: DateTime(2026, 9, 18),
          sourceBudgets: [source, existingSource],
          targetBudgets: [target],
          categoriesById: const {
            'food': BudgetCopyCategory(
              id: 'food',
              bookId: 'book-1',
              name: 'Groceries',
              active: true,
            ),
            'fuel': BudgetCopyCategory(
              id: 'fuel',
              bookId: 'book-1',
              name: 'Transport',
              active: true,
            ),
          },
        );
        expect(preview.sourceBudgetCount, 2);
        expect(preview.budgetsToAdd, 1);
        expect(preview.alreadyPresent, 1);
        expect(preview.expectedTargetTotalMinor, 3750000);

        final copied = service.createCandidates(preview).single;
        expect(copied.id, isNot(source.id));
        expect(copied.bookId, 'book-1');
        expect(copied.categoryId, source.categoryId);
        expect(copied.monthStart, DateTime(2026, 9));
        expect(copied.limitMinor, source.limitMinor);
        expect(copied.currencyCode, source.currencyCode);
        expect(copied.note, source.note);
        expect(copied.version, 1);
        expect(copied.syncStatus, 'pending');
        expect(target.limitMinor, 750000);
        expect(target.note, 'Keep this target value');
      },
    );

    test(
      'skips archived and missing categories and ignores deleted budgets',
      () {
        final preview = service.preview(
          bookId: 'book-1',
          sourceMonth: DateTime(2026, 8),
          targetMonth: DateTime(2026, 9),
          sourceBudgets: [
            _budget(
              id: 'archived',
              categoryId: 'old',
              month: DateTime(2026, 8),
            ),
            _budget(
              id: 'missing',
              categoryId: 'gone',
              month: DateTime(2026, 8),
            ),
            _budget(
              id: 'deleted-source',
              categoryId: 'old',
              month: DateTime(2026, 8),
              deletedAt: DateTime(2026, 8, 2),
            ),
          ],
          targetBudgets: const [],
          categoriesById: const {
            'old': BudgetCopyCategory(
              id: 'old',
              bookId: 'book-1',
              name: 'Archived expense',
              active: false,
            ),
          },
        );
        expect(preview.budgetsToAdd, 0);
        expect(preview.sourceBudgetCount, 2);
        expect(preview.unavailableCategories, 2);
        expect(preview.warnings, hasLength(2));
        expect(service.createCandidates(preview), isEmpty);
      },
    );

    test('rejects cross-household budgets and categories', () {
      expect(
        () => service.preview(
          bookId: 'book-1',
          sourceMonth: DateTime(2026, 8),
          targetMonth: DateTime(2026, 9),
          sourceBudgets: [
            _budget(
              id: 'foreign-budget',
              bookId: 'book-2',
              categoryId: 'food',
              month: DateTime(2026, 8),
            ),
          ],
          targetBudgets: const [],
          categoriesById: const {},
        ),
        throwsStateError,
      );
      expect(
        () => service.preview(
          bookId: 'book-1',
          sourceMonth: DateTime(2026, 8),
          targetMonth: DateTime(2026, 9),
          sourceBudgets: [
            _budget(id: 'source', categoryId: 'food', month: DateTime(2026, 8)),
          ],
          targetBudgets: const [],
          categoriesById: const {
            'food': BudgetCopyCategory(
              id: 'food',
              bookId: 'book-2',
              name: 'Foreign',
              active: true,
            ),
          },
        ),
        throwsStateError,
      );
    });
  });

  test(
    'native copy commits budgets and outbox atomically and is idempotent',
    () async {
      final fixture = await _Fixture.create('native-copy');
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(() async {
        await store.close();
        await fixture.dispose();
      });
      final categories = await _prepareStore(store, bookId: 'copy-book');
      final repository = LocalMonthlyBudgetRepository(store);
      for (final entry in categories.entries.where(
        (entry) => entry.key != 'Archived',
      )) {
        await repository.save(
          _budget(
            id: 'source-${entry.key}',
            bookId: 'copy-book',
            categoryId: entry.value,
            month: DateTime(2026, 8),
            limit: entry.key == 'Food' ? 3000000 : 1000000,
          ),
        );
      }
      final beforeOutbox = await _budgetOutboxCount(store, 'copy-book');
      final preview = await repository.previewCopy(
        bookId: 'copy-book',
        sourceMonth: DateTime(2026, 8),
        targetMonth: DateTime(2026, 9),
      );
      final result = await repository.copy(preview);
      expect(result.copied, 2);
      expect(result.finalTargetCount, 2);
      expect(await _budgetOutboxCount(store, 'copy-book'), beforeOutbox + 2);

      final repeatedPreview = await repository.previewCopy(
        bookId: 'copy-book',
        sourceMonth: DateTime(2026, 8),
        targetMonth: DateTime(2026, 9),
      );
      final repeated = await repository.copy(repeatedPreview);
      expect(repeated.copied, 0);
      expect(repeated.alreadyPresent, 2);
      expect(await _budgetOutboxCount(store, 'copy-book'), beforeOutbox + 2);

      await store.close();
      final reopened = native.LocalStore(databasePath: fixture.path);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(
        await reopened.getMonthlyCategoryBudgets(
          bookId: 'copy-book',
          monthStart: '2026-09-01',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'native batch failure rolls back all budgets and outbox entries',
    () async {
      final fixture = await _Fixture.create('native-rollback');
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(() async {
        await store.close();
        await fixture.dispose();
      });
      final categories = await _prepareStore(store, bookId: 'rollback-book');
      final beforeOutbox = await _budgetOutboxCount(store, 'rollback-book');
      await expectLater(
        store.copyMonthlyCategoryBudgets([
          _record(
            id: 'valid-copy',
            bookId: 'rollback-book',
            categoryId: categories['Food']!,
            month: DateTime(2026, 9),
          ),
          _record(
            id: 'invalid-copy',
            bookId: 'rollback-book',
            categoryId: 'missing-category',
            month: DateTime(2026, 9),
          ),
        ]),
        throwsStateError,
      );
      expect(
        await store.getMonthlyCategoryBudgets(
          bookId: 'rollback-book',
          monthStart: '2026-09-01',
        ),
        isEmpty,
      );
      expect(await _budgetOutboxCount(store, 'rollback-book'), beforeOutbox);
    },
  );

  test(
    'native local-only copy persists without creating outbox work',
    () async {
      final fixture = await _Fixture.create('native-local-only');
      final store = LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(() async {
        await store.close();
        await fixture.dispose();
      });
      final categories = await _prepareStore(
        store,
        bookId: 'local-only-book',
        remoteLinked: false,
      );
      final repository = LocalMonthlyBudgetRepository(store);
      await repository.save(
        _budget(
          id: 'local-only-source',
          bookId: 'local-only-book',
          categoryId: categories['Food']!,
          month: DateTime(2026, 8),
        ),
      );
      final beforeOutbox = await _budgetOutboxCount(store, 'local-only-book');
      final preview = await repository.previewCopy(
        bookId: 'local-only-book',
        sourceMonth: DateTime(2026, 8),
        targetMonth: DateTime(2026, 9),
      );
      final result = await repository.copy(preview);
      expect(result.copied, 1);
      expect(
        await repository.getForMonth(
          bookId: 'local-only-book',
          month: DateTime(2026, 9),
        ),
        hasLength(1),
      );
      expect(await _budgetOutboxCount(store, 'local-only-book'), beforeOutbox);
    },
  );

  test('web local-only copy has atomic add-missing parity', () async {
    final store = web.LocalStore(databasePath: 'beta07b-web');
    await store.initialize();
    final categories = await _prepareStore(
      store,
      bookId: 'beta07b-web-book',
      remoteLinked: false,
    );
    const service = MonthlyBudgetCopyService();
    final source = _budget(
      id: 'web-source',
      bookId: 'beta07b-web-book',
      categoryId: categories['Food']!,
      month: DateTime(2026, 8),
    );
    await store.upsertMonthlyCategoryBudget(source.toRecord());
    final categoryRows = await store.getBudgetCopyCategoryRecords([
      categories['Food']!,
    ]);
    final preview = service.preview(
      bookId: 'beta07b-web-book',
      sourceMonth: DateTime(2026, 8),
      targetMonth: DateTime(2026, 9),
      sourceBudgets: [source],
      targetBudgets: const [],
      categoriesById: {
        for (final row in categoryRows)
          row['id'] as String: BudgetCopyCategory(
            id: row['id'] as String,
            bookId: row['book_id'] as String,
            name: row['name'] as String,
            active: row['deleted_at'] == null,
          ),
      },
    );
    final first = await store.copyMonthlyCategoryBudgets(
      service.createCandidates(preview).map((item) => item.toRecord()).toList(),
    );
    expect(first, hasLength(1));
    final second = await store.copyMonthlyCategoryBudgets(
      service.createCandidates(preview).map((item) => item.toRecord()).toList(),
    );
    expect(second, isEmpty);
  });

  testWidgets(
    'copy dialog previews statuses and cancellation changes nothing',
    (tester) async {
      late _WidgetSetup setup;
      await tester.runAsync(() async {
        setup = await _widgetSetup('preview');
      });
      addTearDown(setup.dispose);
      await _pumpBudgetPage(tester, setup.controller);

      await tester.tap(find.text('Copy budgets'));
      await _waitForAsyncUi(tester, find.text('Will be added'));
      expect(find.text('Source: August 2026'), findsOneWidget);
      expect(find.text('Target: September 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous source month'));
      await _waitForAsyncUi(
        tester,
        find.text('The source month has no active budgets to copy.'),
      );
      expect(find.text('Source: July 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next source month'));
      await _waitForAsyncUi(tester, find.text('Will be added'));
      expect(find.text('Source: August 2026'), findsOneWidget);
      expect(find.text('Will be added'), findsOneWidget);
      expect(find.text('Already present'), findsWidgets);
      expect(find.text('Category unavailable'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final targetBudgets = await tester.runAsync(
        () => setup.repository.getForMonth(
          bookId: setup.bookId,
          month: DateTime(2026, 9),
        ),
      );
      expect(targetBudgets, hasLength(1));
    },
  );

  testWidgets(
    'copy shows busy/success, refreshes target, and reports zero copy',
    (tester) async {
      late _WidgetSetup setup;
      await tester.runAsync(() async {
        setup = await _widgetSetup('complete', delayed: true);
      });
      addTearDown(setup.dispose);
      await _pumpBudgetPage(tester, setup.controller);
      await tester.tap(find.text('Copy budgets'));
      await _waitForAsyncUi(tester, find.text('Will be added'));
      await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
      await tester.pump();
      expect(find.text('Copying...'), findsOneWidget);
      setup.delayedRepository!.release();
      await _waitForAsyncUi(tester, find.text('1 budgets copied.'));
      expect(find.text('1 budgets copied.'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Latest copy: 1 categories added'), findsOneWidget);
      expect(find.text('2 budgeted categories'), findsOneWidget);

      await tester.tap(find.text('Copy budgets'));
      await _waitForAsyncUi(tester, find.text('Already present'));
      await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
      await _waitForAsyncUi(tester, find.text('No budgets were copied.'));
      expect(find.text('No budgets were copied.'), findsOneWidget);
    },
  );
}

MonthlyCategoryBudget _budget({
  required String id,
  String bookId = 'book-1',
  required String categoryId,
  required DateTime month,
  int limit = 100000,
  String? note,
  DateTime? deletedAt,
}) => MonthlyCategoryBudget(
  id: id,
  bookId: bookId,
  categoryId: categoryId,
  monthStart: month,
  limitMinor: limit,
  currencyCode: 'IDR',
  note: note,
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
  deviceId: 'test-device',
  syncStatus: 'pending',
  deletedAt: deletedAt,
);

Map<String, Object?> _record({
  required String id,
  required String bookId,
  required String categoryId,
  required DateTime month,
  int limit = 100000,
}) => _budget(
  id: id,
  bookId: bookId,
  categoryId: categoryId,
  month: month,
  limit: limit,
).toRecord();

Future<Map<String, String>> _prepareStore(
  dynamic store, {
  required String bookId,
  bool remoteLinked = true,
}) async {
  const created = 1785542400000;
  await store.upsertFinancialBook({
    'id': bookId,
    'name': 'BETA-07B household',
    'base_currency_code': 'IDR',
    'created_at': created,
    'updated_at': created,
    'deleted_at': null,
    'version': 1,
    'device_id': 'device-1',
    'sync_status': 'synced',
    'remote_linked_at': remoteLinked ? created : null,
  });
  store.setActiveBookId(bookId);
  for (final name in const ['Food', 'Fuel', 'Archived']) {
    await store.saveMasterName('categories', name, categoryType: 'expense');
  }
  final rows = await store.getCategoryRecords(
    includeDeleted: true,
    categoryType: 'expense',
    bookId: bookId,
  );
  return {for (final row in rows) row['name'] as String: row['id'] as String};
}

Future<int> _budgetOutboxCount(dynamic store, String bookId) async =>
    (await store.getEligibleSyncOperations(
      bookId,
    )).where((row) => row['entity_type'] == 'monthly_category_budgets').length;

class _WidgetSetup {
  const _WidgetSetup({
    required this.fixture,
    required this.store,
    required this.repository,
    required this.controller,
    required this.bookId,
    this.delayedRepository,
  });

  final _Fixture fixture;
  final LocalStore store;
  final LocalMonthlyBudgetRepository repository;
  final MonthlyBudgetController controller;
  final String bookId;
  final _DelayedBudgetRepository? delayedRepository;

  Future<void> dispose() async {
    controller.dispose();
    await store.close();
    await fixture.dispose();
  }
}

Future<_WidgetSetup> _widgetSetup(String name, {bool delayed = false}) async {
  final fixture = await _Fixture.create('widget-$name');
  final store = LocalStore(databasePath: fixture.path);
  await store.initialize();
  final bookId = 'widget-$name-book';
  final categories = await _prepareStore(store, bookId: bookId);
  final baseRepository = delayed
      ? _DelayedBudgetRepository(store)
      : LocalMonthlyBudgetRepository(store);
  await baseRepository.save(
    _budget(
      id: '$name-food-source',
      bookId: bookId,
      categoryId: categories['Food']!,
      month: DateTime(2026, 8),
      limit: 3000000,
    ),
  );
  await baseRepository.save(
    _budget(
      id: '$name-fuel-source',
      bookId: bookId,
      categoryId: categories['Fuel']!,
      month: DateTime(2026, 8),
      limit: 1000000,
    ),
  );
  await baseRepository.save(
    _budget(
      id: '$name-archived-source',
      bookId: bookId,
      categoryId: categories['Archived']!,
      month: DateTime(2026, 8),
      limit: 500000,
    ),
  );
  final archivedCategory = (await store.getCategoryRecords(
    includeDeleted: true,
    categoryType: 'expense',
    bookId: bookId,
  )).singleWhere((row) => row['id'] == categories['Archived']);
  final archivedAt = DateTime(2026, 8, 2).millisecondsSinceEpoch;
  await store.applyRemoteSyncBatch(
    bookId,
    changes: [
      {
        'entity_type': 'categories',
        'entity_id': categories['Archived'],
        'payload': {
          ...archivedCategory,
          'deleted_at': archivedAt,
          'updated_at': archivedAt,
          'version': (archivedCategory['version'] as num).toInt() + 1,
        },
      },
    ],
    finalSequence: 1,
  );
  await baseRepository.save(
    _budget(
      id: '$name-fuel-target',
      bookId: bookId,
      categoryId: categories['Fuel']!,
      month: DateTime(2026, 9),
      limit: 750000,
    ),
  );
  final controller = MonthlyBudgetController(repository: baseRepository);
  await controller.load(
    bookId: bookId,
    categoryNames: {
      for (final entry in categories.entries) entry.value: entry.key,
    },
    activeCategoryIds: {categories['Food']!, categories['Fuel']!},
    currencyCode: 'IDR',
    transactions: const [],
  );
  controller.setMonth(DateTime(2026, 9));
  return _WidgetSetup(
    fixture: fixture,
    store: store,
    repository: baseRepository,
    controller: controller,
    bookId: bookId,
    delayedRepository: baseRepository is _DelayedBudgetRepository
        ? baseRepository
        : null,
  );
}

class _DelayedBudgetRepository extends LocalMonthlyBudgetRepository {
  _DelayedBudgetRepository(super.store);

  Completer<void>? _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<MonthlyBudgetCopyResult> copy(MonthlyBudgetCopyPreview preview) async {
    final gate = _gate;
    if (gate != null) await gate.future;
    return super.copy(preview);
  }
}

Future<void> _pumpBudgetPage(
  WidgetTester tester,
  MonthlyBudgetController controller,
) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, _) =>
                BudgetsPage(controller: controller, currencyCode: 'IDR'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _waitForAsyncUi(WidgetTester tester, Finder expected) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (expected.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for expected asynchronous UI state.');
}

class _Fixture {
  const _Fixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta07b-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
