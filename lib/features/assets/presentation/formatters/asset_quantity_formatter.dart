import '../../domain/entities/asset_portfolio.dart';
import '../../domain/services/asset_numeric_policy.dart';

class AssetQuantityFormatter {
  const AssetQuantityFormatter._();

  static String number(double quantity, AssetKind kind) {
    if (!quantity.isFinite) {
      return quantity.toString();
    }

    final policyDecimals = AssetNumericPolicy.quantityDecimalPlacesFor(kind);
    final isWithinCurrentPolicy = AssetNumericPolicy.validateQuantity(
      quantity: quantity,
      kind: kind,
    ).isValid;
    final decimals = isWithinCurrentPolicy ? policyDecimals : 12;
    final normalized = AssetNumericPolicy.normalizeQuantity(quantity, kind);
    final fixed = normalized.toStringAsFixed(decimals);
    final preserveCurrencyDecimals =
        kind == AssetKind.foreignCurrency &&
        normalized != normalized.roundToDouble() &&
        isWithinCurrentPolicy;
    final trimmed = preserveCurrencyDecimals || !fixed.contains('.')
        ? fixed
        : fixed
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    final parts = trimmed.split('.');
    final integer = _groupInteger(parts.first);
    return parts.length == 1 ? integer : '$integer.${parts.last}';
  }

  static String holding(AssetHolding holding) {
    final formatted = number(holding.quantity, holding.kind);
    final symbol = holding.normalizedSymbol;

    return switch (holding.kind) {
      AssetKind.stock =>
        holding.lotSize > 1
            ? stockWithLots(shares: holding.quantity, lotSize: holding.lotSize)
            : '$formatted shares',
      AssetKind.foreignCurrency =>
        '${symbol ?? holding.normalizedUnit.toUpperCase()} $formatted',
      AssetKind.gold => '$formatted g',
      AssetKind.crypto =>
        symbol == null
            ? '$formatted ${holding.normalizedUnit}'
            : '$symbol $formatted',
      AssetKind.inventory => '$formatted ${_pluralUnit(holding.unit)}',
      AssetKind.other => '$formatted ${holding.unit}',
    };
  }

  static String stockWithLots({required double shares, required int lotSize}) {
    final formattedShares = number(shares, AssetKind.stock);
    if (lotSize <= 1) return '$formattedShares shares';
    final formattedLots = number(shares / lotSize, AssetKind.other);
    return '$formattedShares shares · $formattedLots lots';
  }

  static String withUnit({
    required double quantity,
    required AssetKind kind,
    required String unit,
    String? symbol,
  }) {
    final formatted = number(quantity, kind);
    final normalizedSymbol = symbol?.trim().toUpperCase();

    return switch (kind) {
      AssetKind.stock => '$formatted shares',
      AssetKind.foreignCurrency =>
        '${normalizedSymbol?.isNotEmpty == true ? normalizedSymbol : unit.toUpperCase()} $formatted',
      AssetKind.gold => '$formatted g',
      AssetKind.crypto =>
        normalizedSymbol?.isNotEmpty == true
            ? '$normalizedSymbol $formatted'
            : '$formatted $unit',
      AssetKind.inventory => '$formatted ${_pluralUnit(unit)}',
      AssetKind.other => '$formatted $unit',
    };
  }

  static String _groupInteger(String value) {
    final negative = value.startsWith('-');
    final digits = negative ? value.substring(1) : value;
    final grouped = digits.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => ',',
    );
    return negative ? '-$grouped' : grouped;
  }

  static String _pluralUnit(String unit) {
    final normalized = unit.trim().isEmpty ? 'unit' : unit.trim();
    if (normalized.endsWith('s')) {
      return normalized;
    }
    return '${normalized}s';
  }
}
