import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_execution_analysis.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_market_reference_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_numeric_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_trade_validator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  test('combined BBCA fees, lots, and references preserve accounting', () {
    final buy = _stockTrade(
      id: 'buy',
      date: DateTime.utc(2026, 7, 1),
      action: AssetAction.buy,
      quantity: 1000,
      amount: 10000000,
      feeAmount: 100000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      reference: 9800,
    );
    final sell = _stockTrade(
      id: 'sell',
      date: DateTime.utc(2026, 7, 2),
      action: AssetAction.sell,
      quantity: 400,
      amount: 4400000,
      feeAmount: 40000,
      feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
      reference: 11100,
    );

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [buy, sell],
      assetDefinitions: [_bbca],
    );
    final holding = portfolio.holdings.single;
    expect(buy.unitPrice, 10000);
    expect(holding.quantity, 600);
    expect(holding.costBasis, 6060000);
    expect(holding.averageCost, 10100);
    expect(holding.realizedGain, 320000);

    final buyAnalysis = _analysis(buy);
    final sellAnalysis = _analysis(sell);
    expect(buyAnalysis.directionAdjustedDifferencePerUnit, 200);
    expect(buyAnalysis.estimatedTotalDifference, 200000);
    expect(buyAnalysis.outcome, AssetExecutionOutcome.unfavorable);
    expect(sellAnalysis.directionAdjustedDifferencePerUnit, 100);
    expect(sellAnalysis.estimatedTotalDifference, 40000);
    expect(sellAnalysis.outcome, AssetExecutionOutcome.unfavorable);

    final withoutReferences = AssetPortfolioCalculator.calculate(
      transactions: [buy, sell].map(_clearReference),
      assetDefinitions: [_bbca],
    );
    expect(withoutReferences.totalCostBasis, portfolio.totalCostBasis);
    expect(withoutReferences.totalRealizedGain, portfolio.totalRealizedGain);
  });

  test('fees and references cannot bypass stock validation', () {
    const validator = AssetTradeValidator();
    final purchase = _stockTrade(
      id: 'buy',
      date: DateTime.utc(2026, 7, 1),
      action: AssetAction.buy,
      quantity: 500,
      amount: 5000000,
      feeAmount: 10000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      reference: 9900,
    );

    AssetTradeValidationResult validate(double quantity) =>
        validator.validateCandidate(
          existingTransactions: [purchase],
          candidate: _stockTrade(
            id: 'sale-$quantity',
            date: DateTime.utc(2026, 7, 2),
            action: AssetAction.sell,
            quantity: quantity,
            amount: (quantity * 11000).round(),
            feeAmount: 10000,
            feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
            reference: 11100,
          ),
          definition: _bbca,
        );

    expect(validate(600).sequenceValidation.isValid, isFalse);
    expect(validate(150).lotValidation!.isValid, isFalse);
    expect(validate(500).isValid, isTrue);
    expect(validate(100.5).lotValidation!.message, contains('whole shares'));

    final oddPurchase = purchase.copyWith(quantity: 250.0, amount: 2500000);
    final cleanup = validator.validateCandidate(
      existingTransactions: [oddPurchase],
      candidate: _stockTrade(
        id: 'cleanup',
        date: DateTime.utc(2026, 7, 2),
        action: AssetAction.sell,
        quantity: 50,
        amount: 550000,
        feeAmount: 10000,
        feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
        reference: 11100,
      ),
      definition: _bbca,
    );
    expect(cleanup.isValid, isTrue);
    expect(cleanup.lotValidation!.isOddLotCleanup, isTrue);
    expect(cleanup.lotValidation!.remainingShares, 200);
  });

  test('USD precision, oversell, fee accounting, and references coexist', () {
    final buy = _currencyTrade(
      id: 'usd-buy',
      date: DateTime.utc(2026, 7, 1),
      action: AssetAction.buy,
      quantity: 1000,
      amount: 16200000,
      feeAmount: 100000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      reference: 16250,
    );
    final sell = _currencyTrade(
      id: 'usd-sell',
      date: DateTime.utc(2026, 7, 2),
      action: AssetAction.sell,
      quantity: 400,
      amount: 6640000,
      feeAmount: 40000,
      feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
      reference: 16700,
    );
    const validator = AssetTradeValidator();
    final validation = validator.validateCandidate(
      existingTransactions: [buy],
      candidate: sell,
      definition: _usd,
    );
    expect(validation.isValid, isTrue);
    expect(validation.lotValidation, isNull);
    expect(
      AssetNumericPolicy.validateQuantity(
        quantity: 1000.25,
        kind: AssetKind.foreignCurrency,
        symbol: 'USD',
      ).isValid,
      isTrue,
    );
    expect(
      AssetNumericPolicy.validateQuantity(
        quantity: 1000.257,
        kind: AssetKind.foreignCurrency,
        symbol: 'USD',
      ).isValid,
      isFalse,
    );

    final oversell = validator.validateCandidate(
      existingTransactions: [buy],
      candidate: sell.copyWith(quantity: 1000.01, amount: 16600166),
      definition: _usd,
    );
    expect(oversell.sequenceValidation.isValid, isFalse);

    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: [buy, sell],
      assetDefinitions: [_usd],
    );
    final holding = portfolio.holdings.single;
    expect(holding.quantity, 600);
    expect(holding.averageCost, 16300);
    expect(holding.costBasis, 9780000);
    expect(holding.realizedGain, 80000);

    final fullySold = AssetPortfolioCalculator.calculate(
      transactions: [
        buy,
        sell.copyWith(id: 'usd-full-sale', quantity: 1000.0, amount: 16600000),
      ],
      assetDefinitions: [_usd],
    );
    expect(fullySold.holdings, isEmpty);
    expect(fullySold.totalRealizedGain, 260000);

    const referencePolicy = AssetMarketReferencePolicy();
    final sgdPrice = AssetMarketPrice.manual(
      assetKey: 'SGD',
      symbol: 'SGD',
      price: 12150,
      unit: 'sgd',
    );
    expect(
      referencePolicy.isCompatible(definition: _usd, price: sgdPrice),
      isFalse,
    );
  });
}

AssetExecutionAnalysisResult _analysis(Transaction transaction) =>
    AssetExecutionAnalysis.calculate(
      action: transaction.assetAction!,
      quantity: transaction.quantity!,
      executionUnitPrice: transaction.unitPrice!,
      referenceUnitPrice: transaction.marketReferenceUnitPrice!,
    );

Transaction _clearReference(Transaction transaction) => transaction.copyWith(
  marketReferenceUnitPrice: null,
  marketReferenceCurrencyCode: null,
  marketReferenceUnit: null,
  marketReferenceSource: null,
  marketReferenceQuotedAt: null,
);

Transaction _stockTrade({
  required String id,
  required DateTime date,
  required AssetAction action,
  required double quantity,
  required int amount,
  required int feeAmount,
  required AssetFeeTreatment feeTreatment,
  required int reference,
}) => _trade(
  id: id,
  date: date,
  action: action,
  quantity: quantity,
  amount: amount,
  feeAmount: feeAmount,
  feeTreatment: feeTreatment,
  reference: reference,
  definition: _bbca,
);

Transaction _currencyTrade({
  required String id,
  required DateTime date,
  required AssetAction action,
  required double quantity,
  required int amount,
  required int feeAmount,
  required AssetFeeTreatment feeTreatment,
  required int reference,
}) => _trade(
  id: id,
  date: date,
  action: action,
  quantity: quantity,
  amount: amount,
  feeAmount: feeAmount,
  feeTreatment: feeTreatment,
  reference: reference,
  definition: _usd,
);

Transaction _trade({
  required String id,
  required DateTime date,
  required AssetAction action,
  required double quantity,
  required int amount,
  required int feeAmount,
  required AssetFeeTreatment feeTreatment,
  required int reference,
  required AssetDefinition definition,
}) => Transaction(
  id: id,
  title: '${definition.normalizedSymbol} trade',
  category: 'Asset conversion',
  account: action == AssetAction.buy
      ? 'Cash -> ${definition.displayName}'
      : '${definition.displayName} -> Cash',
  date: date,
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
  marketReferenceUnitPrice: reference,
  marketReferenceCurrencyCode: 'IDR',
  marketReferenceUnit: definition.normalizedUnit,
  marketReferenceSource: AssetMarketReferenceSource.manual,
  marketReferenceQuotedAt: date,
  createdAt: date,
  updatedAt: date,
);

final _bbca = _definition(
  id: 'asset-bbca',
  name: 'Bank Central Asia',
  kind: AssetKind.stock,
  symbol: 'BBCA',
  unit: 'share',
  lotSize: 100,
);

final _usd = _definition(
  id: 'asset-usd',
  name: 'US Dollar Cash',
  kind: AssetKind.foreignCurrency,
  symbol: 'USD',
  unit: 'usd',
);

AssetDefinition _definition({
  required String id,
  required String name,
  required AssetKind kind,
  required String symbol,
  required String unit,
  int lotSize = 1,
}) => AssetDefinition(
  id: id,
  displayName: name,
  kind: kind,
  symbol: symbol,
  providerCode: null,
  providerSymbol: null,
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: unit,
  lotSize: lotSize,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);
