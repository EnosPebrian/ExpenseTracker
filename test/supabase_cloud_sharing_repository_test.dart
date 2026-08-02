import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/data/supabase_cloud_sharing_repository.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/domain/cloud_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('email rate limits produce an actionable message', () {
    const error = AuthApiException(
      'email rate limit exceeded',
      statusCode: '429',
      code: 'over_email_send_rate_limit',
    );

    expect(
      SupabaseCloudSharingRepository.authFailureMessage(
        error,
        fallback: 'Could not send the verification code.',
      ),
      'Too many verification emails were requested. '
      'Wait a few minutes, then try again.',
    );
  });

  test('provider failures retain safe code and status without payload', () {
    const error = AuthApiException(
      'Error sending confirmation email',
      statusCode: '500',
      code: 'unexpected_failure',
    );

    expect(
      SupabaseCloudSharingRepository.authFailureMessage(
        error,
        fallback: 'Could not send the verification code.',
      ),
      'Could not send the verification code. [unexpected_failure, HTTP 500]',
    );
  });

  test('expired sessions use safe local-data copy and typed failure', () {
    const error = AuthApiException(
      'secret response payload',
      statusCode: '401',
      code: 'bad_jwt',
    );
    expect(
      SupabaseCloudSharingRepository.authFailureMessage(
        error,
        fallback: 'Could not restore session.',
      ),
      'Your cloud session expired. Sign in again. Your local data is safe.',
    );
    expect(
      SupabaseCloudSharingRepository.authFailureKind(error),
      CloudFailureKind.sessionExpired,
    );
  });

  test('user-facing auth errors never include provider secret text', () {
    const secret = 'publishable-key-must-not-appear';
    const error = AuthApiException(
      secret,
      statusCode: '500',
      code: 'unexpected_failure',
    );
    final message = SupabaseCloudSharingRepository.authFailureMessage(
      error,
      fallback: 'Could not send the verification code.',
    );
    expect(message, isNot(contains(secret)));
  });
}
