import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_stock_lot_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

const policy = AssetStockLotPolicy();

void main() {
  test('non-stock assets bypass lot validation', () {
    final result = policy.evaluate(
      definition: _definition(kind: AssetKind.gold, lotSize: 100),
      action: AssetAction.buy,
      requestedShares: 1.25,
      availableShares: 0,
    );
    expect(result.isValid, isTrue);
  });

  test('invalid zero lot size is handled without throwing', () {
    final result = policy.evaluate(
      definition: _definition(lotSize: 0),
      action: AssetAction.buy,
      requestedShares: 100,
      availableShares: 0,
    );
    expect(result.isValid, isFalse);
    expect(result.message, contains('invalid lot size'));
  });

  test('lot size one accepts any positive whole shares', () {
    for (final shares in [1.0, 17.0]) {
      expect(
        policy
            .evaluate(
              definition: _definition(symbol: 'AAPL', lotSize: 1),
              action: AssetAction.buy,
              requestedShares: shares,
              availableShares: 0,
            )
            .isValid,
        isTrue,
      );
    }
  });

  test('normal buy requires a whole lot multiple', () {
    expect(_buy(100).isValid, isTrue);
    expect(_buy(100).remainingShares, 100);
    expect(_buy(500).isValid, isTrue);
    expect(_buy(150).isValid, isFalse);
    expect(_buy(50).message, contains('100, 200, 300'));
  });

  test('normal sale requires a whole lot multiple', () {
    expect(_sell(100, available: 500).isValid, isTrue);
    expect(_sell(300, available: 500).isValid, isTrue);
    expect(_sell(150, available: 500).isValid, isFalse);
  });

  test('historical odd-lot position supports all cleanup forms', () {
    expect(_sell(100, available: 250).isValid, isTrue);
    expect(_sell(200, available: 250).isValid, isTrue);

    final residue = _sell(50, available: 250);
    expect(residue.isValid, isTrue);
    expect(residue.isOddLotCleanup, isTrue);
    expect(residue.remainingShares, 200);
    expect(residue.oddLotShares, 50);

    expect(_sell(150, available: 250).isValid, isTrue);
    expect(_sell(250, available: 250).isValid, isTrue);
    expect(_sell(250, available: 250).remainingShares, 0);
  });

  test('sale that leaves another odd residue is blocked', () {
    for (final shares in [25.0, 75.0, 125.0]) {
      expect(_sell(shares, available: 250).isValid, isFalse);
    }
  });

  test('clean whole-lot holding cannot create odd residue', () {
    final result = _sell(150, available: 500);
    expect(result.isValid, isFalse);
    expect(result.remainingShares, 350);
  });

  test('stock whole-share precision remains enforced', () {
    final result = _buy(100.5);
    expect(result.isValid, isFalse);
    expect(result.message, 'Stock quantity must be entered as whole shares.');
  });
}

AssetStockLotValidationResult _buy(double shares) => policy.evaluate(
  definition: _definition(),
  action: AssetAction.buy,
  requestedShares: shares,
  availableShares: 0,
);

AssetStockLotValidationResult _sell(
  double shares, {
  required double available,
}) => policy.evaluate(
  definition: _definition(),
  action: AssetAction.sell,
  requestedShares: shares,
  availableShares: available,
);

AssetDefinition _definition({
  AssetKind kind = AssetKind.stock,
  String symbol = 'BBCA',
  int lotSize = 100,
}) => AssetDefinition(
  id: 'asset-${symbol.toLowerCase()}',
  displayName: symbol,
  kind: kind,
  symbol: kind == AssetKind.stock ? symbol : null,
  providerCode: null,
  providerSymbol: null,
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: kind == AssetKind.stock ? 'share' : 'gram',
  lotSize: lotSize,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);
