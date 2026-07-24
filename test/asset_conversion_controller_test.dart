import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_conversion_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  test('stock conversion uses the selected concrete asset definition', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_goldDefinition(), _bbcaDefinition()],
    );

    addTearDown(controller.dispose);

    controller.setDestination('Bank Central Asia (BBCA)');
    controller.quantityController.text = '100';

    expect(controller.selectedAssetDefinition.id, 'asset-bbca');

    expect(controller.unit, 'share');
    expect(controller.currencyCode, 'IDR');
    expect(controller.canSave, isTrue);

    final transaction = controller.buildTransaction();

    expect(transaction.type, TransactionType.assetConversion);

    expect(transaction.assetName, 'Bank Central Asia');
    expect(transaction.assetDefinitionId, 'asset-bbca');

    expect(transaction.assetSymbol, 'BBCA');
    expect(transaction.assetAction, AssetAction.buy);
    expect(transaction.unit, 'share');
  });

  test('gold conversion uses the definition unit and no ticker', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_goldDefinition(), _bbcaDefinition()],
    );

    addTearDown(controller.dispose);

    expect(controller.selectedAssetDefinition.displayName, 'Gold Holdings');

    expect(controller.unit, 'gram');
    expect(controller.canSave, isTrue);

    final transaction = controller.buildTransaction();

    expect(transaction.assetName, 'Gold Holdings');
    expect(transaction.assetDefinitionId, 'asset-gold');
    expect(transaction.assetSymbol, isNull);
    expect(transaction.assetAction, AssetAction.buy);
    expect(transaction.unit, 'gram');
  });
  test('foreign currency conversion records IDR paid per currency unit', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );

    addTearDown(controller.dispose);

    expect(controller.selectedAssetDefinition.id, 'asset-usd');
    expect(controller.unit, 'usd');
    expect(controller.currencyCode, 'IDR');
    expect(controller.supportsSelectedCurrency, isTrue);

    controller.cashController.text = '16.000.000';
    controller.quantityController.text = '1000';

    expect(controller.cash, 16000000);
    expect(controller.quantity, 1000);
    expect(controller.unitPrice, 16000);
    expect(controller.canSave, isTrue);

    final transaction = controller.buildTransaction();

    expect(transaction.assetDefinitionId, 'asset-usd');
    expect(transaction.assetName, 'US Dollar Cash');
    expect(transaction.assetSymbol, 'USD');
    expect(transaction.assetAction, AssetAction.buy);
    expect(transaction.amount, 16000000);
    expect(transaction.quantity, 1000);
    expect(transaction.unit, 'usd');
    expect(transaction.unitPrice, 16000);
  });
  test('foreign currency sale records IDR proceeds and derived rate', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );

    addTearDown(controller.dispose);

    controller.setSellAsset(true);
    controller.cashController.text = '6.640.000';
    controller.quantityController.text = '400';

    expect(controller.cashLabel, 'Gross proceeds');
    expect(controller.quantityLabel, 'USD sold');
    expect(
      controller.calculatedRateLabel,
      'Calculated rate: Rp 16.600 per USD',
    );
    expect(controller.canSave, isTrue);

    final transaction = controller.buildTransaction();

    expect(transaction.assetAction, AssetAction.sell);
    expect(transaction.assetDefinitionId, 'asset-usd');
    expect(transaction.assetSymbol, 'USD');
    expect(transaction.quantity, 400);
    expect(transaction.amount, 6640000);
    expect(transaction.unitPrice, 16600);
  });

  test('SGD conversion uses the concrete definition without ticker rules', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_sgdDefinition()],
    );

    addTearDown(controller.dispose);

    controller.cashController.text = '30.000.000';
    controller.quantityController.text = '2500';

    expect(controller.currencySymbol, 'SGD');
    expect(controller.quantityLabel, 'SGD received');
    expect(
      controller.calculatedRateLabel,
      'Calculated rate: Rp 12.000 per SGD',
    );

    final transaction = controller.buildTransaction();

    expect(transaction.assetDefinitionId, 'asset-sgd');
    expect(transaction.assetSymbol, 'SGD');
    expect(transaction.unit, 'sgd');
    expect(transaction.unitPrice, 12000);
  });

  test('unit price uses Dart integer-nearest rounding for non-exact rates', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );

    addTearDown(controller.dispose);

    controller.cashController.text = '5';
    controller.quantityController.text = '2';

    expect(controller.unitPrice, 3);
    expect(controller.buildTransaction().unitPrice, 3);
  });

  test('deleted asset definitions are excluded from new conversions', () {
    final deletedUsd = _usdDefinition().copyWith(
      deletedAt: DateTime.utc(2026, 7, 24),
    );
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [deletedUsd, _sgdDefinition()],
    );

    addTearDown(controller.dispose);

    expect(controller.assets, hasLength(1));
    expect(controller.selectedAssetDefinition.id, 'asset-sgd');
    expect(controller.sourceOptions, isNot(contains('US Dollar Cash (USD)')));
    expect(
      controller.destinationOptions,
      isNot(contains('US Dollar Cash (USD)')),
    );
  });

  test('conversion requires at least one active asset definition', () {
    expect(
      () => AssetConversionController(
        accounts: const ['Cash Enos'],
        assets: [
          _usdDefinition().copyWith(deletedAt: DateTime.utc(2026, 7, 24)),
        ],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('active measurable asset'),
        ),
      ),
    );
  });
  test('non-IDR asset conversion is blocked until FX is supported', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_appleDefinition()],
    );

    addTearDown(controller.dispose);

    expect(controller.currencyCode, 'USD');
    expect(controller.supportsSelectedCurrency, isFalse);
    expect(controller.canSave, isFalse);

    expect(
      controller.buildTransaction,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('currently supports IDR-valued assets only'),
        ),
      ),
    );
  });

  test('sell exposes availability and blocks oversell before build', () {
    final purchase = _usdPurchase(1000);
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
      existingTransactionsProvider: () => [purchase],
    );

    addTearDown(controller.dispose);

    controller.setSellAsset(true);
    controller.cashController.text = '24.000.000';
    controller.quantityController.text = '1500';

    expect(controller.availableQuantity, 1000);
    expect(controller.canSave, isFalse);
    expect(controller.oversellMessage, contains('Requested: USD 1500'));
    expect(
      controller.buildTransaction,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('sell up to USD 1000'),
        ),
      ),
    );
  });

  test('sell exactly equal to availability remains enabled', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
      existingTransactionsProvider: () => [_usdPurchase(1000)],
    );

    addTearDown(controller.dispose);

    controller.setSellAsset(true);
    controller.cashController.text = '16.500.000';
    controller.quantityController.text = '1000';

    expect(controller.availableQuantity, 1000);
    expect(controller.oversellMessage, isNull);
    expect(controller.canSave, isTrue);
    expect(controller.buildTransaction().assetAction, AssetAction.sell);
  });

  test('buy fee is capitalized without changing derived unit price', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);

    controller.cashController.text = '16.200.000';
    controller.quantityController.text = '1000';
    controller.feeController.text = '100.000';

    expect(controller.feeAmount, 100000);
    expect(controller.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(controller.grossTradeAmount, 16200000);
    expect(controller.totalCashPaid, 16300000);
    expect(controller.unitPrice, 16200);

    final transaction = controller.buildTransaction();
    expect(transaction.amount, 16200000);
    expect(transaction.feeAmount, 100000);
    expect(transaction.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(transaction.unitPrice, 16200);
  });

  test('sell fee is deducted from gross proceeds', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);

    controller.setSellAsset(true);
    controller.cashController.text = '6.640.000';
    controller.quantityController.text = '400';
    controller.feeController.text = '40.000';

    expect(controller.feeTreatment, AssetFeeTreatment.deductFromSaleProceeds);
    expect(controller.netProceeds, 6600000);
    expect(controller.unitPrice, 16600);
    expect(controller.buildTransaction().feeAmount, 40000);
  });

  test('separate expense keeps portfolio values gross and cash effect net', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);

    controller.cashController.text = '16.200.000';
    controller.quantityController.text = '1000';
    controller.feeController.text = '100.000';
    controller.setFeeTreatment(AssetFeeTreatment.recordAsSeparateExpense);

    expect(controller.totalCashPaid, 16300000);
    expect(controller.costBasisAdded, 16200000);
    expect(controller.buildTransaction().unitPrice, 16200);

    controller.setSellAsset(true);
    expect(controller.feeTreatment, AssetFeeTreatment.recordAsSeparateExpense);
    controller.cashController.text = '6.640.000';
    controller.quantityController.text = '400';
    controller.feeController.text = '40.000';
    expect(controller.netProceeds, 6600000);
    expect(controller.buildTransaction().amount, 6640000);
  });

  test('action switch resets incompatible fee treatment', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);

    controller.feeController.text = '100.000';
    expect(controller.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);

    controller.setSellAsset(true);
    expect(controller.feeTreatment, AssetFeeTreatment.none);
    expect(controller.feeController.text, '100.000');
    expect(controller.canSave, isFalse);

    controller.setFeeTreatment(AssetFeeTreatment.deductFromSaleProceeds);
    controller.setSellAsset(false);
    expect(controller.feeTreatment, AssetFeeTreatment.none);
  });

  test('sell fee equal to gross proceeds is rejected', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);

    controller.setSellAsset(true);
    controller.cashController.text = '40.000';
    controller.quantityController.text = '1';
    controller.feeController.text = '40.000';

    expect(controller.canSave, isFalse);
    expect(
      controller.feeValidationMessage,
      contains('less than the gross sale amount'),
    );
    expect(controller.buildTransaction, throwsStateError);
    expect(controller.feeController.text, '40.000');
  });

  test('foreign currency accepts two decimals and rejects a third', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);

    controller.cashController.text = '16.204.050';
    controller.quantityController.text = '1000.25';
    expect(controller.quantityValidation.isValid, isTrue);
    expect(controller.canSave, isTrue);

    controller.quantityController.text = '1000.257';
    expect(controller.canSave, isFalse);
    expect(
      controller.quantityValidationMessage,
      'USD supports up to 2 decimal places.',
    );
    expect(controller.quantityController.text, '1000.257');
  });

  test('stock enforces definition lot size and whole shares', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_bbcaDefinition()],
    );
    addTearDown(controller.dispose);

    controller.quantityController.text = '100';
    expect(controller.canSave, isTrue);

    controller.quantityController.text = '150';
    expect(controller.canSave, isFalse);
    expect(controller.lotValidationMessage, contains('100, 200, 300'));
    expect(controller.quantityController.text, '150');

    controller.quantityController.text = '100.5';
    expect(controller.canSave, isFalse);
    expect(
      controller.quantityValidationMessage,
      'Stock quantity must be entered as whole shares.',
    );
  });

  test('lot size one accepts whole shares without lot restriction', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_appleDefinition().copyWith(currencyCode: 'IDR')],
    );
    addTearDown(controller.dispose);

    controller.quantityController.text = '17';
    expect(controller.canSave, isTrue);
    expect(controller.lotValidationMessage, isNull);
  });

  test('stock sale allows date-specific odd-lot cleanup', () {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_bbcaDefinition()],
      existingTransactionsProvider: () => [
        _stockTrade(
          id: 'early-buy',
          date: DateTime(2026, 7, 1),
          quantity: 250,
          action: AssetAction.buy,
        ),
        _stockTrade(
          id: 'future-buy',
          date: DateTime(2026, 7, 10),
          quantity: 250,
          action: AssetAction.buy,
        ),
      ],
    );
    addTearDown(controller.dispose);

    controller.setSellAsset(true);
    controller.setDate(DateTime(2026, 7, 5));
    controller.quantityController.text = '50';

    expect(controller.availableQuantity, 250);
    expect(controller.lotValidation!.isOddLotCleanup, isTrue);
    expect(controller.lotValidation!.remainingShares, 200);
    expect(controller.canSave, isTrue);
  });
}

Transaction _stockTrade({
  required String id,
  required DateTime date,
  required double quantity,
  required AssetAction action,
}) => Transaction(
  id: id,
  title: 'BBCA trade',
  category: 'Asset conversion',
  account: action == AssetAction.buy
      ? 'Cash Enos -> Bank Central Asia'
      : 'Bank Central Asia -> Cash Enos',
  date: date,
  amount: (quantity * 10000).round(),
  type: TransactionType.assetConversion,
  quantity: quantity,
  unit: 'share',
  unitPrice: 10000,
  assetDefinitionId: 'asset-bbca',
  assetName: 'Bank Central Asia',
  assetSymbol: 'BBCA',
  assetAction: action,
  createdAt: date,
  updatedAt: date,
);

Transaction _usdPurchase(double quantity) {
  final date = DateTime(2026, 7, 1);
  return Transaction(
    id: 'usd-buy',
    title: 'USD acquisition',
    category: 'Asset conversion',
    account: 'Cash Enos -> US Dollar Cash',
    date: date,
    amount: (quantity * 16200).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: 'usd',
    unitPrice: 16200,
    assetDefinitionId: 'asset-usd',
    assetName: 'US Dollar Cash',
    assetSymbol: 'USD',
    assetAction: AssetAction.buy,
    createdAt: date,
    updatedAt: date,
  );
}

AssetDefinition _goldDefinition() {
  return AssetDefinition(
    id: 'asset-gold',
    displayName: 'Gold Holdings',
    kind: AssetKind.gold,
    symbol: null,
    providerCode: 'alpha_vantage',
    providerSymbol: 'XAU',
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: 'gram',
    lotSize: 1,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21),
    updatedAt: DateTime.utc(2026, 7, 21),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
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

AssetDefinition _appleDefinition() {
  return AssetDefinition(
    id: 'asset-aapl',
    displayName: 'Apple',
    kind: AssetKind.stock,
    symbol: 'AAPL',
    providerCode: 'alpha_vantage',
    providerSymbol: 'AAPL',
    exchangeCode: 'NASDAQ',
    currencyCode: 'USD',
    unit: 'share',
    lotSize: 1,
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
