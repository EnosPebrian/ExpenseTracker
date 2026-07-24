import '../entities/asset_definition.dart';
import '../entities/asset_kind.dart';

enum AssetDefinitionIntegrityField {
  general,
  displayName,
  symbol,
  exchangeCode,
  currencyCode,
  unit,
  lotSize,
  providerCode,
  providerSymbol,
}

enum AssetDefinitionIntegrityCode {
  required,
  invalidFormat,
  stockIdentityConflict,
  marketPriceIdentityConflict,
  providerIdentityConflict,
  foreignCurrencyMismatch,
}

class AssetDefinitionIntegrityIssue {
  const AssetDefinitionIntegrityIssue({
    required this.field,
    required this.code,
    required this.message,
    this.conflictingDefinitionId,
    this.conflictingDefinitionName,
  });

  final AssetDefinitionIntegrityField field;
  final AssetDefinitionIntegrityCode code;
  final String message;
  final String? conflictingDefinitionId;
  final String? conflictingDefinitionName;
}

class AssetDefinitionIntegrityResult {
  const AssetDefinitionIntegrityResult(this.issues);

  final List<AssetDefinitionIntegrityIssue> issues;

  bool get isValid => issues.isEmpty;
  AssetDefinitionIntegrityIssue? get firstIssue => issues.firstOrNull;

  String? errorFor(AssetDefinitionIntegrityField field) {
    for (final issue in issues) {
      if (issue.field == field) return issue.message;
    }
    return null;
  }
}

class AssetDefinitionIntegrityPolicy {
  const AssetDefinitionIntegrityPolicy();

  AssetDefinitionIntegrityResult validate({
    required AssetDefinition candidate,
    required Iterable<AssetDefinition> existingDefinitions,
    String? editingDefinitionId,
  }) {
    final issues = <AssetDefinitionIntegrityIssue>[];
    _validateStructure(candidate, issues);

    for (final existing in existingDefinitions) {
      if (existing.id == editingDefinitionId) continue;
      _validateStockIdentity(candidate, existing, issues);
      _validateMarketPriceIdentity(candidate, existing, issues);
      _validateProviderIdentity(candidate, existing, issues);
    }

    return AssetDefinitionIntegrityResult(List.unmodifiable(issues));
  }

  void _validateStructure(
    AssetDefinition candidate,
    List<AssetDefinitionIntegrityIssue> issues,
  ) {
    if (candidate.displayName.trim().isEmpty) {
      _add(
        issues,
        AssetDefinitionIntegrityField.displayName,
        AssetDefinitionIntegrityCode.required,
        'Display name is required.',
      );
    }
    if (candidate.normalizedCurrencyCode.length != 3) {
      _add(
        issues,
        AssetDefinitionIntegrityField.currencyCode,
        AssetDefinitionIntegrityCode.invalidFormat,
        'Use a three-letter currency code.',
      );
    }
    if (candidate.normalizedUnit.isEmpty) {
      _add(
        issues,
        AssetDefinitionIntegrityField.unit,
        AssetDefinitionIntegrityCode.required,
        'Unit is required.',
      );
    }
    if (candidate.lotSize <= 0) {
      _add(
        issues,
        AssetDefinitionIntegrityField.lotSize,
        AssetDefinitionIntegrityCode.invalidFormat,
        'Lot size must be greater than zero.',
      );
    }
    if (candidate.kind == AssetKind.stock &&
        candidate.normalizedSymbol == null) {
      _add(
        issues,
        AssetDefinitionIntegrityField.symbol,
        AssetDefinitionIntegrityCode.required,
        'A stock symbol is required.',
      );
    }

    if (candidate.kind == AssetKind.foreignCurrency) {
      _validateForeignCurrency(candidate, issues);
    }

    if (candidate.onlinePricingEnabled) {
      if (candidate.normalizedProviderCode == null) {
        _add(
          issues,
          AssetDefinitionIntegrityField.providerCode,
          AssetDefinitionIntegrityCode.required,
          'A provider is required when online pricing is enabled.',
        );
      }
      if (candidate.normalizedProviderSymbol == null) {
        _add(
          issues,
          AssetDefinitionIntegrityField.providerSymbol,
          AssetDefinitionIntegrityCode.required,
          'A provider symbol is required when online pricing is enabled.',
        );
      }
    }
  }

  void _validateForeignCurrency(
    AssetDefinition candidate,
    List<AssetDefinitionIntegrityIssue> issues,
  ) {
    final symbol = candidate.normalizedSymbol;
    if (symbol == null || !RegExp(r'^[A-Z]{3}$').hasMatch(symbol)) {
      _add(
        issues,
        AssetDefinitionIntegrityField.symbol,
        AssetDefinitionIntegrityCode.invalidFormat,
        'Use a three-letter foreign-currency symbol.',
      );
      return;
    }
    if (symbol == candidate.normalizedCurrencyCode) {
      _add(
        issues,
        AssetDefinitionIntegrityField.currencyCode,
        AssetDefinitionIntegrityCode.foreignCurrencyMismatch,
        'Source and valuation currencies must differ.',
      );
    }
    if (candidate.normalizedUnit != symbol.toLowerCase()) {
      _add(
        issues,
        AssetDefinitionIntegrityField.unit,
        AssetDefinitionIntegrityCode.foreignCurrencyMismatch,
        'Unit must match the currency symbol ${symbol.toLowerCase()}.',
      );
    }
    if (candidate.onlinePricingEnabled &&
        candidate.normalizedProviderSymbol !=
            '$symbol/${candidate.normalizedCurrencyCode}') {
      _add(
        issues,
        AssetDefinitionIntegrityField.providerSymbol,
        AssetDefinitionIntegrityCode.foreignCurrencyMismatch,
        'Provider pair must be $symbol/${candidate.normalizedCurrencyCode}.',
      );
    }
  }

  void _validateStockIdentity(
    AssetDefinition candidate,
    AssetDefinition existing,
    List<AssetDefinitionIntegrityIssue> issues,
  ) {
    if (candidate.kind != AssetKind.stock ||
        existing.kind != AssetKind.stock ||
        candidate.normalizedSymbol == null ||
        candidate.normalizedSymbol != existing.normalizedSymbol) {
      return;
    }
    final candidateExchange = candidate.normalizedExchangeCode;
    final existingExchange = existing.normalizedExchangeCode;
    if (candidateExchange != null &&
        existingExchange != null &&
        candidateExchange != existingExchange) {
      return;
    }
    final exchange = existingExchange ?? candidateExchange;
    final archived = existing.isDeleted ? 'An archived ' : '';
    final action = existing.isDeleted
        ? 'Restore or edit it instead.'
        : 'Edit the existing asset instead.';
    _addConflict(
      issues,
      AssetDefinitionIntegrityField.symbol,
      AssetDefinitionIntegrityCode.stockIdentityConflict,
      '$archived${candidate.normalizedSymbol} definition already exists'
      '${exchange == null ? '' : ' for $exchange'}. $action',
      existing,
    );
  }

  void _validateMarketPriceIdentity(
    AssetDefinition candidate,
    AssetDefinition existing,
    List<AssetDefinitionIntegrityIssue> issues,
  ) {
    if (candidate.kind == AssetKind.stock ||
        existing.kind != candidate.kind ||
        _normalize(candidate.marketPriceKey) !=
            _normalize(existing.marketPriceKey)) {
      return;
    }
    final archived = existing.isDeleted ? 'An archived ' : '';
    final action = existing.isDeleted
        ? 'Restore or edit it instead.'
        : 'Edit the existing asset instead.';
    _addConflict(
      issues,
      AssetDefinitionIntegrityField.symbol,
      AssetDefinitionIntegrityCode.marketPriceIdentityConflict,
      '$archived${candidate.marketPriceKey.trim()} definition already exists. '
      '$action',
      existing,
    );
  }

  void _validateProviderIdentity(
    AssetDefinition candidate,
    AssetDefinition existing,
    List<AssetDefinitionIntegrityIssue> issues,
  ) {
    if (!candidate.onlinePricingEnabled) return;
    final provider = candidate.normalizedProviderCode;
    final symbol = candidate.normalizedProviderSymbol;
    if (provider == null ||
        symbol == null ||
        provider != existing.normalizedProviderCode ||
        symbol != existing.normalizedProviderSymbol) {
      return;
    }
    final archived = existing.isDeleted ? 'Archived asset ' : '';
    final action = existing.isDeleted
        ? 'Restore or edit it instead.'
        : 'Use a different provider symbol.';
    _addConflict(
      issues,
      AssetDefinitionIntegrityField.providerSymbol,
      AssetDefinitionIntegrityCode.providerIdentityConflict,
      '$archived$symbol is already used by ${existing.displayName.trim()}. '
      '$action',
      existing,
    );
  }

  static String _normalize(String value) => value.trim().toUpperCase();

  static void _add(
    List<AssetDefinitionIntegrityIssue> issues,
    AssetDefinitionIntegrityField field,
    AssetDefinitionIntegrityCode code,
    String message,
  ) {
    if (issues.any((issue) => issue.field == field && issue.code == code)) {
      return;
    }
    issues.add(
      AssetDefinitionIntegrityIssue(field: field, code: code, message: message),
    );
  }

  static void _addConflict(
    List<AssetDefinitionIntegrityIssue> issues,
    AssetDefinitionIntegrityField field,
    AssetDefinitionIntegrityCode code,
    String message,
    AssetDefinition existing,
  ) {
    if (issues.any((issue) => issue.field == field && issue.code == code)) {
      return;
    }
    issues.add(
      AssetDefinitionIntegrityIssue(
        field: field,
        code: code,
        message: message,
        conflictingDefinitionId: existing.id,
        conflictingDefinitionName: existing.displayName,
      ),
    );
  }
}
