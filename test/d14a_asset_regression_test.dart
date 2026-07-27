import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/assets/data/repositories/local_asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_numeric_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

void main() {
  test(
    'all supported asset classes retain accounting after persistence',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'd14a-asset-matrix-',
      );
      final path = p.join(directory.path, 'test.db');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      var store = LocalStore(databasePath: path);
      await store.initialize();
      final definitions = <String, AssetDefinition>{
        for (final definition in _definitions) definition.id: definition,
      };
      final definitionRepository = LocalAssetDefinitionRepository(store);
      for (final definition in definitions.values) {
        await definitionRepository.upsert(definition);
      }
      var repository = LocalTransactionRepository(store);
      final create = CreateTransaction(
        repository,
        assetDefinitionResolver: (id) => definitions[id],
      );

      await create(
        _trade(
          id: 'gold-buy',
          definition: _gold,
          action: AssetAction.buy,
          quantity: 10,
          amount: 10000000,
          order: 1,
          feeAmount: 100000,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
      );
      await create(
        _trade(
          id: 'gold-sale',
          definition: _gold,
          action: AssetAction.sell,
          quantity: 4,
          amount: 4400000,
          order: 2,
          feeAmount: 40000,
          feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
        ),
      );

      await create(
        _trade(
          id: 'bbca-buy',
          definition: _bbca,
          action: AssetAction.buy,
          quantity: 1000,
          amount: 10000000,
          order: 3,
          referencePrice: 9800,
        ),
      );
      await create(
        _trade(
          id: 'bbca-sale',
          definition: _bbca,
          action: AssetAction.sell,
          quantity: 400,
          amount: 4400000,
          order: 4,
          referencePrice: 11200,
        ),
      );

      await create(
        _trade(
          id: 'lot-one-buy',
          definition: _lotOneStock,
          action: AssetAction.buy,
          quantity: 10,
          amount: 1000000,
          order: 5,
        ),
      );
      await create(
        _trade(
          id: 'lot-one-sale',
          definition: _lotOneStock,
          action: AssetAction.sell,
          quantity: 4,
          amount: 480000,
          order: 6,
        ),
      );

      await create(
        _trade(
          id: 'btc-buy',
          definition: _bitcoin,
          action: AssetAction.buy,
          quantity: 0.1,
          amount: 60000000,
          order: 7,
        ),
      );
      await create(
        _trade(
          id: 'btc-sale',
          definition: _bitcoin,
          action: AssetAction.sell,
          quantity: 0.04,
          amount: 26000000,
          order: 8,
        ),
      );

      await create(
        _trade(
          id: 'inventory-buy',
          definition: _inventory,
          action: AssetAction.buy,
          quantity: 10,
          amount: 1000000,
          order: 9,
        ),
      );
      await create(
        _trade(
          id: 'inventory-full-sale',
          definition: _inventory,
          action: AssetAction.sell,
          quantity: 10,
          amount: 1200000,
          order: 10,
        ),
      );

      await create(
        _trade(
          id: 'usd-buy-one',
          definition: _usd,
          action: AssetAction.buy,
          quantity: 1000,
          amount: 16200000,
          order: 11,
        ),
      );
      await create(
        _trade(
          id: 'usd-buy-two',
          definition: _usd,
          action: AssetAction.buy,
          quantity: 500,
          amount: 8250000,
          order: 12,
        ),
      );
      await create(
        _trade(
          id: 'usd-sale',
          definition: _usd,
          action: AssetAction.sell,
          quantity: 400,
          amount: 6640000,
          order: 13,
        ),
      );

      await create(
        _trade(
          id: 'sgd-buy',
          definition: _sgd,
          action: AssetAction.buy,
          quantity: 2500,
          amount: 30000000,
          order: 14,
        ),
      );
      await create(
        _trade(
          id: 'sgd-sale',
          definition: _sgd,
          action: AssetAction.sell,
          quantity: 500,
          amount: 6100000,
          order: 15,
        ),
      );

      final historicalOddLot = _trade(
        id: 'odd-lot-history',
        definition: _oddLotStock,
        action: AssetAction.buy,
        quantity: 250,
        amount: 2500000,
        order: 16,
      );
      await repository.save(historicalOddLot);
      await create(
        _trade(
          id: 'odd-lot-cleanup',
          definition: _oddLotStock,
          action: AssetAction.sell,
          quantity: 50,
          amount: 550000,
          order: 17,
        ),
      );

      await expectLater(
        create(
          _trade(
            id: 'usd-oversell',
            definition: _usd,
            action: AssetAction.sell,
            quantity: 1100.01,
            amount: 18150165,
            order: 18,
          ),
        ),
        throwsA(isA<TransactionValidationException>()),
      );

      final prices = <AssetMarketPrice>[
        _price(_gold, 1200000),
        _price(_bbca, 12000),
        _price(_lotOneStock, 130000),
        _price(_bitcoin, 700000000),
        _price(_usd, 16450),
        _price(_sgd, 12150),
        _price(_oddLotStock, 12000),
      ];
      for (final price in prices) {
        await store.upsertAssetMarketPrice(price.toRecord());
      }

      await store.close();
      store = LocalStore(databasePath: path);
      await store.initialize();
      addTearDown(store.close);
      repository = LocalTransactionRepository(store);

      final persistedTransactions = await repository.getAll();
      final persistedDefinitions = await LocalAssetDefinitionRepository(
        store,
      ).getAll(includeDeleted: true);
      final persistedPrices = (await store.getAssetMarketPrices())
          .map(AssetMarketPrice.fromRecord)
          .toList();
      final portfolio = AssetPortfolioCalculator.calculate(
        transactions: persistedTransactions,
        assetDefinitions: persistedDefinitions,
        marketPrices: persistedPrices,
      );

      void expectHolding(
        AssetDefinition definition, {
        required double quantity,
        required int costBasis,
        required int averageCost,
        required int marketValue,
        required int realizedGain,
      }) {
        final holding = portfolio.holdings.singleWhere(
          (item) => item.assetDefinitionId == definition.id,
        );
        expect(holding.quantity, quantity, reason: definition.id);
        expect(holding.costBasis, costBasis, reason: definition.id);
        expect(holding.averageCost, averageCost, reason: definition.id);
        expect(holding.marketValue, marketValue, reason: definition.id);
        expect(holding.realizedGain, realizedGain, reason: definition.id);
      }

      expectHolding(
        _gold,
        quantity: 6,
        costBasis: 6060000,
        averageCost: 1010000,
        marketValue: 7200000,
        realizedGain: 320000,
      );
      expectHolding(
        _bbca,
        quantity: 600,
        costBasis: 6000000,
        averageCost: 10000,
        marketValue: 7200000,
        realizedGain: 400000,
      );
      expectHolding(
        _lotOneStock,
        quantity: 6,
        costBasis: 600000,
        averageCost: 100000,
        marketValue: 780000,
        realizedGain: 80000,
      );
      expectHolding(
        _bitcoin,
        quantity: 0.06,
        costBasis: 36000000,
        averageCost: 600000000,
        marketValue: 42000000,
        realizedGain: 2000000,
      );
      expectHolding(
        _usd,
        quantity: 1100,
        costBasis: 17930000,
        averageCost: 16300,
        marketValue: 18095000,
        realizedGain: 120000,
      );
      expectHolding(
        _sgd,
        quantity: 2000,
        costBasis: 24000000,
        averageCost: 12000,
        marketValue: 24300000,
        realizedGain: 100000,
      );
      expectHolding(
        _oddLotStock,
        quantity: 200,
        costBasis: 2000000,
        averageCost: 10000,
        marketValue: 2400000,
        realizedGain: 50000,
      );
      expect(
        portfolio.holdings.any(
          (item) => item.assetDefinitionId == _inventory.id,
        ),
        isFalse,
      );
      expect(portfolio.totalRealizedGain, 3270000);

      final referencedBuy = persistedTransactions.singleWhere(
        (item) => item.id == 'bbca-buy',
      );
      expect(referencedBuy.marketReferenceUnitPrice, 9800);
      expect(
        referencedBuy.marketReferenceSource,
        AssetMarketReferenceSource.manual,
      );
      expect(
        portfolio.holdings
            .singleWhere((item) => item.assetDefinitionId == _bbca.id)
            .costBasis,
        6000000,
      );
    },
  );
}

Transaction _trade({
  required String id,
  required AssetDefinition definition,
  required AssetAction action,
  required double quantity,
  required int amount,
  required int order,
  int feeAmount = 0,
  AssetFeeTreatment feeTreatment = AssetFeeTreatment.none,
  int? referencePrice,
}) {
  final timestamp = DateTime.utc(2026, 7, order);
  return Transaction(
    id: id,
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
    unitPrice: AssetNumericPolicy.deriveUnitPrice(
      amount: amount,
      quantity: quantity,
    ),
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

AssetMarketPrice _price(AssetDefinition definition, int value) =>
    AssetMarketPrice.manual(
      assetKey: definition.marketPriceKey,
      symbol: definition.symbol,
      price: value,
      unit: definition.unit,
      quotedAt: DateTime.utc(2026, 7, 24),
    );

AssetDefinition _definition({
  required String id,
  required String name,
  required AssetKind kind,
  required String unit,
  String? symbol,
  String? exchange,
  int lotSize = 1,
}) => AssetDefinition(
  id: id,
  displayName: name,
  kind: kind,
  symbol: symbol,
  providerCode: null,
  providerSymbol: null,
  exchangeCode: exchange,
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

final _gold = _definition(
  id: 'matrix-gold',
  name: 'Matrix Gold',
  kind: AssetKind.gold,
  unit: 'gram',
);
final _bbca = _definition(
  id: 'matrix-bbca',
  name: 'Bank Central Asia',
  kind: AssetKind.stock,
  unit: 'share',
  symbol: 'BBCA',
  exchange: 'IDX',
  lotSize: 100,
);
final _lotOneStock = _definition(
  id: 'matrix-lot-one',
  name: 'Lot One Stock',
  kind: AssetKind.stock,
  unit: 'share',
  symbol: 'LOT1',
  exchange: 'NASDAQ',
);
final _bitcoin = _definition(
  id: 'matrix-bitcoin',
  name: 'Bitcoin',
  kind: AssetKind.crypto,
  unit: 'btc',
  symbol: 'BTC',
);
final _inventory = _definition(
  id: 'matrix-inventory',
  name: 'Inventory',
  kind: AssetKind.inventory,
  unit: 'unit',
);
final _usd = _definition(
  id: 'matrix-usd',
  name: 'US Dollar Cash',
  kind: AssetKind.foreignCurrency,
  unit: 'usd',
  symbol: 'USD',
);
final _sgd = _definition(
  id: 'matrix-sgd',
  name: 'Singapore Dollar Cash',
  kind: AssetKind.foreignCurrency,
  unit: 'sgd',
  symbol: 'SGD',
);
final _oddLotStock = _definition(
  id: 'matrix-odd-lot',
  name: 'Historical Odd Lot',
  kind: AssetKind.stock,
  unit: 'share',
  symbol: 'ODD',
  exchange: 'IDX',
  lotSize: 100,
);

final _definitions = <AssetDefinition>[
  _gold,
  _bbca,
  _lotOneStock,
  _bitcoin,
  _inventory,
  _usd,
  _sgd,
  _oddLotStock,
];
