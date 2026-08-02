import '../../master_data/domain/entities/financial_book.dart';
import '../../master_data/domain/entities/household_member.dart';
import 'cloud_models.dart';

abstract interface class CloudSharingRepository {
  CloudConfigurationDiagnostics get diagnostics;
  CloudAuthUser? get currentUser;
  Stream<CloudAuthUser?> get authChanges;

  Future<void> restoreAuthSession();

  Future<void> requestEmailOtp(String email);
  Future<CloudAuthUser> verifyEmailOtp({
    required String email,
    required String token,
  });
  Future<void> signOut();
  Future<List<CloudBookMembership>> listMemberships();
  Future<List<CloudBookInvitation>> listPendingInvitations();
  Future<CloudLinkResult> linkHousehold({
    required FinancialBook book,
    required HouseholdMember activeMember,
  });
  Future<CloudBookInvitation> createInvitation({
    required String bookId,
    required String email,
    required HouseholdMember householdMember,
  });
  Future<CloudBookMembership> acceptInvitation(String invitationId);
}
