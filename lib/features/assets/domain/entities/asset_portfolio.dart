import 'asset_kind.dart';

export 'asset_kind.dart';

class AssetHolding {
  const AssetHolding({
    this.assetDefinitionId,
    this.providerCode,
    this.providerSymbol,
    this.currencyCode = 'IDR',
    this.onlinePricingEnabled = true,
    required this.assetKey,
    required this.name,
    required this.symbol,
    required this.kind,
    required this.unit,
    required this.quantity,
    required this.lotSize,
    required this.costBasis,
    required this.averageCost,
    required this.currentPrice,
    required this.marketValue,
    required this.realizedGain,
    required this.priceSource,
    required this.priceQuotedAt,
    required this.isPriceDelayed,
    required this.isManualPrice,
  });

  /// Stable link to the concrete asset definition.
  ///
  /// Null indicates a legacy transaction whose identity was resolved from
  /// its stored asset name, symbol, account, or title.
  final String? assetDefinitionId;

  /// Market-data provider configured by the linked asset definition.
  ///
  /// Example: ALPHA_VANTAGE.
  final String? providerCode;

  /// Symbol that must be sent to the market-data provider.
  ///
  /// This may differ from the display symbol. For example:
  ///
  /// - display symbol: BBCA
  /// - provider symbol: BBCA.JK
  final String? providerSymbol;

  /// Currency in which the asset and its market price are recorded.
  final String currencyCode;

  /// Whether the linked asset definition permits online pricing.
  final bool onlinePricingEnabled;

  /// Stable key used to match this holding with cached market prices.
  ///
  /// Stocks normally use their ticker, such as BBCA.
  /// Other assets normally use their asset name.
  final String assetKey;

  final String name;
  final String? symbol;
  final AssetKind kind;
  final String unit;

  /// Current remaining quantity.
  final double quantity;

  /// Number of shares in one lot.
  ///
  /// Non-stock assets use 1.
  final int lotSize;

  /// Remaining acquisition cost after recorded sales.
  final int costBasis;

  /// Weighted-average cost per remaining unit.
  final int averageCost;

  /// Latest online or manually entered price per unit.
  ///
  /// Null means no current market price is available.
  final int? currentPrice;

  /// Current market value.
  ///
  /// When no market price exists, this falls back to cost basis.
  final int marketValue;

  /// Gain already realized through recorded sales.
  final int realizedGain;

  final String? priceSource;
  final DateTime? priceQuotedAt;
  final bool isPriceDelayed;
  final bool isManualPrice;
  String? get normalizedProviderCode {
    final normalized = providerCode?.trim().toUpperCase();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String? get normalizedProviderSymbol {
    final normalized = providerSymbol?.trim().toUpperCase();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String? get normalizedSymbol {
    final normalized = symbol?.trim().toUpperCase();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  String get normalizedCurrencyCode {
    final normalized = currencyCode.trim().toUpperCase();

    return normalized.isEmpty ? 'IDR' : normalized;
  }

  String get normalizedUnit {
    final normalized = unit.trim().toLowerCase();

    return normalized.isEmpty ? 'unit' : normalized;
  }

  /// Symbol used for online requests.
  ///
  /// Concrete definitions prefer [providerSymbol]. Legacy holdings fall back
  /// to their stored display symbol.
  String? get quoteSymbol {
    return normalizedProviderSymbol ?? normalizedSymbol;
  }

  bool get hasMarketPrice => currentPrice != null;

  double get lots {
    if (kind != AssetKind.stock || lotSize <= 0) {
      return 0;
    }

    return quantity / lotSize;
  }

  int get unrealizedGain => marketValue - costBasis;

  double get unrealizedReturn {
    if (costBasis == 0) {
      return 0;
    }

    return unrealizedGain / costBasis;
  }
}

class AssetPortfolio {
  const AssetPortfolio({
    required this.holdings,
    required this.totalCostBasis,
    required this.totalMarketValue,
    required this.totalUnrealizedGain,
    required this.totalRealizedGain,
  });

  final List<AssetHolding> holdings;
  final int totalCostBasis;
  final int totalMarketValue;
  final int totalUnrealizedGain;
  final int totalRealizedGain;

  bool get isEmpty => holdings.isEmpty;

  int get holdingCount => holdings.length;
}
