class AppEnvironment {
  const AppEnvironment._();

  static const String alphaVantageApiKey = String.fromEnvironment(
    'ALPHA_VANTAGE_API_KEY',
  );

  static bool get hasAlphaVantageApiKey {
    return alphaVantageApiKey.trim().isNotEmpty;
  }

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String supabaseLegacyAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static String get supabaseClientKey =>
      supabasePublishableKey.trim().isNotEmpty
      ? supabasePublishableKey
      : supabaseLegacyAnonKey;

  static bool get hasSupabaseConfiguration {
    final uri = Uri.tryParse(supabaseUrl.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        supabaseClientKey.trim().isNotEmpty;
  }
}
