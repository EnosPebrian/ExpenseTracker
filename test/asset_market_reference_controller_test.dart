import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_conversion_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';

void main() {
  test('no execution reference remains a valid asset transaction', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    final transaction = controller.buildTransaction();
    expect(transaction.marketReferenceUnitPrice, isNull);
    expect(transaction.marketReferenceSource, isNull);
  });

  test('manual reference is saved as an IDR per-unit snapshot', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    controller.useManualMarketReference();
    controller.referencePriceController.text = '16.250';
    final transaction = controller.buildTransaction();

    expect(transaction.marketReferenceUnitPrice, 16250);
    expect(transaction.marketReferenceCurrencyCode, 'IDR');
    expect(transaction.marketReferenceUnit, 'usd');
    expect(
      transaction.marketReferenceSource,
      AssetMarketReferenceSource.manual,
    );
    expect(transaction.marketReferenceQuotedAt, isNotNull);
  });

  test(
    'explicit compatible cached quote is copied as an immutable snapshot',
    () {
      final quotedAt = DateTime.utc(2026, 7, 24, 8);
      final controller = _controller(
        prices: [_price(assetKey: 'USD', unit: 'usd', quotedAt: quotedAt)],
      );
      addTearDown(controller.dispose);

      expect(controller.useLatestCachedMarketReference(), isTrue);
      final transaction = controller.buildTransaction();
      expect(transaction.marketReferenceUnitPrice, 16250);
      expect(
        transaction.marketReferenceSource,
        AssetMarketReferenceSource.cachedQuote,
      );
      expect(transaction.marketReferenceQuotedAt, quotedAt);
    },
  );

  test('mismatched cached quotes are unavailable and never attached', () {
    final controller = _controller(
      prices: [
        _price(assetKey: 'SGD', unit: 'sgd'),
        _price(assetKey: 'USD', unit: 'usd', currency: 'USD'),
      ],
    );
    addTearDown(controller.dispose);

    expect(controller.latestCompatibleMarketPrice, isNull);
    expect(controller.useLatestCachedMarketReference(), isFalse);
    expect(controller.buildTransaction().marketReferenceSource, isNull);
  });

  test('invalid manual input blocks only the reference and preserves text', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    controller.useManualMarketReference();
    controller.referencePriceController.text = '0';

    expect(controller.canSave, isFalse);
    expect(
      controller.marketReferenceValidationMessage,
      contains('greater than zero'),
    );
    expect(controller.referencePriceController.text, '0');
    expect(controller.buildTransaction, throwsStateError);
    expect(controller.referencePriceController.text, '0');
  });

  test(
    'changing asset rejects a cached reference selected for another asset',
    () {
      final controller = _controller(
        assets: [_usd, _sgd],
        prices: [_price(assetKey: 'USD', unit: 'usd')],
      );
      addTearDown(controller.dispose);

      expect(controller.useLatestCachedMarketReference(), isTrue);
      controller.setDestination('Singapore Dollar Cash (SGD)');
      expect(
        controller.marketReferenceValidationMessage,
        contains('does not match'),
      );
      expect(controller.canSave, isFalse);
    },
  );
}

AssetConversionController _controller({
  List<AssetDefinition>? assets,
  List<AssetMarketPrice> prices = const [],
}) {
  final controller = AssetConversionController(
    accounts: const ['Cash'],
    assets: assets ?? [_usd],
    marketPrices: prices,
  );
  controller.cashController.text = '16.300.000';
  controller.quantityController.text = '1000';
  return controller;
}

AssetMarketPrice _price({
  required String assetKey,
  required String unit,
  String currency = 'IDR',
  DateTime? quotedAt,
}) => AssetMarketPrice.manual(
  assetKey: assetKey,
  symbol: assetKey,
  price: 16250,
  currencyCode: currency,
  unit: unit,
  quotedAt: quotedAt,
);

final _usd = _definition('asset-usd', 'US Dollar Cash', 'USD', 'usd');
final _sgd = _definition('asset-sgd', 'Singapore Dollar Cash', 'SGD', 'sgd');

AssetDefinition _definition(
  String id,
  String name,
  String symbol,
  String unit,
) => AssetDefinition(
  id: id,
  displayName: name,
  kind: AssetKind.foreignCurrency,
  symbol: symbol,
  providerCode: 'alpha_vantage',
  providerSymbol: '$symbol/IDR',
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: unit,
  lotSize: 1,
  onlinePricingEnabled: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);
