import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_portfolio.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';

void main() {
  test('calculates gold quantity, cost basis, and unrealized gain', () {
    final transactions = [
      _conversion(
        id: 'gold-buy',
        assetName: 'Gold Holdings',
        action: AssetAction.buy,
        amount: 50000000,
        quantity: 20,
        unit: 'gram',
        unitPrice: 2500000,
      ),
    ];

    final prices = [
      AssetMarketPrice.manual(
        assetKey: 'Gold Holdings',
        symbol: 'XAU',
        price: 2700000,
        unit: 'gram',
      ),
    ];

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      marketPrices: prices,
    );

    expect(portfolio.holdings, hasLength(1));

    final holding = portfolio.holdings.single;

    expect(holding.kind, AssetKind.gold);
    expect(holding.quantity, 20);
    expect(holding.averageCost, 2500000);
    expect(holding.currentPrice, 2700000);
    expect(holding.costBasis, 50000000);
    expect(holding.marketValue, 54000000);
    expect(holding.unrealizedGain, 4000000);
    expect(holding.unrealizedReturn, closeTo(0.08, 0.0001));

    expect(portfolio.totalCostBasis, 50000000);
    expect(portfolio.totalMarketValue, 54000000);
    expect(portfolio.totalUnrealizedGain, 4000000);
  });

  test('calculates weighted stock cost after a partial sale', () {
    final transactions = [
      _conversion(
        id: 'stock-buy-1',
        assetName: 'Stock Portfolio',
        assetSymbol: 'BBCA',
        action: AssetAction.buy,
        amount: 800000,
        quantity: 100,
        unit: 'share',
        unitPrice: 8000,
        date: DateTime(2026, 1, 1),
      ),
      _conversion(
        id: 'stock-buy-2',
        assetName: 'Stock Portfolio',
        assetSymbol: 'BBCA',
        action: AssetAction.buy,
        amount: 1000000,
        quantity: 100,
        unit: 'share',
        unitPrice: 10000,
        date: DateTime(2026, 2, 1),
      ),
      _conversion(
        id: 'stock-sell',
        assetName: 'Stock Portfolio',
        assetSymbol: 'BBCA',
        action: AssetAction.sell,
        amount: 550000,
        quantity: 50,
        unit: 'share',
        unitPrice: 11000,
        date: DateTime(2026, 3, 1),
      ),
    ];

    final prices = [
      AssetMarketPrice.manual(
        assetKey: 'BBCA',
        symbol: 'BBCA',
        price: 10000,
        unit: 'share',
      ),
    ];

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      marketPrices: prices,
    );

    final holding = portfolio.holdings.single;

    expect(holding.kind, AssetKind.stock);
    expect(holding.symbol, 'BBCA');
    expect(holding.assetDefinitionId, isNull);
    expect(holding.providerCode, isNull);
    expect(holding.providerSymbol, isNull);
    expect(holding.quoteSymbol, 'BBCA');
    expect(holding.normalizedCurrencyCode, 'IDR');
    expect(holding.onlinePricingEnabled, isTrue);
    expect(holding.quantity, 150);
    expect(holding.lotSize, 100);
    expect(holding.lots, 1.5);

    expect(holding.averageCost, 9000);
    expect(holding.costBasis, 1350000);
    expect(holding.currentPrice, 10000);
    expect(holding.marketValue, 1500000);
    expect(holding.unrealizedGain, 150000);
    expect(holding.realizedGain, 100000);
  });

  test('uses cost basis when no current market price exists', () {
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [
        _conversion(
          id: 'unpriced-gold',
          assetName: 'Gold Holdings',
          action: AssetAction.buy,
          amount: 2500000,
          quantity: 1,
          unit: 'gram',
          unitPrice: 2500000,
        ),
      ],
    );

    final holding = portfolio.holdings.single;

    expect(holding.hasMarketPrice, isFalse);
    expect(holding.currentPrice, isNull);
    expect(holding.marketValue, holding.costBasis);
    expect(holding.unrealizedGain, 0);
  });

  test('ignores cached price with a mismatched currency', () {
    final transaction = _conversion(
      id: 'bbca-currency-mismatch',
      assetDefinitionId: 'asset-bbca',
      assetName: 'Bank Central Asia',
      assetSymbol: 'BBCA',
      action: AssetAction.buy,
      amount: 1000000,
      quantity: 100,
      unit: 'share',
      unitPrice: 10000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [_bbcaDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'BBCA',
          symbol: 'BBCA',
          price: 9500,
          currencyCode: 'USD',
          unit: 'share',
        ),
      ],
    );

    final holding = portfolio.holdings.single;

    expect(holding.hasMarketPrice, isFalse);
    expect(holding.currentPrice, isNull);
    expect(holding.marketValue, holding.costBasis);
    expect(holding.unrealizedGain, 0);
  });

  test('ignores cached price with a mismatched unit', () {
    final transaction = _conversion(
      id: 'bbca-unit-mismatch',
      assetDefinitionId: 'asset-bbca',
      assetName: 'Bank Central Asia',
      assetSymbol: 'BBCA',
      action: AssetAction.buy,
      amount: 1000000,
      quantity: 100,
      unit: 'share',
      unitPrice: 10000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [_bbcaDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'BBCA',
          symbol: 'BBCA',
          price: 9500,
          currencyCode: 'IDR',
          unit: 'unit',
        ),
      ],
    );

    final holding = portfolio.holdings.single;

    expect(holding.hasMarketPrice, isFalse);
    expect(holding.currentPrice, isNull);
    expect(holding.marketValue, holding.costBasis);
    expect(holding.unrealizedGain, 0);
  });

  test('supports legacy conversions without explicit asset fields', () {
    final transaction = Transaction(
      id: 'legacy-gold',
      title: 'Gold Holdings acquisition',
      category: 'Asset conversion',
      account: 'Cash Enos -> Gold Holdings',
      date: DateTime(2025, 1, 1),
      amount: 5000000,
      type: TransactionType.assetConversion,
      quantity: 2,
      unit: 'gram',
      unitPrice: 2500000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
    );

    expect(portfolio.holdings, hasLength(1));

    final holding = portfolio.holdings.single;

    expect(holding.assetKey, 'Gold Holdings');
    expect(holding.quantity, 2);
    expect(holding.costBasis, 5000000);
  });

  test('linked definition supplies identity, kind, unit, and lot size', () {
    final transaction = _conversion(
      id: 'linked-bbca-buy',
      assetDefinitionId: 'asset-bbca',
      assetName: 'Legacy Stock Portfolio',
      assetSymbol: 'OLD',
      action: AssetAction.buy,
      amount: 1000000,
      quantity: 100,
      unit: 'unit',
      unitPrice: 10000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [_bbcaDefinition()],
    );

    expect(portfolio.holdings, hasLength(1));

    final holding = portfolio.holdings.single;

    expect(holding.assetDefinitionId, 'asset-bbca');
    expect(holding.providerCode, 'ALPHA_VANTAGE');
    expect(holding.providerSymbol, 'BBCA.JK');
    expect(holding.quoteSymbol, 'BBCA.JK');
    expect(holding.currencyCode, 'IDR');
    expect(holding.normalizedCurrencyCode, 'IDR');
    expect(holding.onlinePricingEnabled, isTrue);
    expect(holding.assetKey, 'BBCA');
    expect(holding.name, 'Bank Central Asia');
    expect(holding.symbol, 'BBCA');
    expect(holding.kind, AssetKind.stock);
    expect(holding.unit, 'share');
    expect(holding.lotSize, 100);
    expect(holding.quantity, 100);
    expect(holding.lots, 1);
  });
  test('missing definition falls back to stored transaction snapshots', () {
    final transaction = _conversion(
      id: 'missing-definition-gold',
      assetDefinitionId: 'removed-asset-definition',
      assetName: 'Gold Holdings',
      action: AssetAction.buy,
      amount: 5000000,
      quantity: 2,
      unit: 'gram',
      unitPrice: 2500000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: const [],
    );

    final holding = portfolio.holdings.single;

    expect(holding.assetDefinitionId, isNull);
    expect(holding.assetKey, 'Gold Holdings');
    expect(holding.name, 'Gold Holdings');
    expect(holding.kind, AssetKind.gold);
    expect(holding.unit, 'gram');
    expect(holding.quantity, 2);
  });
  test('archived definition remains readable for historical transactions', () {
    final transaction = _conversion(
      id: 'archived-usd-buy',
      assetDefinitionId: 'asset-usd',
      assetName: 'US Dollar Cash',
      assetSymbol: 'USD',
      action: AssetAction.buy,
      amount: 16200000,
      quantity: 1000,
      unit: 'usd',
      unitPrice: 16200,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [
        _usdDefinition().copyWith(deletedAt: DateTime.utc(2026, 7, 24)),
      ],
    );

    final holding = portfolio.holdings.single;

    expect(holding.assetDefinitionId, 'asset-usd');
    expect(holding.name, 'US Dollar Cash');
    expect(holding.symbol, 'USD');
    expect(holding.kind, AssetKind.foreignCurrency);
    expect(holding.quantity, 1000);
    expect(holding.costBasis, 16200000);
  });
  test('values foreign currency holding using a cached FX rate', () {
    final transaction = _conversion(
      id: 'usd-buy',
      assetDefinitionId: 'asset-usd',
      assetName: 'US Dollar Cash',
      assetSymbol: 'USD',
      action: AssetAction.buy,
      amount: 16000000,
      quantity: 1000,
      unit: 'usd',
      unitPrice: 16000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [_usdDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'USD',
          symbol: 'USD/IDR',
          price: 16500,
          currencyCode: 'IDR',
          unit: 'usd',
        ),
      ],
    );

    expect(portfolio.holdings, hasLength(1));

    final holding = portfolio.holdings.single;

    expect(holding.assetDefinitionId, 'asset-usd');
    expect(holding.kind, AssetKind.foreignCurrency);
    expect(holding.assetKey, 'USD');
    expect(holding.name, 'US Dollar Cash');
    expect(holding.symbol, 'USD');
    expect(holding.providerSymbol, 'USD/IDR');
    expect(holding.currencyCode, 'IDR');
    expect(holding.unit, 'usd');

    expect(holding.quantity, 1000);
    expect(holding.averageCost, 16000);
    expect(holding.costBasis, 16000000);
    expect(holding.currentPrice, 16500);
    expect(holding.marketValue, 16500000);
    expect(holding.unrealizedGain, 500000);

    expect(portfolio.totalCostBasis, 16000000);
    expect(portfolio.totalMarketValue, 16500000);
    expect(portfolio.totalUnrealizedGain, 500000);
  });
  test('calculates weighted-average USD purchases and partial sale', () {
    final transactions = [
      _conversion(
        id: 'usd-buy-one',
        assetDefinitionId: 'asset-usd',
        assetName: 'US Dollar Cash',
        assetSymbol: 'USD',
        action: AssetAction.buy,
        amount: 16200000,
        quantity: 1000,
        unit: 'usd',
        unitPrice: 16200,
        date: DateTime(2026, 1, 1),
      ),
      _conversion(
        id: 'usd-buy-two',
        assetDefinitionId: 'asset-usd',
        assetName: 'US Dollar Cash',
        assetSymbol: 'USD',
        action: AssetAction.buy,
        amount: 8250000,
        quantity: 500,
        unit: 'usd',
        unitPrice: 16500,
        date: DateTime(2026, 2, 1),
      ),
      _conversion(
        id: 'usd-sale',
        assetDefinitionId: 'asset-usd',
        assetName: 'US Dollar Cash',
        assetSymbol: 'USD',
        action: AssetAction.sell,
        amount: 6640000,
        quantity: 400,
        unit: 'usd',
        unitPrice: 16600,
        date: DateTime(2026, 3, 1),
      ),
    ];

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      assetDefinitions: [_usdDefinition()],
    );

    final holding = portfolio.holdings.single;

    expect(holding.quantity, 1100);
    expect(holding.costBasis, 17930000);
    expect(holding.averageCost, 16300);
    expect(holding.realizedGain, 120000);
    expect(portfolio.totalRealizedGain, 120000);
  });

  test('calculates SGD valuation and realized gain independently', () {
    final transactions = [
      _conversion(
        id: 'sgd-buy',
        assetDefinitionId: 'asset-sgd',
        assetName: 'Singapore Dollar Cash',
        assetSymbol: 'SGD',
        action: AssetAction.buy,
        amount: 30000000,
        quantity: 2500,
        unit: 'sgd',
        unitPrice: 12000,
        date: DateTime(2026, 1, 1),
      ),
      _conversion(
        id: 'sgd-sale',
        assetDefinitionId: 'asset-sgd',
        assetName: 'Singapore Dollar Cash',
        assetSymbol: 'SGD',
        action: AssetAction.sell,
        amount: 6100000,
        quantity: 500,
        unit: 'sgd',
        unitPrice: 12200,
        date: DateTime(2026, 2, 1),
      ),
    ];

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      assetDefinitions: [_sgdDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'SGD',
          symbol: 'SGD/IDR',
          price: 12150,
          currencyCode: 'IDR',
          unit: 'sgd',
        ),
      ],
    );

    final holding = portfolio.holdings.single;

    expect(holding.quantity, 2000);
    expect(holding.costBasis, 24000000);
    expect(holding.averageCost, 12000);
    expect(holding.marketValue, 24300000);
    expect(holding.unrealizedGain, 300000);
    expect(holding.realizedGain, 100000);
  });

  test('rejects incompatible FX identity, unit, and valuation currency', () {
    final transaction = _conversion(
      id: 'usd-buy',
      assetDefinitionId: 'asset-usd',
      assetName: 'US Dollar Cash',
      assetSymbol: 'USD',
      action: AssetAction.buy,
      amount: 16000000,
      quantity: 1000,
      unit: 'usd',
      unitPrice: 16000,
    );

    final incompatiblePrices = [
      AssetMarketPrice.manual(
        assetKey: 'SGD',
        symbol: 'SGD/IDR',
        price: 12150,
        currencyCode: 'IDR',
        unit: 'sgd',
      ),
      AssetMarketPrice.manual(
        assetKey: 'USD',
        symbol: 'USD/IDR',
        price: 16500,
        currencyCode: 'IDR',
        unit: 'gram',
      ),
      AssetMarketPrice.manual(
        assetKey: 'USD',
        symbol: 'SGD/IDR',
        price: 16500,
        currencyCode: 'IDR',
        unit: 'usd',
      ),
      AssetMarketPrice.manual(
        assetKey: 'USD',
        symbol: 'USD/IDR',
        price: 16500,
        currencyCode: 'SGD',
        unit: 'usd',
      ),
    ];

    for (final price in incompatiblePrices) {
      final portfolio = AssetPortfolioCalculator.calculate(
        transactions: [transaction],
        assetDefinitions: [_usdDefinition()],
        marketPrices: [price],
      );

      final holding = portfolio.holdings.single;

      expect(holding.currentPrice, isNull);
      expect(holding.costBasis, 16000000);
      expect(holding.marketValue, 16000000);
    }
  });

  test('USD quote cannot value an SGD holding', () {
    final transaction = _conversion(
      id: 'sgd-buy',
      assetDefinitionId: 'asset-sgd',
      assetName: 'Singapore Dollar Cash',
      assetSymbol: 'SGD',
      action: AssetAction.buy,
      amount: 12000000,
      quantity: 1000,
      unit: 'sgd',
      unitPrice: 12000,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [_sgdDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'USD',
          symbol: 'USD/IDR',
          price: 16500,
          currencyCode: 'IDR',
          unit: 'usd',
        ),
      ],
    );

    final holding = portfolio.holdings.single;

    expect(holding.currentPrice, isNull);
    expect(holding.costBasis, 12000000);
    expect(holding.marketValue, 12000000);
  });

  test('manual USD and SGD prices do not require provider-pair metadata', () {
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [
        _conversion(
          id: 'usd-buy',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.buy,
          amount: 16200000,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16200,
        ),
        _conversion(
          id: 'sgd-buy',
          assetDefinitionId: 'asset-sgd',
          assetName: 'Singapore Dollar Cash',
          assetSymbol: 'SGD',
          action: AssetAction.buy,
          amount: 12000000,
          quantity: 1000,
          unit: 'sgd',
          unitPrice: 12000,
        ),
      ],
      assetDefinitions: [_usdDefinition(), _sgdDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'USD',
          price: 16450,
          currencyCode: 'IDR',
          unit: 'usd',
        ),
        AssetMarketPrice.manual(
          assetKey: 'SGD',
          price: 12150,
          currencyCode: 'IDR',
          unit: 'sgd',
        ),
      ],
    );

    final bySymbol = {
      for (final holding in portfolio.holdings) holding.symbol: holding,
    };

    expect(bySymbol['USD']!.currentPrice, 16450);
    expect(bySymbol['USD']!.marketValue, 16450000);
    expect(bySymbol['SGD']!.currentPrice, 12150);
    expect(bySymbol['SGD']!.marketValue, 12150000);
  });

  test('fully sold USD retains realized gain in portfolio totals', () {
    final transactions = [
      _conversion(
        id: 'usd-full-buy',
        assetDefinitionId: 'asset-usd',
        assetName: 'US Dollar Cash',
        assetSymbol: 'USD',
        action: AssetAction.buy,
        amount: 16200000,
        quantity: 1000,
        unit: 'usd',
        unitPrice: 16200,
        date: DateTime(2026, 1, 1),
      ),
      _conversion(
        id: 'usd-full-sell',
        assetDefinitionId: 'asset-usd',
        assetName: 'US Dollar Cash',
        assetSymbol: 'USD',
        action: AssetAction.sell,
        amount: 16600000,
        quantity: 1000,
        unit: 'usd',
        unitPrice: 16600,
        date: DateTime(2026, 2, 1),
      ),
    ];

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      assetDefinitions: [_usdDefinition()],
    );

    expect(portfolio.holdings, isEmpty);
    expect(portfolio.totalCostBasis, 0);
    expect(portfolio.totalMarketValue, 0);
    expect(portfolio.totalUnrealizedGain, 0);
    expect(portfolio.totalRealizedGain, 400000);
  });
  test('fully sold position contributes to total realized gain', () {
    final transactions = [
      _conversion(
        id: 'bbca-full-buy',
        assetDefinitionId: 'asset-bbca',
        assetName: 'Bank Central Asia',
        assetSymbol: 'BBCA',
        action: AssetAction.buy,
        amount: 800000,
        quantity: 100,
        unit: 'share',
        unitPrice: 8000,
        date: DateTime(2026, 1, 1),
      ),
      _conversion(
        id: 'bbca-full-sell',
        assetDefinitionId: 'asset-bbca',
        assetName: 'Bank Central Asia',
        assetSymbol: 'BBCA',
        action: AssetAction.sell,
        amount: 900000,
        quantity: 100,
        unit: 'share',
        unitPrice: 9000,
        date: DateTime(2026, 2, 1),
      ),
    ];

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      assetDefinitions: [_bbcaDefinition()],
    );

    expect(portfolio.holdings, isEmpty);
    expect(portfolio.totalCostBasis, 0);
    expect(portfolio.totalMarketValue, 0);
    expect(portfolio.totalUnrealizedGain, 0);
    expect(portfolio.totalRealizedGain, 100000);
  });

  test('capitalized USD buy fee increases cost basis and average cost', () {
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [
        _conversion(
          id: 'usd-buy-with-fee',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.buy,
          amount: 16200000,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16200,
          feeAmount: 100000,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
      ],
      assetDefinitions: [_usdDefinition()],
    );

    final holding = portfolio.holdings.single;
    expect(holding.quantity, 1000);
    expect(holding.costBasis, 16300000);
    expect(holding.averageCost, 16300);
  });

  test('weighted average includes capitalized fees from multiple buys', () {
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [
        _conversion(
          id: 'usd-buy-1',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.buy,
          amount: 16200000,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16200,
          feeAmount: 100000,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
        _conversion(
          id: 'usd-buy-2',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.buy,
          amount: 8250000,
          quantity: 500,
          unit: 'usd',
          unitPrice: 16500,
          feeAmount: 50000,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
          date: DateTime(2026, 1, 2),
        ),
      ],
      assetDefinitions: [_usdDefinition()],
    );

    final holding = portfolio.holdings.single;
    expect(holding.quantity, 1500);
    expect(holding.costBasis, 24600000);
    expect(holding.averageCost, 16400);
  });

  test('partial sale removes fee-inclusive cost and deducts sell fee', () {
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [
        _conversion(
          id: 'usd-buy',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.buy,
          amount: 16200000,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16200,
          feeAmount: 100000,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
        _conversion(
          id: 'usd-sell',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.sell,
          amount: 6640000,
          quantity: 400,
          unit: 'usd',
          unitPrice: 16600,
          feeAmount: 40000,
          feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
          date: DateTime(2026, 2, 1),
        ),
      ],
      assetDefinitions: [_usdDefinition()],
    );

    final holding = portfolio.holdings.single;
    expect(holding.quantity, 600);
    expect(holding.costBasis, 9780000);
    expect(holding.averageCost, 16300);
    expect(holding.realizedGain, 80000);
  });

  test('fees do not affect quantity, unit price, or market price', () {
    final transaction = _conversion(
      id: 'sgd-buy-with-fee',
      assetDefinitionId: 'asset-sgd',
      assetName: 'Singapore Dollar Cash',
      assetSymbol: 'SGD',
      action: AssetAction.buy,
      amount: 30000000,
      quantity: 2500,
      unit: 'sgd',
      unitPrice: 12000,
      feeAmount: 50000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
    );
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [transaction],
      assetDefinitions: [_sgdDefinition()],
      marketPrices: [
        AssetMarketPrice.manual(
          assetKey: 'SGD',
          price: 12150,
          currencyCode: 'IDR',
          unit: 'sgd',
        ),
      ],
    );

    final holding = portfolio.holdings.single;
    expect(transaction.unitPrice, 12000);
    expect(holding.quantity, 2500);
    expect(holding.currentPrice, 12150);
    expect(holding.marketValue, 30375000);
    expect(holding.costBasis, 30050000);
    expect(holding.unrealizedGain, 325000);
  });

  test('fully sold position retains net realized gain after fees', () {
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [
        _conversion(
          id: 'usd-buy',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.buy,
          amount: 16200000,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16200,
          feeAmount: 100000,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
        _conversion(
          id: 'usd-sell',
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          action: AssetAction.sell,
          amount: 16600000,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16600,
          feeAmount: 40000,
          feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
          date: DateTime(2026, 2, 1),
        ),
      ],
      assetDefinitions: [_usdDefinition()],
    );

    expect(portfolio.holdings, isEmpty);
    expect(portfolio.totalRealizedGain, 260000);
  });

  test(
    'floating residue creates no phantom holding and keeps realized gain',
    () {
      final portfolio = AssetPortfolioCalculator.calculate(
        transactions: [
          _conversion(
            id: 'usd-buy-1',
            assetDefinitionId: 'asset-usd',
            assetName: 'US Dollar Cash',
            assetSymbol: 'USD',
            action: AssetAction.buy,
            amount: 1620,
            quantity: 0.1,
            unit: 'usd',
            unitPrice: 16200,
          ),
          _conversion(
            id: 'usd-buy-2',
            assetDefinitionId: 'asset-usd',
            assetName: 'US Dollar Cash',
            assetSymbol: 'USD',
            action: AssetAction.buy,
            amount: 3240,
            quantity: 0.2,
            unit: 'usd',
            unitPrice: 16200,
            date: DateTime(2026, 1, 2),
          ),
          _conversion(
            id: 'usd-sell',
            assetDefinitionId: 'asset-usd',
            assetName: 'US Dollar Cash',
            assetSymbol: 'USD',
            action: AssetAction.sell,
            amount: 5000,
            quantity: 0.3,
            unit: 'usd',
            unitPrice: 16667,
            date: DateTime(2026, 1, 3),
          ),
        ],
        assetDefinitions: [_usdDefinition()],
      );

      expect(portfolio.holdings, isEmpty);
      expect(portfolio.totalCostBasis, 0);
      expect(portfolio.totalRealizedGain, 140);
    },
  );

  test(
    'historical over-precision quantity still participates in calculation',
    () {
      final portfolio = AssetPortfolioCalculator.calculate(
        transactions: [
          _conversion(
            id: 'legacy-gold',
            assetName: 'Gold Holdings',
            action: AssetAction.buy,
            amount: 3086400,
            quantity: 1.23456,
            unit: 'gram',
            unitPrice: 2500000,
          ),
        ],
      );

      expect(portfolio.holdings.single.quantity, 1.23456);
      expect(portfolio.holdings.single.costBasis, 3086400);
    },
  );
}

AssetDefinition _bbcaDefinition() {
  return AssetDefinition(
    id: 'asset-bbca',
    displayName: 'Bank Central Asia',
    kind: AssetKind.stock,
    symbol: 'BBCA',
    providerCode: 'alpha_vantage',
    providerSymbol: 'BBCA.JK',
    exchangeCode: 'IDX',
    currencyCode: 'IDR',
    unit: 'share',
    lotSize: 100,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21),
    updatedAt: DateTime.utc(2026, 7, 21),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

AssetDefinition _usdDefinition() {
  return AssetDefinition(
    id: 'asset-usd',
    displayName: 'US Dollar Cash',
    kind: AssetKind.foreignCurrency,
    symbol: 'USD',
    providerCode: 'alpha_vantage',
    providerSymbol: 'USD/IDR',
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: 'usd',
    lotSize: 1,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 23),
    updatedAt: DateTime.utc(2026, 7, 23),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

AssetDefinition _sgdDefinition() {
  return AssetDefinition(
    id: 'asset-sgd',
    displayName: 'Singapore Dollar Cash',
    kind: AssetKind.foreignCurrency,
    symbol: 'SGD',
    providerCode: 'alpha_vantage',
    providerSymbol: 'SGD/IDR',
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: 'sgd',
    lotSize: 1,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 23),
    updatedAt: DateTime.utc(2026, 7, 23),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

Transaction _conversion({
  required String id,
  required String assetName,
  String? assetDefinitionId,
  String? assetSymbol,
  required AssetAction action,
  required int amount,
  required double quantity,
  required String unit,
  required int unitPrice,
  int feeAmount = 0,
  AssetFeeTreatment feeTreatment = AssetFeeTreatment.none,
  DateTime? date,
}) {
  final isSell = action == AssetAction.sell;

  return Transaction(
    id: id,
    title: isSell ? '$assetName sale' : '$assetName acquisition',
    category: 'Asset conversion',
    account: isSell ? '$assetName -> Cash Enos' : 'Cash Enos -> $assetName',
    date: date ?? DateTime(2026, 1, 1),
    amount: amount,
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: unit,
    unitPrice: unitPrice,
    assetDefinitionId: assetDefinitionId,
    assetName: assetName,
    assetSymbol: assetSymbol,
    assetAction: action,
    feeAmount: feeAmount,
    feeTreatment: feeTreatment,
  );
}
