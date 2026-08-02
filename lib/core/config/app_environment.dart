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

  static SupabaseConfigurationDiagnostics get supabaseDiagnostics =>
      SupabaseConfigurationDiagnostics.inspect(
        url: supabaseUrl,
        publishableKey: supabaseClientKey,
      );

  static bool get hasSupabaseConfiguration => supabaseDiagnostics.isValid;
}

class SupabaseConfigurationDiagnostics {
  const SupabaseConfigurationDiagnostics({
    required this.urlPresent,
    required this.urlValid,
    required this.publishableKeyPresent,
  });

  factory SupabaseConfigurationDiagnostics.inspect({
    required String url,
    required String publishableKey,
  }) {
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);
    return SupabaseConfigurationDiagnostics(
      urlPresent: trimmedUrl.isNotEmpty,
      urlValid:
          trimmedUrl.isNotEmpty &&
          uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.host.contains('.') &&
          !uri.hasFragment &&
          (uri.path.isEmpty || uri.path == '/'),
      publishableKeyPresent: publishableKey.trim().isNotEmpty,
    );
  }

  final bool urlPresent;
  final bool urlValid;
  final bool publishableKeyPresent;

  bool get isValid => urlValid && publishableKeyPresent;
}
