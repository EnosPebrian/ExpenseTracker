import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/data/default_asset_definitions.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_conversion_controller.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/repositories/asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_retirement_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/assets/presentation/models/asset_definition_catalog_query.dart';
import 'package:pilgrim_tracker/features/assets/presentation/services/asset_definition_catalog_filter.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/edit/transaction_form.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';

void main() {
  group('D13 closure audit', () {
    test(
      'fresh defaults exclude obsolete seed and stay idempotent/searchable',
      () async {
        final repository = _AssetRepository();
        final controller = AssetDefinitionController(repository: repository);
        final defaults = buildDefaultAssetDefinitions(
          timestamp: DateTime.utc(2026, 7, 24),
        );

        await controller.initialize(seeds: defaults);
        await controller.initialize(seeds: defaults);

        expect(
          controller.allDefinitions.map((item) => item.id),
          isNot(
            contains(AssetDefinitionRetirementPolicy.retiredStockPortfolioId),
          ),
        );
        expect(controller.definitions, hasLength(defaults.length));
        expect(repository.values, hasLength(defaults.length));
        final search = const AssetDefinitionCatalogFilter().apply(
          definitions: controller.allDefinitions,
          query: const AssetDefinitionCatalogQuery(searchText: 'usd'),
        );
        expect(search.single.id, 'asset-usd');
      },
    );

    test(
      'unused exact legacy seed auto-archives but same-name user asset does not',
      () async {
        final repository = _AssetRepository();
        final legacy = _legacyDefinition();
        final userAsset = _legacyDefinition().copyWith(
          id: 'user-stock-portfolio',
          symbol: 'USER',
        );
        await repository.upsert(legacy);
        await repository.upsert(userAsset);
        final controller = AssetDefinitionController(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 24),
        );

        await controller.initialize();

        expect(controller.definitions.single.id, userAsset.id);
        expect(controller.archivedDefinitions.single.id, legacy.id);
        expect(controller.archivedDefinitions.single.version, 2);
      },
    );

    test(
      'open legacy holding stays active, closes safely, then auto-archives',
      () async {
        final repository = _AssetRepository();
        final legacy = _legacyDefinition();
        final transactionRepository = _TransactionRepository();
        transactionRepository.values.add(
          _trade(
            id: 'buy',
            action: AssetAction.buy,
            quantity: 500,
            amount: 5000000,
          ),
        );
        await repository.upsert(legacy);
        final controller = AssetDefinitionController(
          repository: repository,
          transactionsProvider: () =>
              transactionRepository.getAll(includeDeleted: true),
          now: () => DateTime.utc(2026, 7, 24),
        );
        AssetDefinition? resolve(String id) => id == legacy.id ? legacy : null;
        final transactionController = TransactionController(
          create: CreateTransaction(
            transactionRepository,
            assetDefinitionResolver: resolve,
          ),
          update: UpdateTransaction(
            transactionRepository,
            assetDefinitionResolver: resolve,
          ),
          delete: DeleteTransaction(transactionRepository),
          get: GetTransactions(transactionRepository),
          duplicate: DuplicateTransaction(
            transactionRepository,
            assetDefinitionResolver: resolve,
          ),
          afterMutation: controller.reload,
        );
        addTearDown(controller.dispose);
        addTearDown(transactionController.dispose);
        await controller.initialize();

        expect(controller.definitions.single.id, legacy.id);
        expect(controller.usageFor(legacy).openQuantity, 500);

        await transactionController.createTransaction(
          _trade(
            id: 'sell',
            action: AssetAction.sell,
            quantity: 500,
            amount: 6000000,
          ),
        );

        expect(controller.definitions, isEmpty);
        expect(controller.archivedDefinitions.single.id, legacy.id);
        expect(transactionRepository.values, hasLength(2));
        final portfolio = AssetPortfolioCalculator.calculate(
          transactions: transactionRepository.values,
          assetDefinitions: controller.allDefinitions,
        );
        expect(portfolio.totalCostBasis, 0);
        expect(portfolio.totalRealizedGain, 1000000);
      },
    );

    test(
      'bootstrap ignores an obsolete seed supplied by an old caller',
      () async {
        final repository = _AssetRepository();
        final controller = AssetDefinitionController(repository: repository);

        await controller.initialize(
          seeds: [_legacyDefinition(), _goldDefinition()],
        );

        expect(repository.values.map((item) => item.id), ['asset-gold']);
        expect(controller.definitions.single.id, 'asset-gold');
        expect(controller.archivedDefinitions, isEmpty);
      },
    );

    test('retired seed cannot be restored or edited', () async {
      final repository = _AssetRepository();
      final legacy = _legacyDefinition().copyWith(
        deletedAt: DateTime.utc(2026, 7, 23),
      );
      await repository.upsert(legacy);
      final controller = AssetDefinitionController(repository: repository);
      await controller.initialize();

      await expectLater(
        controller.restore(legacy),
        throwsA(isA<AssetDefinitionLifecycleException>()),
      );
      expect(controller.error, contains('cannot be restored'));
      await expectLater(
        controller.save(legacy.copyWith(deletedAt: null)),
        throwsA(isA<AssetDefinitionLifecycleException>()),
      );
      expect((await repository.getById(legacy.id))?.isDeleted, isTrue);
    });

    test(
      'conversion selectors exclude legacy buys and allow bounded close sales',
      () {
        final legacy = _legacyDefinition();
        final gold = _goldDefinition();
        final existing = [
          _trade(
            id: 'buy',
            action: AssetAction.buy,
            quantity: 500,
            amount: 5000000,
          ),
        ];
        final controller = AssetConversionController(
          accounts: const ['Cash'],
          assets: [legacy, gold],
          existingTransactionsProvider: () => existing,
        );
        addTearDown(controller.dispose);

        expect(
          controller.destinationOptions,
          isNot(contains('Stock Portfolio (STOCK)')),
        );
        controller.setSellAsset(true);
        expect(controller.sourceOptions, contains('Stock Portfolio (STOCK)'));
        controller.setSource('Stock Portfolio (STOCK)');
        controller.cashController.text = '1.200.000';
        controller.quantityController.text = '100';

        expect(controller.isLegacyCloseOnly, isTrue);
        expect(controller.canSave, isTrue);
        final sale = controller.buildTransaction();
        expect(sale.assetDefinitionId, legacy.id);
        expect(sale.assetAction, AssetAction.sell);

        controller.quantityController.text = '600';
        expect(controller.canSave, isFalse);
        expect(controller.oversellMessage, isNotNull);
      },
    );

    test(
      'transaction use cases reject legacy buys and duplicates but allow a sale',
      () async {
        final repository = _TransactionRepository();
        final legacy = _legacyDefinition();
        final originalBuy = _trade(
          id: 'historical-buy',
          action: AssetAction.buy,
          quantity: 500,
          amount: 5000000,
        );
        repository.values.add(originalBuy);
        AssetDefinition? resolve(String id) => id == legacy.id ? legacy : null;
        final create = CreateTransaction(
          repository,
          assetDefinitionResolver: resolve,
        );

        await expectLater(
          create(
            _trade(
              id: 'blocked-buy',
              action: AssetAction.buy,
              quantity: 100,
              amount: 1000000,
            ),
          ),
          throwsA(isA<TransactionValidationException>()),
        );
        await expectLater(
          DuplicateTransaction(repository, assetDefinitionResolver: resolve)(
            originalBuy,
          ),
          throwsA(isA<TransactionValidationException>()),
        );

        final sale = await create(
          _trade(
            id: 'valid-sale',
            action: AssetAction.sell,
            quantity: 100,
            amount: 1200000,
          ),
        );
        expect(sale.assetAction, AssetAction.sell);
        expect(repository.values, hasLength(2));
      },
    );

    test(
      'transaction edit options expose legacy definition only to its sale',
      () {
        final legacy = _legacyDefinition();
        final options = TransactionFormOptions(
          accounts: const ['Cash'],
          expenseCategories: const ['Expense'],
          incomeCategories: const ['Income'],
          projects: const ['Life'],
          assetDefinitions: [legacy, _goldDefinition()],
        );

        final buyOptions = options.assetOptionsFor(
          _trade(
            id: 'buy',
            action: AssetAction.buy,
            quantity: 500,
            amount: 5000000,
          ),
        );
        final saleOptions = options.assetOptionsFor(
          _trade(
            id: 'sell',
            action: AssetAction.sell,
            quantity: 100,
            amount: 1200000,
          ),
        );

        expect(buyOptions, isNot(contains('Stock Portfolio (STOCK)')));
        expect(saleOptions, contains('Stock Portfolio (STOCK)'));
      },
    );
  });
}

AssetDefinition _legacyDefinition() => AssetDefinition(
  id: AssetDefinitionRetirementPolicy.retiredStockPortfolioId,
  displayName: 'Stock Portfolio',
  kind: AssetKind.stock,
  symbol: 'STOCK',
  providerCode: null,
  providerSymbol: null,
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: 'share',
  lotSize: 100,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);

AssetDefinition _goldDefinition() => AssetDefinition(
  id: 'asset-gold',
  displayName: 'Gold Holdings',
  kind: AssetKind.gold,
  symbol: null,
  providerCode: null,
  providerSymbol: null,
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: 'gram',
  lotSize: 1,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);

Transaction _trade({
  required String id,
  required AssetAction action,
  required double quantity,
  required int amount,
}) {
  return Transaction(
    id: id,
    title: action == AssetAction.buy ? 'Legacy acquisition' : 'Legacy sale',
    category: 'Asset conversion',
    account: action == AssetAction.buy
        ? 'Cash -> Stock Portfolio (STOCK)'
        : 'Stock Portfolio (STOCK) -> Cash',
    date: DateTime.utc(2026, 7, action == AssetAction.buy ? 1 : 2),
    amount: amount,
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: 'share',
    unitPrice: (amount / quantity).round(),
    assetDefinitionId: AssetDefinitionRetirementPolicy.retiredStockPortfolioId,
    assetName: 'Stock Portfolio',
    assetSymbol: 'STOCK',
    assetAction: action,
  );
}

class _AssetRepository implements AssetDefinitionRepository {
  final values = <AssetDefinition>[];

  @override
  Future<List<AssetDefinition>> getAll({bool includeDeleted = false}) async {
    return values.where((item) => includeDeleted || !item.isDeleted).toList();
  }

  @override
  Future<AssetDefinition?> getById(String id) async {
    return values.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<void> upsert(AssetDefinition definition) async {
    values.removeWhere((item) => item.id == definition.id);
    values.add(definition);
  }

  @override
  Future<void> softDelete(String id, {required DateTime deletedAt}) async {
    final definition = await getById(id);
    if (definition == null) return;
    await upsert(
      definition.copyWith(
        deletedAt: deletedAt,
        updatedAt: deletedAt,
        version: definition.version + 1,
        syncStatus: 'pending',
      ),
    );
  }

  @override
  Future<void> ensureSeeds(Iterable<AssetDefinition> definitions) async {
    for (final definition in definitions) {
      if (await getById(definition.id) == null) await upsert(definition);
    }
  }
}

class _TransactionRepository implements TransactionRepository {
  final values = <Transaction>[];

  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async {
    return values
        .where((item) => includeDeleted || item.deletedAt == null)
        .toList();
  }

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {
    values.removeWhere((item) => item.id == transaction.id);
    values.add(transaction);
  }

  @override
  Future<void> softDelete(Transaction transaction) => save(transaction);

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {
    await save(parent);
    if (linkedExpense != null) await save(linkedExpense);
    if (obsoleteLinkedExpense != null) await save(obsoleteLinkedExpense);
  }
}
