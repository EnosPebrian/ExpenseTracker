import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';

void main() {
  group('AssetDefinition', () {
    test('SQLite record mapping preserves all fields', () {
      final definition = _stockDefinition();

      final restored = AssetDefinition.fromRecord(definition.toRecord());

      expect(restored.id, definition.id);
      expect(restored.displayName, 'Bank Central Asia');
      expect(restored.kind, AssetKind.stock);
      expect(restored.symbol, 'BBCA');
      expect(restored.providerCode, 'ALPHA_VANTAGE');
      expect(restored.providerSymbol, 'BBCA');
      expect(restored.exchangeCode, 'IDX');
      expect(restored.currencyCode, 'IDR');
      expect(restored.unit, 'share');
      expect(restored.lotSize, 100);
      expect(restored.onlinePricingEnabled, isTrue);
      expect(restored.createdAt, definition.createdAt);
      expect(restored.updatedAt, definition.updatedAt);
      expect(restored.deletedAt, isNull);
      expect(restored.version, 1);
      expect(restored.deviceId, 'test-device');
      expect(restored.syncStatus, 'local_only');
    });

    test('copyWith can explicitly clear nullable fields', () {
      final definition = _stockDefinition();

      final updated = definition.copyWith(
        providerCode: null,
        providerSymbol: null,
        exchangeCode: null,
        deletedAt: DateTime.utc(2026, 7, 22),
      );

      expect(updated.providerCode, isNull);
      expect(updated.providerSymbol, isNull);
      expect(updated.exchangeCode, isNull);
      expect(updated.deletedAt, DateTime.utc(2026, 7, 22));

      final restored = updated.copyWith(deletedAt: null);

      expect(restored.deletedAt, isNull);
    });

    test('stock validation requires a stock symbol', () {
      final definition = _stockDefinition().copyWith(symbol: null);

      expect(definition.validate(), contains('A stock symbol is required.'));
    });

    test('online pricing requires a provider symbol for non-gold assets', () {
      final definition = _stockDefinition().copyWith(providerSymbol: null);

      expect(
        definition.validate(),
        contains(
          'A provider symbol is required when online pricing is enabled.',
        ),
      );
    });

    test('market and quote keys use normalized asset identity', () {
      final stock = _stockDefinition().copyWith(
        symbol: ' bbca ',
        providerSymbol: ' bbca.jk ',
      );

      expect(stock.marketPriceKey, 'BBCA');
      expect(stock.quoteSymbol, 'BBCA.JK');

      final gold = _goldDefinition();

      expect(gold.marketPriceKey, 'Gold Holdings');
      expect(gold.quoteSymbol, 'XAU');
    });

    test('invalid lot size and currency are reported', () {
      final definition = _stockDefinition().copyWith(
        currencyCode: 'ID',
        lotSize: 0,
      );

      final errors = definition.validate();

      expect(
        errors,
        contains('Currency code must contain exactly three characters.'),
      );

      expect(errors, contains('Lot size must be greater than zero.'));
    });
  });
}

AssetDefinition _stockDefinition() {
  return AssetDefinition(
    id: 'asset-bbca',
    displayName: 'Bank Central Asia',
    kind: AssetKind.stock,
    symbol: 'BBCA',
    providerCode: 'alpha_vantage',
    providerSymbol: 'BBCA',
    exchangeCode: 'IDX',
    currencyCode: 'idr',
    unit: 'SHARE',
    lotSize: 100,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21, 10),
    updatedAt: DateTime.utc(2026, 7, 21, 11),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

AssetDefinition _goldDefinition() {
  return AssetDefinition(
    id: 'asset-gold',
    displayName: 'Gold Holdings',
    kind: AssetKind.gold,
    symbol: null,
    providerCode: 'alpha_vantage',
    providerSymbol: 'xau',
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
