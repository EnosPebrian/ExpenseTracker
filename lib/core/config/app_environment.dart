class AppEnvironment {
  const AppEnvironment._();

  static const String alphaVantageApiKey = String.fromEnvironment(
    'ALPHA_VANTAGE_API_KEY',
  );

  static bool get hasAlphaVantageApiKey {
    return alphaVantageApiKey.trim().isNotEmpty;
  }
}
