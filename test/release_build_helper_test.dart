import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = '${Directory.current.path}\\tool\\build_release.ps1';

  Future<ProcessResult> validate(Map<String, String> environment) =>
      Process.run('powershell.exe', [
        '-NoProfile',
        '-File',
        script,
        '-Platform',
        'windows',
        '-ValidateOnly',
      ], environment: environment);

  test('release helper rejects missing values', () async {
    final result = await validate({
      'SUPABASE_URL': '',
      'SUPABASE_PUBLISHABLE_KEY': '',
    });
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('SUPABASE_URL is required'),
    );
  });

  test('release helper rejects placeholders', () async {
    final result = await validate({
      'SUPABASE_URL': 'https://YOUR_PROJECT_REF.supabase.co',
      'SUPABASE_PUBLISHABLE_KEY': 'YOUR_PUBLIC_PUBLISHABLE_KEY',
    });
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}${result.stderr}', contains('placeholder'));
  });

  test('release helper validates without printing publishable key', () async {
    const secretMarker = 'public-test-key-must-not-appear';
    final result = await validate({
      'SUPABASE_URL': 'https://project.supabase.co',
      'SUPABASE_PUBLISHABLE_KEY': secretMarker,
    });
    final output = '${result.stdout}${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, isNot(contains(secretMarker)));
    expect(output, contains('publishable key present: yes'));
  });
}
