import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/config/app_environment.dart';

void main() {
  test('missing and whitespace configuration is unconfigured', () {
    final diagnostics = SupabaseConfigurationDiagnostics.inspect(
      url: '   ',
      publishableKey: '',
    );
    expect(diagnostics.isValid, isFalse);
    expect(diagnostics.urlPresent, isFalse);
    expect(diagnostics.publishableKeyPresent, isFalse);
  });

  test('malformed and non-HTTPS project URLs are rejected', () {
    for (final url in [
      'not a url',
      'http://project.supabase.co',
      'https://project.supabase.co/unexpected',
    ]) {
      expect(
        SupabaseConfigurationDiagnostics.inspect(
          url: url,
          publishableKey: 'public-test-key',
        ).isValid,
        isFalse,
      );
    }
  });

  test('valid HTTPS configuration reports only non-secret presence', () {
    final diagnostics = SupabaseConfigurationDiagnostics.inspect(
      url: ' https://project.supabase.co ',
      publishableKey: ' public-test-key ',
    );
    expect(diagnostics.isValid, isTrue);
    expect(diagnostics.urlValid, isTrue);
    expect(diagnostics.publishableKeyPresent, isTrue);
  });
}
