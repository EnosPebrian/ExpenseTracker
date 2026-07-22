class AssetSymbolMatch {
  const AssetSymbolMatch({
    required this.symbol,
    required this.name,
    required this.type,
    required this.region,
    required this.currencyCode,
    required this.matchScore,
  });

  final String symbol;
  final String name;
  final String type;
  final String region;
  final String currencyCode;

  /// Value from 0 to 1.
  final double matchScore;
}
