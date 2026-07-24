import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_numeric_policy.dart';

void main() {
  test('returns centralized precision for every asset kind', () {
    expect(AssetNumericPolicy.quantityDecimalPlacesFor(AssetKind.stock), 0);
    expect(
      AssetNumericPolicy.quantityDecimalPlacesFor(AssetKind.foreignCurrency),
      2,
    );
    expect(AssetNumericPolicy.quantityDecimalPlacesFor(AssetKind.gold), 4);
    expect(AssetNumericPolicy.quantityDecimalPlacesFor(AssetKind.crypto), 8);
    expect(AssetNumericPolicy.quantityDecimalPlacesFor(AssetKind.inventory), 3);
    expect(AssetNumericPolicy.quantityDecimalPlacesFor(AssetKind.other), 4);
  });

  test('accepts precision boundaries for every asset kind', () {
    expect(_valid(100.0, AssetKind.stock), isTrue);
    expect(_valid(1000.25, AssetKind.foreignCurrency), isTrue);
    expect(_valid(1.2345, AssetKind.gold), isTrue);
    expect(_valid(0.12345678, AssetKind.crypto), isTrue);
    expect(_valid(10.125, AssetKind.inventory), isTrue);
    expect(_valid(10.1234, AssetKind.other), isTrue);
  });

  test('rejects one decimal beyond every asset-kind policy', () {
    expect(_valid(100.5, AssetKind.stock), isFalse);
    expect(_valid(1000.257, AssetKind.foreignCurrency), isFalse);
    expect(_valid(1.23456, AssetKind.gold), isFalse);
    expect(_valid(0.123456789, AssetKind.crypto), isFalse);
    expect(_valid(10.1255, AssetKind.inventory), isFalse);
    expect(_valid(10.12345, AssetKind.other), isFalse);
  });

  test('rejects non-positive and non-finite quantities', () {
    for (final quantity in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(_valid(quantity, AssetKind.gold), isFalse);
    }
  });

  test(
    'stock accepts whole-valued doubles and explains fractional rejection',
    () {
      expect(_valid(100.0, AssetKind.stock), isTrue);
      final result = AssetNumericPolicy.validateQuantity(
        quantity: 100.5,
        kind: AssetKind.stock,
      );
      expect(result.isValid, isFalse);
      expect(result.message, 'Stock quantity must be entered as whole shares.');
    },
  );

  test('derived unit price uses deterministic positive half rounding', () {
    expect(AssetNumericPolicy.deriveUnitPrice(amount: 5, quantity: 2), 3);
    expect(AssetNumericPolicy.deriveUnitPrice(amount: 10, quantity: 4), 3);
    expect(AssetNumericPolicy.deriveUnitPrice(amount: 10, quantity: 5), 2);
    expect(
      () =>
          AssetNumericPolicy.deriveUnitPrice(amount: 10, quantity: double.nan),
      throwsArgumentError,
    );
  });

  test('normalizes near zero without hiding material negatives', () {
    expect(
      AssetNumericPolicy.normalizeQuantity(
        0.000000001,
        AssetKind.foreignCurrency,
      ),
      0,
    );
    expect(
      AssetNumericPolicy.normalizeQuantity(
        -0.000000001,
        AssetKind.foreignCurrency,
      ),
      0,
    );
    expect(
      AssetNumericPolicy.normalizeQuantity(-0.001, AssetKind.foreignCurrency),
      -0.001,
    );
    expect(
      AssetNumericPolicy.normalizeQuantity(
        600.0000000001,
        AssetKind.foreignCurrency,
      ),
      600,
    );
  });
}

bool _valid(double quantity, AssetKind kind) {
  return AssetNumericPolicy.validateQuantity(
    quantity: quantity,
    kind: kind,
    symbol: kind == AssetKind.foreignCurrency ? 'USD' : null,
  ).isValid;
}
