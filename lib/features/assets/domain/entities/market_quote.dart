class MarketQuote {
  const MarketQuote({
    required this.symbol,
    required this.priceMinor,
    required this.minorUnitScale,
    required this.currencyCode,
    required this.unit,
    required this.quotedAt,
    required this.source,
    this.isDelayed = false,
  }) : assert(minorUnitScale > 0);

  /// Market symbol, such as BBCA, IBM, or XAU.
  final String symbol;

  /// Price stored as an integer.
  ///
  /// Examples:
  ///
  /// - IDR 9,250 with scale 1 is stored as 9250.
  /// - USD 185.50 with scale 100 is stored as 18550.
  final int priceMinor;

  /// Number of minor units in one major currency unit.
  ///
  /// Examples:
  ///
  /// - IDR uses 1.
  /// - USD commonly uses 100.
  final int minorUnitScale;

  final String currencyCode;

  /// Unit priced by this quote.
  ///
  /// Examples: share, gram, coin.
  final String unit;

  final DateTime quotedAt;
  final String source;
  final bool isDelayed;

  double get price {
    return priceMinor / minorUnitScale;
  }
}
