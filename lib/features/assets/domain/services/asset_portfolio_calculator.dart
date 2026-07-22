import 'dart:math' as math;

import '../../../transactions/domain/entities/transaction.dart';
import '../entities/asset_market_price.dart';
import '../entities/asset_portfolio.dart';
import '../entities/asset_definition.dart';

class AssetPortfolioCalculator {
  const AssetPortfolioCalculator._();

  static AssetPortfolio calculate({
    required Iterable<Transaction> transactions,
    Iterable<AssetMarketPrice> marketPrices = const [],
    Iterable<AssetDefinition> assetDefinitions = const [],
  }) {
    final definitionById = <String, AssetDefinition>{};

    for (final definition in assetDefinitions) {
      final id = definition.id.trim();

      if (id.isNotEmpty) {
        definitionById[id] = definition;
      }
    }
    final priceByKey = <String, AssetMarketPrice>{};

    for (final price in marketPrices) {
      priceByKey[_normalizeKey(price.assetKey)] = price;

      final symbol = price.symbol?.trim();

      if (symbol != null && symbol.isNotEmpty) {
        priceByKey[_normalizeKey(symbol)] = price;
      }
    }

    final conversions =
        transactions
            .where((transaction) {
              return transaction.deletedAt == null &&
                  transaction.type == TransactionType.assetConversion &&
                  (transaction.quantity ?? 0) > 0;
            })
            .toList(growable: false)
          ..sort(_compareTransactions);

    final states = <String, _HoldingState>{};

    for (final transaction in conversions) {
      final action = _resolveAction(transaction);
      final definition = _findDefinition(
        transaction: transaction,
        definitionById: definitionById,
      );

      final snapshotName = _resolveAssetName(transaction, action);

      final assetName = definition?.displayName.trim() ?? snapshotName;

      if (assetName.isEmpty) {
        continue;
      }

      final symbol =
          definition?.normalizedSymbol ??
          _normalizedSymbol(transaction.assetSymbol);

      final assetKey = symbol ?? assetName;

      final groupingKey = definition == null
          ? 'legacy:${_normalizeKey(assetKey)}'
          : 'definition:${_normalizeKey(definition.id)}';

      final quantity = transaction.quantity ?? 0;

      if (quantity <= 0) {
        continue;
      }

      final unit =
          definition?.normalizedUnit ?? _resolvedUnit(transaction.unit);

      final kind =
          definition?.kind ??
          _resolveKind(unit: unit, assetName: assetName, symbol: symbol);

      final lotSize =
          definition?.lotSize ?? (kind == AssetKind.stock ? 100 : 1);

      final state = states.putIfAbsent(
        groupingKey,
        () => _HoldingState(
          assetDefinitionId: definition?.id,
          providerCode: definition?.normalizedProviderCode,
          providerSymbol: definition?.normalizedProviderSymbol,
          currencyCode: definition?.normalizedCurrencyCode ?? 'IDR',
          onlinePricingEnabled: definition?.onlinePricingEnabled ?? true,
          assetKey: assetKey,
          name: assetName,
          symbol: symbol,
          kind: kind,
          unit: unit,
          lotSize: lotSize,
        ),
      );

      final unitPrice = transaction.unitPrice;

      if (unitPrice != null && unitPrice > 0) {
        state.latestTransactionPrice = unitPrice;
      }

      switch (action) {
        case AssetAction.buy:
          state.quantity += quantity;
          state.costBasis += transaction.amount;

        case AssetAction.sell:
          if (state.quantity <= 0 || state.costBasis <= 0) {
            continue;
          }

          final matchedQuantity = math.min(quantity, state.quantity);
          final averageCostBeforeSale = state.costBasis / state.quantity;
          final removedCost = averageCostBeforeSale * matchedQuantity;

          final proceedsPerUnit = transaction.amount / quantity;
          final matchedProceeds = proceedsPerUnit * matchedQuantity;

          state.quantity -= matchedQuantity;
          state.costBasis -= removedCost;
          state.realizedGain += matchedProceeds - removedCost;

          if (state.quantity.abs() < 0.0000001) {
            state.quantity = 0;
            state.costBasis = 0;
          }
      }
    }

    final holdings = <AssetHolding>[];

    for (final state in states.values) {
      if (state.quantity <= 0) {
        continue;
      }

      final marketPrice = _findPrice(state: state, priceByKey: priceByKey);

      final currentPrice = marketPrice?.roundedPrice;

      final roundedCostBasis = state.costBasis.round();
      final marketValue = currentPrice == null
          ? roundedCostBasis
          : (state.quantity * currentPrice).round();

      holdings.add(
        AssetHolding(
          assetDefinitionId: state.assetDefinitionId,
          providerCode: state.providerCode,
          providerSymbol: state.providerSymbol,
          currencyCode: state.currencyCode,
          onlinePricingEnabled: state.onlinePricingEnabled,
          assetKey: state.assetKey,
          name: state.name,
          symbol: state.symbol,
          kind: state.kind,
          unit: state.unit,
          quantity: state.quantity,
          lotSize: state.lotSize,
          costBasis: roundedCostBasis,
          averageCost: state.quantity == 0
              ? 0
              : (state.costBasis / state.quantity).round(),
          currentPrice: currentPrice,
          marketValue: marketValue,
          realizedGain: state.realizedGain.round(),
          priceSource: marketPrice?.source,
          priceQuotedAt: marketPrice?.quotedAt,
          isPriceDelayed: marketPrice?.isDelayed ?? false,
          isManualPrice: marketPrice?.isManual ?? false,
        ),
      );
    }

    holdings.sort(
      (left, right) => right.marketValue.compareTo(left.marketValue),
    );

    final totalCostBasis = holdings.fold<int>(
      0,
      (total, holding) => total + holding.costBasis,
    );

    final totalMarketValue = holdings.fold<int>(
      0,
      (total, holding) => total + holding.marketValue,
    );

    final totalRealizedGain = states.values.fold<int>(
      0,
      (total, state) => total + state.realizedGain.round(),
    );

    return AssetPortfolio(
      holdings: List<AssetHolding>.unmodifiable(holdings),
      totalCostBasis: totalCostBasis,
      totalMarketValue: totalMarketValue,
      totalUnrealizedGain: totalMarketValue - totalCostBasis,
      totalRealizedGain: totalRealizedGain,
    );
  }

  static AssetDefinition? _findDefinition({
    required Transaction transaction,
    required Map<String, AssetDefinition> definitionById,
  }) {
    final id = transaction.assetDefinitionId?.trim();

    if (id == null || id.isEmpty) {
      return null;
    }

    return definitionById[id];
  }

  static AssetMarketPrice? _findPrice({
    required _HoldingState state,
    required Map<String, AssetMarketPrice> priceByKey,
  }) {
    final direct = priceByKey[_normalizeKey(state.assetKey)];

    if (direct != null && _isCompatiblePrice(state: state, price: direct)) {
      return direct;
    }

    final symbol = state.symbol;

    if (symbol != null) {
      final symbolPrice = priceByKey[_normalizeKey(symbol)];

      if (symbolPrice != null &&
          _isCompatiblePrice(state: state, price: symbolPrice)) {
        return symbolPrice;
      }
    }

    if (state.kind == AssetKind.gold) {
      final goldPrice = priceByKey[_normalizeKey('XAU')];

      if (goldPrice != null &&
          _isCompatiblePrice(state: state, price: goldPrice)) {
        return goldPrice;
      }
    }

    return null;
  }

  static bool _isCompatiblePrice({
    required _HoldingState state,
    required AssetMarketPrice price,
  }) {
    if (price.priceMinor <= 0 || price.minorUnitScale <= 0) {
      return false;
    }

    final expectedCurrency = state.currencyCode.trim().toUpperCase();
    final actualCurrency = price.currencyCode.trim().toUpperCase();

    if (actualCurrency != expectedCurrency) {
      return false;
    }

    final expectedUnit = state.unit.trim().toLowerCase();
    final actualUnit = price.unit.trim().toLowerCase();

    return actualUnit == expectedUnit;
  }

  static AssetAction _resolveAction(Transaction transaction) {
    final storedAction = transaction.assetAction;

    if (storedAction != null) {
      return storedAction;
    }

    final normalizedTitle = transaction.title.toLowerCase();

    if (normalizedTitle.contains('sale') || normalizedTitle.contains('sell')) {
      return AssetAction.sell;
    }

    return AssetAction.buy;
  }

  static String _resolveAssetName(Transaction transaction, AssetAction action) {
    final storedName = transaction.assetName?.trim();

    if (storedName != null && storedName.isNotEmpty) {
      return storedName;
    }

    final accountParts = transaction.account
        .split('->')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (accountParts.length >= 2) {
      return action == AssetAction.sell
          ? accountParts.first
          : accountParts.last;
    }

    return transaction.title.trim();
  }

  static String? _normalizedSymbol(String? value) {
    final normalized = value?.trim().toUpperCase();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static String _resolvedUnit(String? value) {
    final normalized = value?.trim();

    if (normalized == null || normalized.isEmpty) {
      return 'unit';
    }

    return normalized;
  }

  static AssetKind _resolveKind({
    required String unit,
    required String assetName,
    required String? symbol,
  }) {
    final normalizedUnit = unit.toLowerCase();
    final normalizedName = assetName.toLowerCase();

    if (normalizedUnit == 'share' || symbol != null) {
      return AssetKind.stock;
    }

    if (normalizedUnit == 'gram' || normalizedName.contains('gold')) {
      return AssetKind.gold;
    }

    if (normalizedUnit == 'btc' ||
        normalizedUnit == 'coin' ||
        normalizedName.contains('bitcoin') ||
        normalizedName.contains('crypto')) {
      return AssetKind.crypto;
    }

    if (normalizedName.contains('inventory')) {
      return AssetKind.inventory;
    }

    return AssetKind.other;
  }

  static int _compareTransactions(Transaction left, Transaction right) {
    final dateComparison = left.date.compareTo(right.date);

    if (dateComparison != 0) {
      return dateComparison;
    }

    return left.createdAt.compareTo(right.createdAt);
  }

  static String _normalizeKey(String value) {
    return value.trim().toLowerCase();
  }
}

class _HoldingState {
  _HoldingState({
    required this.assetDefinitionId,
    required this.providerCode,
    required this.providerSymbol,
    required this.currencyCode,
    required this.onlinePricingEnabled,
    required this.assetKey,
    required this.name,
    required this.symbol,
    required this.kind,
    required this.unit,
    required this.lotSize,
  });

  final String? assetDefinitionId;
  final String? providerCode;
  final String? providerSymbol;
  final String currencyCode;
  final bool onlinePricingEnabled;

  final String assetKey;
  final String name;
  final String? symbol;
  final AssetKind kind;
  final String unit;
  final int lotSize;

  double quantity = 0;
  double costBasis = 0;
  double realizedGain = 0;
  int? latestTransactionPrice;
}
