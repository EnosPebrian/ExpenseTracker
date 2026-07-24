enum AssetMarketReferenceSource {
  manual('manual'),
  cachedQuote('cached_quote'),
  unknown('unknown');

  const AssetMarketReferenceSource(this.storedValue);

  final String storedValue;

  static AssetMarketReferenceSource? fromStoredValue(Object? value) {
    if (value == null) return null;
    for (final source in values) {
      if (source.storedValue == value) return source;
    }
    return AssetMarketReferenceSource.unknown;
  }
}
