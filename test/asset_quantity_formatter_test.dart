import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/presentation/formatters/asset_quantity_formatter.dart';

void main() {
  test('formats and groups stock as whole shares', () {
    expect(
      AssetQuantityFormatter.withUnit(
        quantity: 1000,
        kind: AssetKind.stock,
        unit: 'share',
      ),
      '1,000 shares',
    );
  });

  test('formats USD and SGD while trimming unnecessary zeroes', () {
    expect(_currency(1000, 'USD'), 'USD 1,000');
    expect(_currency(1000.5, 'USD'), 'USD 1,000.50');
    expect(_currency(250.75, 'SGD'), 'SGD 250.75');
  });

  test('formats gold, crypto, and inventory at policy precision', () {
    expect(
      AssetQuantityFormatter.withUnit(
        quantity: 10.1234,
        kind: AssetKind.gold,
        unit: 'gram',
      ),
      '10.1234 g',
    );
    expect(
      AssetQuantityFormatter.withUnit(
        quantity: 0.12345678,
        kind: AssetKind.crypto,
        unit: 'btc',
        symbol: 'BTC',
      ),
      'BTC 0.12345678',
    );
    expect(
      AssetQuantityFormatter.withUnit(
        quantity: 10.125,
        kind: AssetKind.inventory,
        unit: 'unit',
      ),
      '10.125 units',
    );
  });

  test('historical over-precision quantities remain displayable', () {
    expect(AssetQuantityFormatter.number(1.23456, AssetKind.gold), '1.23456');
    expect(AssetQuantityFormatter.number(100.5, AssetKind.stock), '100.5');
  });

  test('derives whole and fractional stock lots from shares', () {
    expect(
      AssetQuantityFormatter.stockWithLots(shares: 1000, lotSize: 100),
      '1,000 shares · 10 lots',
    );
    expect(
      AssetQuantityFormatter.stockWithLots(shares: 250, lotSize: 100),
      '250 shares · 2.5 lots',
    );
    expect(
      AssetQuantityFormatter.stockWithLots(shares: 17, lotSize: 1),
      '17 shares',
    );
  });
}

String _currency(double quantity, String symbol) {
  return AssetQuantityFormatter.withUnit(
    quantity: quantity,
    kind: AssetKind.foreignCurrency,
    unit: symbol.toLowerCase(),
    symbol: symbol,
  );
}
