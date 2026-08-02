import 'package:supabase_flutter/supabase_flutter.dart';

import '../../master_data/domain/entities/financial_book.dart';
import '../../master_data/domain/entities/household_member.dart';
import '../domain/cloud_models.dart';
import '../domain/cloud_sharing_repository.dart';

class SupabaseCloudSharingRepository implements CloudSharingRepository {
  SupabaseCloudSharingRepository(this._client);

  final SupabaseClient _client;

  @override
  CloudConfigurationDiagnostics get diagnostics =>
      const CloudConfigurationDiagnostics(
        configuration: CloudConfigurationState.configured,
        urlValid: true,
        publishableKeyPresent: true,
        authInitialization: CloudAuthInitializationState.initialized,
      );

  @override
  CloudAuthUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<CloudAuthUser?> get authChanges => _client.auth.onAuthStateChange.map(
    (event) => _mapUser(event.session?.user),
  );

  @override
  Future<void> restoreAuthSession() async {
    // Supabase.initialize restores persisted auth before this repository exists.
    // Reading currentUser is intentionally local and does not ping Auth.
  }

  @override
  Future<void> requestEmailOtp(String email) async {
    await _guard(
      () => _client.auth.signInWithOtp(email: _normalizeEmail(email)),
      'Could not send the verification code.',
    );
  }

  @override
  Future<CloudAuthUser> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final response = await _guard(
      () => _client.auth.verifyOTP(
        email: _normalizeEmail(email),
        token: token.trim(),
        type: OtpType.email,
      ),
      'The verification code is invalid or expired.',
    );
    final user = _mapUser(response.user);
    if (user == null) {
      throw const CloudSharingException(
        'Could not restore the signed-in user.',
      );
    }
    return user;
  }

  @override
  Future<void> signOut() async {
    await _guard(_client.auth.signOut, 'Could not sign out of cloud sharing.');
  }

  @override
  Future<List<CloudBookMembership>> listMemberships() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _guard(
      () => _client
          .from('book_memberships')
          .select('id,book_id,user_id,household_member_id,role,status')
          .eq('status', 'active')
          .eq('user_id', userId),
      'Could not load cloud memberships.',
    );
    return _maps(rows)
        .map(CloudBookMembership.fromJson)
        .where((membership) => membership.userId == userId)
        .toList();
  }

  @override
  Future<List<CloudBookInvitation>> listPendingInvitations() async {
    final ownedRows = await _guard(
      () => _client
          .from('book_invitations')
          .select(
            'id,book_id,email_normalized,household_member_id,role,status,expires_at',
          )
          .eq('status', 'pending'),
      'Could not load household invitations.',
    );
    final receivedRows = await _guard(
      () => _client.rpc('list_my_pending_invitations'),
      'Could not load household invitations.',
    );
    final invitations = <String, CloudBookInvitation>{};
    for (final row in [..._maps(ownedRows), ..._maps(receivedRows)]) {
      final invitation = CloudBookInvitation.fromJson(row);
      invitations[invitation.id] = invitation;
    }
    return invitations.values.toList();
  }

  @override
  Future<CloudLinkResult> linkHousehold({
    required FinancialBook book,
    required HouseholdMember activeMember,
  }) async {
    final result = await _guard(
      () => _client.rpc(
        'link_local_household',
        params: {
          'p_book_id': book.id,
          'p_book_name': book.name,
          'p_base_currency_code': book.baseCurrencyCode,
          'p_household_member_id': activeMember.id,
          'p_member_display_name': activeMember.displayName,
        },
      ),
      'Could not link this household. It may already belong to another owner.',
    );
    return CloudLinkResult.fromJson(_singleMap(result));
  }

  @override
  Future<CloudBookInvitation> createInvitation({
    required String bookId,
    required String email,
    required HouseholdMember householdMember,
  }) async {
    final response = await _guard(
      () => _client.functions.invoke(
        'create-book-invitation',
        body: {
          'book_id': bookId,
          'email': _normalizeEmail(email),
          'household_member_id': householdMember.id,
          'role': 'member',
        },
      ),
      'Could not create the household invitation.',
    );
    return CloudBookInvitation.fromJson(_singleMap(response.data));
  }

  @override
  Future<CloudBookMembership> acceptInvitation(String invitationId) async {
    final response = await _guard(
      () => _client.rpc(
        'accept_book_invitation',
        params: {'p_invitation_id': invitationId},
      ),
      'This invitation cannot be accepted. It may be expired or revoked.',
    );
    return CloudBookMembership.fromJson(_singleMap(response));
  }

  static CloudAuthUser? _mapUser(User? user) {
    final email = user?.email;
    return user == null || email == null
        ? null
        : CloudAuthUser(id: user.id, email: email);
  }

  static String _normalizeEmail(String value) => value.trim().toLowerCase();

  static List<Map<String, Object?>> _maps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList();
  }

  static Map<String, Object?> _singleMap(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map).cast<String, Object?>();
    }
    throw const CloudSharingException('The cloud service returned no result.');
  }

  static Future<T> _guard<T>(
    Future<T> Function() operation,
    String safeMessage,
  ) async {
    try {
      return await operation();
    } on CloudSharingException {
      rethrow;
    } on AuthException catch (exception) {
      throw CloudSharingException(
        authFailureMessage(exception, fallback: safeMessage),
        kind: authFailureKind(exception),
      );
    } catch (_) {
      throw CloudSharingException(safeMessage);
    }
  }

  static String authFailureMessage(
    AuthException exception, {
    required String fallback,
  }) {
    final code = exception.code?.trim();
    final status = exception.statusCode?.trim();
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        status == '429') {
      return 'Too many verification emails were requested. '
          'Wait a few minutes, then try again.';
    }
    if (code == 'email_provider_disabled' || code == 'otp_disabled') {
      return 'Email verification is disabled in Supabase Auth.';
    }
    if (code == 'request_timeout' || exception is AuthRetryableFetchException) {
      return 'Pilgrim Tracker could not reach Supabase Auth. '
          'Check your internet connection and try again.';
    }

    if (status == '401' ||
        code == 'refresh_token_not_found' ||
        code == 'refresh_token_already_used' ||
        code == 'bad_jwt') {
      return 'Your cloud session expired. Sign in again. Your local data is safe.';
    }

    final diagnostic = [
      if (code != null && code.isNotEmpty) code,
      if (status != null && status.isNotEmpty) 'HTTP $status',
    ].join(', ');
    return [fallback, if (diagnostic.isNotEmpty) '[$diagnostic]'].join(' ');
  }

  static CloudFailureKind authFailureKind(AuthException exception) {
    final code = exception.code?.trim();
    final status = exception.statusCode?.trim();
    if (code == 'request_timeout' || exception is AuthRetryableFetchException) {
      return CloudFailureKind.connectivity;
    }
    if (status == '401' ||
        code == 'refresh_token_not_found' ||
        code == 'refresh_token_already_used' ||
        code == 'bad_jwt') {
      return CloudFailureKind.sessionExpired;
    }
    return CloudFailureKind.rejected;
  }
}
