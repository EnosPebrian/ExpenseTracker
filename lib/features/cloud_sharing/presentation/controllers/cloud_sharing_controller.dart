import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/financial_book.dart';
import '../../../master_data/domain/entities/household_member.dart';
import '../../domain/cloud_models.dart';
import '../../domain/cloud_sharing_repository.dart';

enum CloudSharingStatus {
  notConfigured,
  signedOut,
  otpSent,
  signedInUnlinked,
  householdLinked,
  invitationPending,
  membershipActive,
  error,
}

class CloudSharingController extends ChangeNotifier {
  CloudSharingController({required this.repository, this.onLinked});

  final CloudSharingRepository repository;
  final Future<void> Function(CloudLinkResult result)? onLinked;

  CloudSharingStatus status = CloudSharingStatus.notConfigured;
  CloudAuthUser? user;
  List<CloudBookMembership> memberships = const [];
  List<CloudBookInvitation> invitations = const [];
  String? pendingEmail;
  String? error;
  bool busy = false;
  StreamSubscription<CloudAuthUser?>? _authSubscription;

  bool isLinked(String bookId) => memberships.any(
    (membership) =>
        membership.bookId == bookId && membership.status == 'active',
  );

  Future<void> initialize() async {
    if (!repository.isConfigured) {
      status = CloudSharingStatus.notConfigured;
      notifyListeners();
      return;
    }
    _authSubscription = repository.authChanges.listen((changedUser) {
      user = changedUser;
      if (changedUser == null) {
        memberships = const [];
        invitations = const [];
        status = CloudSharingStatus.signedOut;
        notifyListeners();
      } else {
        unawaited(refreshRemoteState());
      }
    });
    user = repository.currentUser;
    if (user == null) {
      status = CloudSharingStatus.signedOut;
      notifyListeners();
      return;
    }
    await refreshRemoteState();
  }

  Future<void> requestOtp(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized)) {
      error = 'Enter a valid email address.';
      notifyListeners();
      return;
    }
    await _run(() async {
      await repository.requestEmailOtp(normalized);
      pendingEmail = normalized;
      status = CloudSharingStatus.otpSent;
    });
  }

  Future<void> verifyOtp(String token) async {
    final email = pendingEmail;
    if (email == null || token.trim().isEmpty) {
      error = 'Enter the verification code sent to your email.';
      notifyListeners();
      return;
    }
    await _run(() async {
      user = await repository.verifyEmailOtp(email: email, token: token);
      pendingEmail = null;
      await _loadRemoteState();
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      await repository.signOut();
      user = null;
      memberships = const [];
      invitations = const [];
      pendingEmail = null;
      status = CloudSharingStatus.signedOut;
    });
  }

  Future<void> refreshRemoteState() => _run(_loadRemoteState);

  Future<void> linkHousehold({
    required FinancialBook book,
    required HouseholdMember activeMember,
  }) async {
    await _run(() async {
      final result = await repository.linkHousehold(
        book: book,
        activeMember: activeMember,
      );
      await onLinked?.call(result);
      memberships = await repository.listMemberships();
      status = CloudSharingStatus.householdLinked;
    });
  }

  Future<void> inviteMember({
    required FinancialBook book,
    required HouseholdMember member,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!_validEmail(normalized)) {
      error = 'Enter a valid invitation email.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final invitation = await repository.createInvitation(
        bookId: book.id,
        email: normalized,
        householdMember: member,
      );
      invitations = [
        invitation,
        ...invitations.where((item) => item.id != invitation.id),
      ];
      status = CloudSharingStatus.invitationPending;
    });
  }

  Future<void> acceptInvitation(CloudBookInvitation invitation) async {
    await _run(() async {
      final membership = await repository.acceptInvitation(invitation.id);
      memberships = [
        membership,
        ...memberships.where((item) => item.id != membership.id),
      ];
      invitations = invitations
          .where((item) => item.id != invitation.id)
          .toList();
      status = CloudSharingStatus.membershipActive;
    });
  }

  Future<void> _loadRemoteState() async {
    if (user == null) {
      status = CloudSharingStatus.signedOut;
      return;
    }
    memberships = await repository.listMemberships();
    invitations = await repository.listPendingInvitations();
    status = invitations.isNotEmpty
        ? CloudSharingStatus.invitationPending
        : memberships.isNotEmpty
        ? CloudSharingStatus.membershipActive
        : CloudSharingStatus.signedInUnlinked;
  }

  Future<void> _run(Future<void> Function() operation) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } on CloudSharingException catch (exception) {
      error = exception.message;
      status = CloudSharingStatus.error;
    } catch (_) {
      error =
          'Cloud sharing is temporarily unavailable. Local finance remains usable.';
      status = CloudSharingStatus.error;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static bool _validEmail(String value) {
    final at = value.indexOf('@');
    return at > 0 && at < value.length - 3 && value.contains('.', at);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
