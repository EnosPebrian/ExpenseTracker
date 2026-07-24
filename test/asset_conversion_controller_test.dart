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

    expect(controller.cashLabel, 'IDR received');
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
