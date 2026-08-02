import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/app/data/default_asset_definitions.dart';
import 'package:pilgrim_tracker/app/services/app_bootstrap_service.dart';
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_period.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/assets/data/repositories/local_asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/demo_financial_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh production bootstrap contains no user financial data', () async {
    final fixture = await _Fixture.create('fresh');
    addTearDown(fixture.dispose);
    final controller = TransactionProviders.controller(fixture.store);
    addTearDown(controller.dispose);
    final bootstrap = AppBootstrapService(
      store: fixture.store,
      transactionController: controller,
    );

    await bootstrap.load();
    await LocalAssetDefinitionRepository(
      fixture.store,
    ).ensureSeeds(buildDefaultAssetDefinitions(timestamp: DateTime.utc(2026)));

    for (final table in const [
      'transactions',
      'accounts',
      'projects',
      'books',
      'household_members',
      'sync_outbox',
      'sync_conflicts',
      'initial_sync_staging',
    ]) {
      expect(await _count(fixture.store, table), 0, reason: table);
    }
    expect(await fixture.store.getMasterNames('accounts'), isEmpty);
    expect(await fixture.store.getMasterNames('projects'), isEmpty);
    expect(await fixture.store.getAssetDefinitions(), hasLength(5));
    expect(controller.transactions, isEmpty);

    final summary = FinancialSummary.calculate(
      transactions: controller.transactions,
      referenceDate: DateTime(2026, 7, 20),
    );
    expect(summary.monthlyIncome, 0);
    expect(summary.monthlyExpenses, 0);
    expect(summary.monthlyNetCashFlow, 0);
  });

  test('reopen does not create demo data or modify real user data', () async {
    final fixture = await _Fixture.create('reopen');
    addTearDown(fixture.dispose);
    await fixture.store.initialize();
    final repository = LocalTransactionRepository(fixture.store);
    final real = Transaction(
      id: 'real-user-transaction',
      title: 'Actual user expense',
      category: 'User category',
      account: 'User account',
      date: DateTime(2026, 7, 28),
      amount: 12345,
      type: TransactionType.expense,
    );
    await fixture.store.upsertAccount({
      'id': 'real-user-account',
      'name': 'User account',
      'account_type': 'asset',
      'currency_code': 'IDR',
      'opening_balance': 50000,
      'created_at': 1,
      'updated_at': 1,
      'version': 1,
      'device_id': 'user-device',
      'sync_status': 'local_only',
    });
    await repository.save(real);
    await fixture.reopen();

    final controller = TransactionProviders.controller(fixture.store);
    addTearDown(controller.dispose);
    await AppBootstrapService(
      store: fixture.store,
      transactionController: controller,
    ).load();

    expect(controller.transactions, hasLength(1));
    expect(controller.transactions.single.id, real.id);
    expect(await fixture.store.getAccounts(), hasLength(1));
    expect(
      (await fixture.store.getAccounts()).single['opening_balance'],
      50000,
    );
  });

  test(
    'asset presets move from pre-onboarding scope to the household and reopen',
    () async {
      final fixture = await _Fixture.create('preset-adoption');
      addTearDown(fixture.dispose);
      await fixture.store.initialize();
      final seeds = buildDefaultAssetDefinitions(
        timestamp: DateTime.utc(2026, 7, 28, 9),
      );
      final repository = LocalAssetDefinitionRepository(fixture.store);
      await repository.ensureSeeds(seeds);
      expect(await fixture.store.getAssetDefinitions(), hasLength(5));

      const bookId = 'fresh-household';
      await fixture.store.upsertFinancialBook(
        FinancialBook(id: bookId, name: 'My Household').toRecord(),
        enqueueSync: false,
      );
      fixture.store.setActiveBookId(bookId);
      final controller = AssetDefinitionController(repository: repository);
      await controller.initialize(
        seeds: buildDefaultAssetDefinitions(
          timestamp: DateTime.utc(2026, 7, 28, 10),
        ),
        preserveExistingDefinitionsOnSeedConflict: true,
      );

      expect(controller.error, isNull);
      expect(controller.definitions, hasLength(5));
      expect(
        controller.definitions.map((definition) => definition.id).toSet(),
        seeds.map((definition) => definition.id).toSet(),
      );
      expect(await _count(fixture.store, 'asset_definitions'), 5);

      await fixture.reopen();
      fixture.store.setActiveBookId(bookId);
      final reopenedRepository = LocalAssetDefinitionRepository(fixture.store);
      final reopenedController = AssetDefinitionController(
        repository: reopenedRepository,
      );
      await reopenedController.initialize(
        seeds: buildDefaultAssetDefinitions(
          timestamp: DateTime.utc(2026, 7, 28, 11),
        ),
        preserveExistingDefinitionsOnSeedConflict: true,
      );

      expect(reopenedController.error, isNull);
      expect(reopenedController.definitions, hasLength(5));
      expect(await _count(fixture.store, 'asset_definitions'), 5);
    },
  );

  test('legacy random preset copies do not block database reopen', () async {
    final fixture = await _Fixture.create('legacy-preset-copy');
    addTearDown(fixture.dispose);
    await fixture.store.initialize();
    final seeds = buildDefaultAssetDefinitions(
      timestamp: DateTime.utc(2026, 7, 28, 9),
    );
    await LocalAssetDefinitionRepository(fixture.store).ensureSeeds(seeds);

    const bookId = 'legacy-household';
    await fixture.store.upsertFinancialBook(
      FinancialBook(id: bookId, name: 'My Household').toRecord(),
      enqueueSync: false,
    );
    fixture.store.setActiveBookId(bookId);
    for (final seed in seeds) {
      await fixture.store.upsertAssetDefinition(
        seed
            .copyWith(
              id: 'legacy-copy-${seed.id}',
              bookId: bookId,
              createdAt: DateTime.utc(2026, 7, 28, 10),
              updatedAt: DateTime.utc(2026, 7, 28, 10),
            )
            .toRecord(),
        enqueueSync: false,
      );
    }
    await fixture.reopen();
    fixture.store.setActiveBookId(bookId);
    final controller = AssetDefinitionController(
      repository: LocalAssetDefinitionRepository(fixture.store),
    );

    await controller.initialize(
      seeds: buildDefaultAssetDefinitions(
        timestamp: DateTime.utc(2026, 7, 28, 11),
      ),
      preserveExistingDefinitionsOnSeedConflict: true,
    );

    expect(controller.error, isNull);
    expect(controller.definitions, hasLength(5));
    expect(
      controller.definitions.every(
        (definition) => definition.id.startsWith('legacy-copy-'),
      ),
      isTrue,
    );
  });

  test('demo fixture requires an explicit test-only call', () async {
    final fixture = await _Fixture.create('fixture');
    addTearDown(fixture.dispose);
    await fixture.store.initialize();
    final repository = LocalTransactionRepository(fixture.store);
    expect(await repository.getAll(), isEmpty);
    await installDemoFinancialFixture(repository);
    expect(await repository.getAll(), hasLength(2));
  });

  testWidgets('fresh dashboard renders zero values and setup actions', (
    tester,
  ) async {
    var accountActions = 0;
    final summary = FinancialSummary.calculate(
      transactions: const [],
      referenceDate: DateTime(2026, 7, 28),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Dashboard(
            transactions: const [],
            hasAccounts: false,
            summary: summary,
            referenceDate: DateTime(2026, 7, 28),
            period: FinancialPeriod.thisMonth(DateTime(2026, 7, 28)),
            onPeriodChanged: (_) {},
            onOpen: (_) {},
            onAddAccount: () => accountActions++,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('fresh-workspace-empty-state')),
      findsOneWidget,
    );
    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Add transaction'), findsOneWidget);
    expect(find.text('Rp 0'), findsWidgets);
    expect(find.text('Client retainer - July'), findsNothing);
    await tester.tap(find.byKey(const Key('empty-add-account')));
    expect(accountActions, 1);
  });
}

Future<int> _count(dynamic store, String table) async {
  final rows = await store.db.rawQuery('SELECT COUNT(*) AS total FROM $table');
  return (rows.single['total'] as num).toInt();
}

class _Fixture {
  _Fixture(this.directory, this.path, this.store);
  final Directory directory;
  final String path;
  LocalStore store;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('pilgrim-$name-');
    final path = p.join(directory.path, 'pilgrim_tracker.db');
    return _Fixture(directory, path, LocalStore(databasePath: path));
  }

  Future<void> reopen() async {
    await store.close();
    store = LocalStore(databasePath: path);
    await store.initialize();
  }

  Future<void> dispose() async {
    await store.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
