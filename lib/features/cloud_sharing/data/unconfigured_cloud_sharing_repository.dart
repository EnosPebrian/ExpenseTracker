import '../../master_data/domain/entities/financial_book.dart';
import '../../master_data/domain/entities/household_member.dart';
import '../domain/cloud_models.dart';
import '../domain/cloud_sharing_repository.dart';

class UnconfiguredCloudSharingRepository implements CloudSharingRepository {
  const UnconfiguredCloudSharingRepository({this.configurationError});

  final String? configurationError;

  @override
  bool get isConfigured => configurationError != null;

  @override
  CloudAuthUser? get currentUser => null;

  @override
  Stream<CloudAuthUser?> get authChanges => const Stream.empty();

  Never _unavailable() => throw CloudSharingException(
    configurationError ?? 'Cloud sharing is not configured.',
  );

  @override
  Future<CloudBookMembership> acceptInvitation(String invitationId) async =>
      _unavailable();

  @override
  Future<CloudBookInvitation> createInvitation({
    required String bookId,
    required String email,
    required HouseholdMember householdMember,
  }) async => _unavailable();

  @override
  Future<List<CloudBookMembership>> listMemberships() async =>
      configurationError == null ? const [] : _unavailable();

  @override
  Future<List<CloudBookInvitation>> listPendingInvitations() async =>
      configurationError == null ? const [] : _unavailable();

  @override
  Future<CloudLinkResult> linkHousehold({
    required FinancialBook book,
    required HouseholdMember activeMember,
  }) async => _unavailable();

  @override
  Future<void> requestEmailOtp(String email) async => _unavailable();

  @override
  Future<void> signOut() async {}

  @override
  Future<CloudAuthUser> verifyEmailOtp({
    required String email,
    required String token,
  }) async => _unavailable();
}
