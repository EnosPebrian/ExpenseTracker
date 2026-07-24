import 'dart:math' as math;

import '../entities/asset_kind.dart';

class AssetQuantityValidationResult {
  const AssetQuantityValidationResult.valid() : isValid = true, message = null;

  const AssetQuantityValidationResult.invalid(this.message) : isValid = false;

  final bool isValid;
  final String? message;
}

class AssetNumericPolicy {
  const AssetNumericPolicy._();

  static int quantityDecimalPlacesFor(AssetKind kind) {
    return switch (kind) {
      AssetKind.stock => 0,
      AssetKind.foreignCurrency => 2,
      AssetKind.gold => 4,
      AssetKind.crypto => 8,
      AssetKind.inventory => 3,
      AssetKind.other => 4,
    };
  }

  static AssetQuantityValidationResult validateQuantity({
    required double quantity,
    required AssetKind kind,
    String? symbol,
  }) {
    if (!quantity.isFinite) {
      return const AssetQuantityValidationResult.invalid(
        'Asset quantity must be a finite number.',
      );
    }

    if (quantity <= 0) {
      return const AssetQuantityValidationResult.invalid(
        'Enter an asset quantity greater than zero.',
      );
    }

    final decimalPlaces = quantityDecimalPlacesFor(kind);
    final scale = math.pow(10, decimalPlaces).toDouble();
    final scaled = quantity * scale;
    final isWithinPrecision =
        (scaled - scaled.roundToDouble()).abs() <= 0.000001;

    if (isWithinPrecision) {
      return const AssetQuantityValidationResult.valid();
    }

    if (kind == AssetKind.stock) {
      return const AssetQuantityValidationResult.invalid(
        'Stock quantity must be entered as whole shares.',
      );
    }

    final label = _quantityLabel(kind: kind, symbol: symbol);
    return AssetQuantityValidationResult.invalid(
      '$label supports up to $decimalPlaces decimal places.',
    );
  }

  static int deriveUnitPrice({required int amount, required double quantity}) {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Quantity must be finite and greater than zero.',
      );
    }

    return (amount / quantity).round();
  }

  static double comparisonToleranceFor(AssetKind kind) {
    final decimalPlaces = quantityDecimalPlacesFor(kind);
    return math.pow(10, -(decimalPlaces + 6)).toDouble();
  }

  static bool isEffectivelyZero(double quantity, AssetKind kind) {
    return quantity.isFinite && quantity.abs() <= comparisonToleranceFor(kind);
  }

  static double normalizeQuantity(double quantity, AssetKind kind) {
    if (!quantity.isFinite) {
      return quantity;
    }

    if (isEffectivelyZero(quantity, kind)) {
      return 0;
    }

    final decimals = quantityDecimalPlacesFor(kind);
    final scale = math.pow(10, decimals).toDouble();
    final supportedPrecisionValue = (quantity * scale).roundToDouble() / scale;

    return (quantity - supportedPrecisionValue).abs() <=
            comparisonToleranceFor(kind)
        ? supportedPrecisionValue
        : quantity;
  }

  static AssetKind inferKind({
    required String? unit,
    String? symbol,
    String? assetName,
  }) {
    final normalizedUnit = unit?.trim().toLowerCase() ?? '';
    final normalizedSymbol = symbol?.trim().toLowerCase() ?? '';
    final normalizedName = assetName?.trim().toLowerCase() ?? '';

    if (normalizedUnit == 'share' || normalizedUnit == 'shares') {
      return AssetKind.stock;
    }

    if (normalizedUnit == 'gram' ||
        normalizedUnit == 'g' ||
        normalizedName.contains('gold')) {
      return AssetKind.gold;
    }

    if (normalizedUnit == 'btc' ||
        normalizedUnit == 'coin' ||
        normalizedName.contains('bitcoin') ||
        normalizedName.contains('crypto')) {
      return AssetKind.crypto;
    }

    if (normalizedUnit.length == 3 &&
        normalizedUnit == normalizedSymbol &&
        RegExp(r'^[a-z]{3}$').hasMatch(normalizedUnit)) {
      return AssetKind.foreignCurrency;
    }

    if (normalizedUnit == 'item' ||
        normalizedUnit == 'items' ||
        normalizedName.contains('inventory')) {
      return AssetKind.inventory;
    }

    return AssetKind.other;
  }

  static String _quantityLabel({required AssetKind kind, String? symbol}) {
    final normalizedSymbol = symbol?.trim().toUpperCase();

    return switch (kind) {
      AssetKind.foreignCurrency =>
        normalizedSymbol?.isNotEmpty == true
            ? normalizedSymbol!
            : 'Foreign currency',
      AssetKind.gold => 'Gold',
      AssetKind.crypto =>
        normalizedSymbol?.isNotEmpty == true
            ? normalizedSymbol!
            : 'Cryptocurrency',
      AssetKind.inventory => 'Inventory',
      AssetKind.other => 'Asset',
      AssetKind.stock => 'Stock',
    };
  }
}
