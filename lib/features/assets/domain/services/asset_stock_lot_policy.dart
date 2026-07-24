import '../../../transactions/domain/entities/transaction.dart';
import '../entities/asset_definition.dart';
import '../entities/asset_kind.dart';
import 'asset_numeric_policy.dart';

class AssetStockLotValidationResult {
  const AssetStockLotValidationResult({
    required this.isValid,
    required this.lotSize,
    required this.requestedShares,
    required this.requestedLots,
    required this.availableShares,
    required this.remainingShares,
    required this.isOddLotCleanup,
    required this.oddLotShares,
    this.message,
  });

  final bool isValid;
  final int lotSize;
  final double requestedShares;
  final double requestedLots;
  final double availableShares;
  final double remainingShares;
  final bool isOddLotCleanup;
  final double oddLotShares;
  final String? message;

  bool get hasOddLotHolding => oddLotShares > 0;
}

/// Definition-driven stock lot validation for new and edited trades.
///
/// Quantities remain shares. Lot counts and odd-lot status are always derived.
class AssetStockLotPolicy {
  const AssetStockLotPolicy();

  AssetStockLotValidationResult evaluate({
    required AssetDefinition definition,
    required AssetAction action,
    required double requestedShares,
    required double availableShares,
  }) {
    if (definition.kind != AssetKind.stock) {
      return _result(
        isValid: true,
        action: action,
        lotSize: definition.lotSize,
        requestedShares: requestedShares,
        availableShares: availableShares,
      );
    }

    final lotSize = definition.lotSize;
    if (lotSize < 1) {
      return _result(
        isValid: false,
        action: action,
        lotSize: lotSize,
        requestedShares: requestedShares,
        availableShares: availableShares,
        message: '${_label(definition)} has an invalid lot size.',
      );
    }

    final quantityValidation = AssetNumericPolicy.validateQuantity(
      quantity: requestedShares,
      kind: AssetKind.stock,
      symbol: definition.normalizedSymbol,
    );
    if (!quantityValidation.isValid) {
      return _result(
        isValid: false,
        action: action,
        lotSize: lotSize,
        requestedShares: requestedShares,
        availableShares: availableShares,
        message: quantityValidation.message,
      );
    }

    if (lotSize == 1) {
      return _result(
        isValid: true,
        action: action,
        lotSize: lotSize,
        requestedShares: requestedShares,
        availableShares: availableShares,
      );
    }

    final normalizedAvailable = AssetNumericPolicy.normalizeQuantity(
      availableShares,
      AssetKind.stock,
    );
    final remaining = AssetNumericPolicy.normalizeQuantity(
      normalizedAvailable - requestedShares,
      AssetKind.stock,
    );
    final requestedIsWholeLot = _isWholeLot(requestedShares, lotSize);
    final availableIsOddLot = !_isWholeLot(normalizedAvailable, lotSize);
    final remainingIsWholeLot = _isWholeLot(remaining, lotSize);
    final withinAvailability = remaining >= 0;

    final isCleanup =
        action == AssetAction.sell &&
        availableIsOddLot &&
        !requestedIsWholeLot &&
        withinAvailability &&
        remainingIsWholeLot;

    final isValid = action == AssetAction.buy
        ? requestedIsWholeLot
        : requestedIsWholeLot || isCleanup;

    return _result(
      isValid: isValid,
      action: action,
      lotSize: lotSize,
      requestedShares: requestedShares,
      availableShares: normalizedAvailable,
      isOddLotCleanup: isCleanup,
      oddLotShares: _oddLotShares(normalizedAvailable, lotSize),
      message: isValid ? null : _multipleMessage(definition, lotSize),
    );
  }

  static AssetStockLotValidationResult _result({
    required bool isValid,
    required AssetAction action,
    required int lotSize,
    required double requestedShares,
    required double availableShares,
    bool isOddLotCleanup = false,
    double? oddLotShares,
    String? message,
  }) {
    final safeLotSize = lotSize > 0 ? lotSize : 1;
    final remaining = AssetNumericPolicy.normalizeQuantity(
      action == AssetAction.buy
          ? availableShares + requestedShares
          : availableShares - requestedShares,
      AssetKind.stock,
    );
    return AssetStockLotValidationResult(
      isValid: isValid,
      lotSize: lotSize,
      requestedShares: requestedShares,
      requestedLots: requestedShares / safeLotSize,
      availableShares: availableShares,
      remainingShares: remaining,
      isOddLotCleanup: isOddLotCleanup,
      oddLotShares: oddLotShares ?? _oddLotShares(availableShares, safeLotSize),
      message: message,
    );
  }

  static bool _isWholeLot(double shares, int lotSize) {
    if (!shares.isFinite || lotSize < 1) {
      return false;
    }
    final normalized = AssetNumericPolicy.normalizeQuantity(
      shares,
      AssetKind.stock,
    );
    if (normalized < 0 || normalized != normalized.roundToDouble()) {
      return false;
    }
    return normalized.toInt() % lotSize == 0;
  }

  static double _oddLotShares(double shares, int lotSize) {
    if (!shares.isFinite || shares <= 0 || lotSize < 1) {
      return 0;
    }
    final normalized = AssetNumericPolicy.normalizeQuantity(
      shares,
      AssetKind.stock,
    );
    if (normalized != normalized.roundToDouble()) {
      return normalized;
    }
    return (normalized.toInt() % lotSize).toDouble();
  }

  static String _multipleMessage(AssetDefinition definition, int lotSize) {
    final label = _label(definition);
    return '$label trades in lots of $lotSize shares. '
        'Enter $lotSize, ${lotSize * 2}, ${lotSize * 3}, and so on.';
  }

  static String _label(AssetDefinition definition) {
    return definition.normalizedSymbol ?? definition.displayName.trim();
  }
}
