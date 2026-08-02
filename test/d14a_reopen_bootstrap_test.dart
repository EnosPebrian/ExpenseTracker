import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/master_data/default_asset_definition_ids.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/app/data/default_asset_definitions.dart';
import 'package:pilgrim_tracker/app/services/app_bootstrap_service.dart';
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart'
    as web_store;
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_conversion_controller.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/assets/data/repositories/local_asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_retirement_policy.dart';
import 'package:pilgrim_tracker/features/assets/presentation/models/asset_definition_catalog_query.dart';
import 'package:pilgrim_tracker/features/assets/presentation/services/asset_definition_catalog_filter.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('integrated financial state survives native close and reopen', () async {
    final fixture = await _StoreFixture.create('d14a-reopen');
    addTearDown(fixture.dispose);
    final definitions = <String, AssetDefinition>{
      _bbca.id: _bbca,
      _inventory.id: _inventory,
    };
    final definitionRepository = LocalAssetDefinitionRepository(fixture.store);
    for (final definition in definitions.values) {
      await definitionRepository.upsert(definition);
    }

    final repository = LocalTransactionRepository(fixture.store);
    final create = CreateTransaction(
      repository,
      assetDefinitionResolver: (id) => definitions[id],
    );
    final delete = DeleteTransaction(repository);

    final expense = await create(
      _expense(id: 'expense-active', amount: 250000, title: 'Groceries'),
    );
    final deletedExpense = await create(
      _expense(id: 'expense-deleted', amount: 90000, title: 'Old expense'),
    );
    await delete(deletedExpense);

    final buy = await create(
      _trade(
        id: 'bbca-buy',
        definition: _bbca,
        action: AssetAction.buy,
        quantity: 1000,
        amount: 10000000,
        feeAmount: 100000,
        feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      ),
    );
    final sale = await create(
      _trade(
        id: 'bbca-sale',
        definition: _bbca,
        action: AssetAction.sell,
        quantity: 400,
        amount: 4400000,
        feeAmount: 40000,
        feeTreatment: AssetFeeTreatment.recordAsSeparateExpense,
        referencePrice: 10800,
      ),
    );
    await create(
      _trade(
        id: 'inventory-buy',
        definition: _inventory,
        action: AssetAction.buy,
        quantity: 10,
        amount: 1000000,
      ),
    );
    await create(
      _trade(
        id: 'inventory-sale',
        definition: _inventory,
        action: AssetAction.sell,
        quantity: 10,
        amount: 1200000,
      ),
    );
    await definitionRepository.softDelete(
      _inventory.id,
      deletedAt: DateTime.utc(2026, 7, 25),
    );

    final price = AssetMarketPrice.manual(
      assetKey: _bbca.marketPriceKey,
      symbol: _bbca.symbol,
      price: 12000,
      unit: _bbca.unit,
      quotedAt: DateTime.utc(2026, 7, 25, 8),
    );
    await fixture.store.upsertAssetMarketPrice(price.toRecord());

    final feeBeforeClose = await repository.getAssetFeeExpense(sale.id);
    expect(feeBeforeClose, isNotNull);
    final feeId = feeBeforeClose!.id;
    await fixture.reopen();

    final reopenedTransactions = LocalTransactionRepository(fixture.store);
    final active = await reopenedTransactions.getAll();
    final all = await reopenedTransactions.getAll(includeDeleted: true);
    final reopenedDefinitions = LocalAssetDefinitionRepository(fixture.store);
    final definitionValues = await reopenedDefinitions.getAll(
      includeDeleted: true,
    );
    final prices = (await fixture.store.getAssetMarketPrices())
        .map(AssetMarketPrice.fromRecord)
        .toList();

    expect(active.any((item) => item.id == expense.id), isTrue);
    final restoredBuy = active.singleWhere((item) => item.id == buy.id);
    final restoredSale = active.singleWhere((item) => item.id == sale.id);
    expect(restoredBuy.assetDefinitionId, _bbca.id);
    expect(restoredBuy.assetName, _bbca.displayName);
    expect(restoredBuy.assetSymbol, _bbca.symbol);
    expect(restoredBuy.feeAmount, 100000);
    expect(restoredBuy.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(restoredSale.marketReferenceUnitPrice, 10800);
    expect(restoredSale.marketReferenceCurrencyCode, 'IDR');
    expect(restoredSale.marketReferenceUnit, 'share');
    expect(
      restoredSale.marketReferenceSource,
      AssetMarketReferenceSource.manual,
    );
    expect(
      restoredSale.marketReferenceQuotedAt?.millisecondsSinceEpoch,
      DateTime.utc(2026, 7, 24, 11).millisecondsSinceEpoch,
    );

    final restoredFee = await reopenedTransactions.getAssetFeeExpense(sale.id);
    expect(restoredFee!.id, feeId);
    expect(restoredFee.relatedTransactionId, sale.id);
    expect(restoredFee.relationType, TransactionRelationType.assetFeeExpense);
    final restoredDeleted = all.singleWhere(
      (item) => item.id == deletedExpense.id,
    );
    expect(restoredDeleted.deletedAt, isNotNull);
    expect(restoredDeleted.version, 2);

    final archivedInventory = definitionValues.singleWhere(
      (item) => item.id == _inventory.id,
    );
    expect(archivedInventory.isDeleted, isTrue);
    expect(
      await reopenedDefinitions.getAll(),
      isNot(contains(archivedInventory)),
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: active,
      assetDefinitions: definitionValues,
      marketPrices: prices,
    );
    final holding = portfolio.holdings.single;
    expect(holding.assetDefinitionId, _bbca.id);
    expect(holding.quantity, 600);
    expect(holding.costBasis, 6060000);
    expect(holding.averageCost, 10100);
    expect(holding.marketValue, 7200000);
    expect(holding.unrealizedGain, 1140000);
    expect(holding.realizedGain, 360000);
    expect(portfolio.totalRealizedGain, 560000);

    final summary = FinancialSummary.calculate(
      transactions: active,
      referenceDate: DateTime(2026, 7, 24),
    );
    expect(summary.monthlyExpenses, 290000);
    expect(
      summary.spendingByCategory,
      contains(
        predicate<CategorySpending>(
          (entry) => entry.category == 'Asset Fees' && entry.amount == 40000,
        ),
      ),
    );
  });

  test(
    'bootstrap remains idempotent before and after database reopen',
    () async {
      final fixture = await _StoreFixture.create('d14a-bootstrap');
      addTearDown(fixture.dispose);
      final seed = _expense(id: 'seed-expense', amount: 10000, title: 'Seed');

      await fixture.store.ensureAccountSeeds(const ['Cash', 'Bank']);
      await fixture.store.ensureMasterSeeds('categories', const [
        'Food',
        'Asset Fees',
      ], categoryType: 'expense');
      await fixture.store.ensureMasterSeeds('categories', const [
        'Salary',
      ], categoryType: 'income');
      await fixture.store.ensureMasterSeeds('projects', const ['Life']);
      await LocalTransactionRepository(fixture.store).save(seed);

      Future<void> bootstrap() async {
        final transactionController = TransactionProviders.controller(
          fixture.store,
        );
        final service = AppBootstrapService(
          store: fixture.store,
          transactionController: transactionController,
        );
        await service.load();
        final transactionRepository = LocalTransactionRepository(fixture.store);
        final controller = AssetDefinitionController(
          repository: LocalAssetDefinitionRepository(fixture.store),
          transactionsProvider: () =>
              transactionRepository.getAll(includeDeleted: true),
        );
        await controller.initialize(seeds: buildDefaultAssetDefinitions());
        expect(controller.error, isNull);
      }

      await bootstrap();
      final definitionRepository = LocalAssetDefinitionRepository(
        fixture.store,
      );
      final initialDefinitions = await definitionRepository.getAll(
        includeDeleted: true,
      );
      final usd = initialDefinitions.singleWhere(
        (item) => item.id == defaultUsdAssetId,
      );
      await definitionRepository.upsert(
        usd.copyWith(
          displayName: 'Personal USD',
          providerCode: null,
          providerSymbol: null,
          onlinePricingEnabled: false,
          version: usd.version + 1,
          syncStatus: 'pending',
        ),
      );
      await definitionRepository.softDelete(
        defaultInventoryAssetId,
        deletedAt: DateTime.utc(2026, 7, 25),
      );
      await definitionRepository.upsert(_userAsset);

      await bootstrap();
      await fixture.reopen();
      await bootstrap();

      expect(await fixture.store.getMasterNames('accounts'), ['Bank', 'Cash']);
      expect(
        await fixture.store.getMasterNames(
          'categories',
          categoryType: 'expense',
        ),
        ['Asset Fees', 'Food'],
      );
      expect(
        await fixture.store.getMasterNames(
          'categories',
          categoryType: 'income',
        ),
        ['Salary'],
      );
      expect(await fixture.store.getMasterNames('projects'), ['Life']);

      final definitions = await LocalAssetDefinitionRepository(
        fixture.store,
      ).getAll(includeDeleted: true);
      final ids = definitions.map((item) => item.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in const [
        defaultGoldHoldingsAssetId,
        defaultBitcoinWalletAssetId,
        defaultInventoryAssetId,
        defaultUsdAssetId,
        defaultSgdAssetId,
        'asset-user-bond',
      ]) {
        expect(ids.where((value) => value == id), hasLength(1));
      }
      expect(
        ids,
        isNot(
          contains(AssetDefinitionRetirementPolicy.retiredStockPortfolioId),
        ),
      );
      final restoredUsd = definitions.singleWhere(
        (item) => item.id == defaultUsdAssetId,
      );
      expect(restoredUsd.displayName, 'Personal USD');
      expect(restoredUsd.providerCode, isNull);
      expect(restoredUsd.onlinePricingEnabled, isFalse);
      expect(
        definitions
            .singleWhere((item) => item.id == defaultInventoryAssetId)
            .isDeleted,
        isTrue,
      );
      expect(
        definitions.singleWhere((item) => item.id == _userAsset.id).displayName,
        _userAsset.displayName,
      );
      final transactions = await LocalTransactionRepository(
        fixture.store,
      ).getAll(includeDeleted: true);
      expect(transactions.where((item) => item.id == seed.id), hasLength(1));
      expect(transactions.single.version, 1);
    },
  );

  test('native linked-fee changes are atomic and survive reopen', () async {
    final fixture = await _StoreFixture.create('d14a-atomic-fee');
    addTearDown(fixture.dispose);
    final parent = _trade(
      id: 'atomic-parent',
      definition: _gold,
      action: AssetAction.buy,
      quantity: 10,
      amount: 10000000,
      feeAmount: 100000,
      feeTreatment: AssetFeeTreatment.recordAsSeparateExpense,
    );

    await expectLater(
      fixture.store.saveAssetFeeChange(
        parent: parent.toRecord(),
        linkedExpense: const <String, Object?>{'id': 'invalid-child'},
      ),
      throwsA(anything),
    );
    expect(await fixture.store.getTransactions(includeDeleted: true), isEmpty);

    final definitions = {_gold.id: _gold};
    final repository = LocalTransactionRepository(fixture.store);
    final create = CreateTransaction(
      repository,
      assetDefinitionResolver: (id) => definitions[id],
    );
    final update = UpdateTransaction(
      repository,
      assetDefinitionResolver: (id) => definitions[id],
    );
    final duplicate = DuplicateTransaction(
      repository,
      assetDefinitionResolver: (id) => definitions[id],
    );
    final delete = DeleteTransaction(repository);

    final created = await create(parent);
    final firstChild = (await repository.getAssetFeeExpense(created.id))!;
    final edited = await update(created.copyWith(feeAmount: 125000));
    final editedChild = (await repository.getAssetFeeExpense(created.id))!;
    expect(editedChild.id, firstChild.id);
    expect(editedChild.amount, 125000);

    final capitalized = await update(
      edited.copyWith(feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis),
    );
    expect(
      (await repository.getAssetFeeExpense(created.id))!.deletedAt,
      isNotNull,
    );
    final restored = await update(
      capitalized.copyWith(
        feeTreatment: AssetFeeTreatment.recordAsSeparateExpense,
      ),
    );
    expect(
      (await repository.getAssetFeeExpense(created.id))!.id,
      firstChild.id,
    );
    final copy = await duplicate(restored);
    final copyChild = (await repository.getAssetFeeExpense(copy.id))!;
    expect(copy.id, isNot(created.id));
    expect(copyChild.id, isNot(firstChild.id));

    await delete(restored);
    await fixture.reopen();
    final reopened = LocalTransactionRepository(fixture.store);
    expect(
      (await reopened.getAssetFeeExpense(created.id))!.deletedAt,
      isNotNull,
    );
    expect((await reopened.getAssetFeeExpense(copy.id))!.deletedAt, isNull);
    final allChildren = (await reopened.getAll(includeDeleted: true))
        .where(
          (item) =>
              item.relationType == TransactionRelationType.assetFeeExpense,
        )
        .toList();
    expect(allChildren, hasLength(2));
    expect(allChildren.where((item) => item.deletedAt == null), hasLength(1));
  });

  test('asset-definition lifecycle rules remain intact after reopen', () async {
    final fixture = await _StoreFixture.create('d14a-lifecycle');
    addTearDown(fixture.dispose);
    final assetRepository = LocalAssetDefinitionRepository(fixture.store);
    final transactionRepository = LocalTransactionRepository(fixture.store);
    final providerStock = _bbca.copyWith(
      providerCode: 'alpha_vantage',
      providerSymbol: 'BBCA.JK',
      onlinePricingEnabled: true,
    );
    final retired = _definition(
      id: AssetDefinitionRetirementPolicy.retiredStockPortfolioId,
      name: 'Stock Portfolio',
      kind: AssetKind.stock,
      unit: 'share',
      symbol: 'STOCK',
      lotSize: 100,
    );
    for (final definition in [providerStock, _inventory, retired]) {
      await assetRepository.upsert(definition);
    }
    await transactionRepository.save(
      _trade(
        id: 'open-bbca-history',
        definition: providerStock,
        action: AssetAction.buy,
        quantity: 100,
        amount: 1000000,
      ),
    );
    await transactionRepository.save(
      _trade(
        id: 'closed-inventory-buy',
        definition: _inventory,
        action: AssetAction.buy,
        quantity: 10,
        amount: 1000000,
      ),
    );
    await transactionRepository.save(
      _trade(
        id: 'closed-inventory-sale',
        definition: _inventory,
        action: AssetAction.sell,
        quantity: 10,
        amount: 1200000,
      ).copyWith(
        date: DateTime.utc(2026, 7, 24, 12),
        createdAt: DateTime.utc(2026, 7, 24, 12),
        updatedAt: DateTime.utc(2026, 7, 24, 12),
      ),
    );
    await transactionRepository.save(
      _trade(
        id: 'retired-open-history',
        definition: retired,
        action: AssetAction.buy,
        quantity: 100,
        amount: 1000000,
      ),
    );
    await fixture.reopen();

    final reopenedTransactions = LocalTransactionRepository(fixture.store);
    final controller = AssetDefinitionController(
      repository: LocalAssetDefinitionRepository(fixture.store),
      transactionsProvider: () =>
          reopenedTransactions.getAll(includeDeleted: true),
    );
    await controller.initialize();
    expect(controller.error, isNull);

    await expectLater(
      controller.archive(controller.definitionById(providerStock.id)!),
      throwsA(isA<AssetDefinitionLifecycleException>()),
    );
    controller.clearError();

    final closed = controller.definitionById(_inventory.id)!;
    await controller.archive(closed);
    expect(controller.definitionById(closed.id)!.isDeleted, isTrue);
    final restored = await controller.restore(
      controller.definitionById(closed.id)!,
    );
    expect(restored.id, closed.id);

    await expectLater(
      controller.save(restored.copyWith(unit: 'item')),
      throwsA(isA<AssetDefinitionLifecycleException>()),
    );
    controller.clearError();
    final safelyEdited = await controller.save(
      restored.copyWith(displayName: 'Inventory Renamed'),
    );
    expect(safelyEdited.displayName, 'Inventory Renamed');
    expect(
      (await reopenedTransactions.getAll())
          .singleWhere((item) => item.id == 'closed-inventory-buy')
          .assetName,
      'Inventory Test',
    );

    final duplicateStock = _definition(
      id: 'duplicate-bbca',
      name: 'Duplicate BBCA',
      kind: AssetKind.stock,
      unit: 'share',
      symbol: 'bbca',
      lotSize: 100,
    );
    await expectLater(
      controller.save(duplicateStock),
      throwsA(isA<AssetDefinitionIntegrityException>()),
    );
    controller.clearError();
    final providerConflict =
        _definition(
          id: 'provider-conflict',
          name: 'Provider Conflict',
          kind: AssetKind.stock,
          unit: 'share',
          symbol: 'DIFF',
          lotSize: 100,
        ).copyWith(
          providerCode: 'ALPHA_VANTAGE',
          providerSymbol: 'bbca.jk',
          onlinePricingEnabled: true,
        );
    await expectLater(
      controller.save(providerConflict),
      throwsA(isA<AssetDefinitionIntegrityException>()),
    );
    controller.clearError();

    final transactions = await reopenedTransactions.getAll();
    final conversion = AssetConversionController(
      accounts: const ['Cash'],
      assets: controller.definitions,
      existingTransactionsProvider: () => transactions,
    );
    addTearDown(conversion.dispose);
    expect(
      conversion.destinationOptions,
      isNot(contains('Stock Portfolio (STOCK)')),
    );
    conversion.setSellAsset(true);
    expect(conversion.sourceOptions, contains('Stock Portfolio (STOCK)'));

    final closeRetired = CreateTransaction(
      reopenedTransactions,
      assetDefinitionResolver: controller.definitionById,
    );
    await closeRetired(
      _trade(
        id: 'retired-close',
        definition: retired,
        action: AssetAction.sell,
        quantity: 100,
        amount: 1100000,
      ).copyWith(
        date: DateTime.utc(2026, 7, 24, 13),
        createdAt: DateTime.utc(2026, 7, 24, 13),
        updatedAt: DateTime.utc(2026, 7, 24, 13),
      ),
    );
    await controller.reload();
    final archivedRetired = controller.definitionById(retired.id)!;
    expect(archivedRetired.isDeleted, isTrue);
    await expectLater(
      controller.restore(archivedRetired),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            AssetDefinitionRetirementPolicy.restoreBlockedMessage,
          ),
        ),
      ),
    );

    final recordsBefore = controller.allDefinitions
        .map((item) => item.toRecord())
        .toList();
    const filter = AssetDefinitionCatalogFilter();
    final active = filter.apply(
      definitions: controller.allDefinitions,
      query: const AssetDefinitionCatalogQuery(searchText: 'inventory'),
    );
    final archived = filter.apply(
      definitions: controller.allDefinitions,
      query: const AssetDefinitionCatalogQuery(
        lifecycle: AssetDefinitionLifecycle.archived,
      ),
    );
    expect(active.map((item) => item.id), contains(_inventory.id));
    expect(archived.map((item) => item.id), contains(retired.id));
    expect(
      controller.allDefinitions.map((item) => item.toRecord()).toList(),
      recordsBefore,
    );
  });

  test(
    'web store preserves current fields and rolls back linked-fee failure',
    () async {
      final store = _FailingWebStore();
      final unique = DateTime.now().microsecondsSinceEpoch.toString();
      final parent = _trade(
        id: 'web-parent-$unique',
        definition: _gold,
        action: AssetAction.buy,
        quantity: 1,
        amount: 1000000,
        feeAmount: 10000,
        feeTreatment: AssetFeeTreatment.recordAsSeparateExpense,
        referencePrice: 990000,
      );
      final baselineIds = (await store.getTransactions(
        includeDeleted: true,
      )).map((record) => record['id']).toSet();
      store.failId = 'web-child-$unique';
      await expectLater(
        store.saveAssetFeeChange(
          parent: parent.toRecord(),
          linkedExpense: {
            ..._expense(
              id: store.failId!,
              amount: 10000,
              title: 'Web fee',
            ).toRecord(),
            'related_transaction_id': parent.id,
            'relation_type': 'assetFeeExpense',
          },
        ),
        throwsStateError,
      );
      expect(
        (await store.getTransactions(
          includeDeleted: true,
        )).map((record) => record['id']).toSet(),
        baselineIds,
      );

      store.failId = null;
      await store.upsertTransaction(parent.toRecord());
      final restored = (await store.getTransactions(
        includeDeleted: true,
      )).singleWhere((record) => record['id'] == parent.id);
      expect(restored['asset_definition_id'], _gold.id);
      expect(restored['fee_treatment'], 'recordAsSeparateExpense');
      expect(restored['market_reference_unit_price'], 990000);
      expect(restored['market_reference_source'], 'manual');

      final deletedAt = DateTime.utc(2026, 7, 26).millisecondsSinceEpoch;
      await store.softDeleteTransaction(parent.id, deletedAt, version: 2);
      final deleted = (await store.getTransactions(
        includeDeleted: true,
      )).singleWhere((record) => record['id'] == parent.id);
      expect(deleted['deleted_at'], deletedAt);
      expect(deleted['updated_at'], deletedAt);
      expect(deleted['version'], 2);
      expect(deleted['sync_status'], 'pending');

      final definition = _userAsset.copyWith(id: 'web-definition-$unique');
      await store.ensureAssetDefinitionSeeds([
        definition.toRecord(),
        definition.toRecord(),
      ]);
      await store.softDeleteAssetDefinition(definition.id, deletedAt);
      final storedDefinition = await store.getAssetDefinitionById(
        definition.id,
      );
      expect(storedDefinition!['deleted_at'], deletedAt);
      expect(storedDefinition['version'], definition.version + 1);
      expect(storedDefinition['sync_status'], 'pending');

      final price = AssetMarketPrice.manual(
        assetKey: 'web-price-$unique',
        price: 12345,
        unit: 'unit',
      );
      await store.upsertAssetMarketPrice(price.toRecord());
      expect(
        (await store.getAssetMarketPrices()).singleWhere(
          (record) => record['asset_key'] == price.assetKey,
        )['price_minor'],
        12345,
      );
    },
  );
}

class _FailingWebStore extends web_store.LocalStore {
  String? failId;

  @override
  Future<void> upsertTransaction(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    if (record['id'] == failId) throw StateError('simulated web write failure');
    await super.upsertTransaction(record, enqueueSync: enqueueSync);
  }
}

class _StoreFixture {
  _StoreFixture(this.directory, this.path, this.store);

  final Directory directory;
  final String path;
  LocalStore store;

  static Future<_StoreFixture> create(String prefix) async {
    final directory = await Directory.systemTemp.createTemp('$prefix-');
    final path = p.join(directory.path, 'test.db');
    final store = LocalStore(databasePath: path);
    await store.initialize();
    return _StoreFixture(directory, path, store);
  }

  Future<void> reopen() async {
    await store.close();
    store = LocalStore(databasePath: path);
    await store.initialize();
  }

  Future<void> dispose() async {
    await store.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

Transaction _expense({
  required String id,
  required int amount,
  required String title,
}) => Transaction(
  id: id,
  projectId: 'life',
  title: title,
  category: 'Food',
  account: 'Cash',
  date: DateTime.utc(2026, 7, 24, 9),
  amount: amount,
  type: TransactionType.expense,
  createdAt: DateTime.utc(2026, 7, 24, 9),
  updatedAt: DateTime.utc(2026, 7, 24, 9),
);

Transaction _trade({
  required String id,
  required AssetDefinition definition,
  required AssetAction action,
  required double quantity,
  required int amount,
  int feeAmount = 0,
  AssetFeeTreatment feeTreatment = AssetFeeTreatment.none,
  int? referencePrice,
}) {
  final timestamp = DateTime.utc(
    2026,
    7,
    24,
    action == AssetAction.buy ? 10 : 11,
  );
  return Transaction(
    id: id,
    projectId: 'life',
    title: '${action.name} ${definition.displayName}',
    category: 'Asset conversion',
    account: action == AssetAction.buy
        ? 'Cash -> ${definition.displayName}'
        : '${definition.displayName} -> Cash',
    date: timestamp,
    amount: amount,
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: definition.normalizedUnit,
    unitPrice: (amount / quantity).round(),
    assetDefinitionId: definition.id,
    assetName: definition.displayName,
    assetSymbol: definition.normalizedSymbol,
    assetAction: action,
    feeAmount: feeAmount,
    feeTreatment: feeTreatment,
    marketReferenceUnitPrice: referencePrice,
    marketReferenceCurrencyCode: referencePrice == null ? null : 'IDR',
    marketReferenceUnit: referencePrice == null
        ? null
        : definition.normalizedUnit,
    marketReferenceSource: referencePrice == null
        ? null
        : AssetMarketReferenceSource.manual,
    marketReferenceQuotedAt: referencePrice == null ? null : timestamp,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

AssetDefinition _definition({
  required String id,
  required String name,
  required AssetKind kind,
  required String unit,
  String? symbol,
  int lotSize = 1,
}) => AssetDefinition(
  id: id,
  displayName: name,
  kind: kind,
  symbol: symbol,
  providerCode: null,
  providerSymbol: null,
  exchangeCode: kind == AssetKind.stock ? 'IDX' : null,
  currencyCode: 'IDR',
  unit: unit,
  lotSize: lotSize,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
  deletedAt: null,
  version: 1,
  deviceId: 'test-device',
  syncStatus: 'local_only',
);

final _bbca = _definition(
  id: 'asset-bbca',
  name: 'Bank Central Asia',
  kind: AssetKind.stock,
  unit: 'share',
  symbol: 'BBCA',
  lotSize: 100,
);

final _inventory = _definition(
  id: 'asset-inventory-test',
  name: 'Inventory Test',
  kind: AssetKind.inventory,
  unit: 'unit',
);

final _gold = _definition(
  id: 'asset-gold-test',
  name: 'Gold Test',
  kind: AssetKind.gold,
  unit: 'gram',
);

final _userAsset = _definition(
  id: 'asset-user-bond',
  name: 'User Bond',
  kind: AssetKind.other,
  unit: 'unit',
);
