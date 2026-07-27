import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/domain/cloud_models.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/domain/cloud_sharing_repository.dart';
import 'package:pilgrim_tracker/features/cloud_sharing/presentation/controllers/cloud_sharing_controller.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';

void main() {
  final book = FinancialBook(id: 'book', name: 'Household');
  final member = HouseholdMember(
    id: 'member',
    bookId: book.id,
    displayName: 'Enos',
  );

  test('missing Supabase configuration remains in local mode', () async {
    final repository = _FakeCloudRepository(configured: false);
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.status, CloudSharingStatus.notConfigured);
    expect(repository.calls, isEmpty);
  });

  test('requests email OTP without exposing configuration', () async {
    final repository = _FakeCloudRepository();
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.requestOtp(' Enos@Example.Test ');
    expect(repository.requestedEmail, 'enos@example.test');
    expect(controller.status, CloudSharingStatus.otpSent);
  });

  test('verifies OTP and restores the authenticated user', () async {
    final repository = _FakeCloudRepository();
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.requestOtp('enos@example.test');
    await controller.verifyOtp('123456');
    expect(controller.user?.id, 'auth-user');
    expect(repository.verifiedToken, '123456');
    expect(controller.status, CloudSharingStatus.signedInUnlinked);
  });

  test('restores an existing Supabase session independently', () async {
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(id: 'restored', email: 'e@example.test'),
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.user?.id, 'restored');
    expect(controller.status, CloudSharingStatus.signedInUnlinked);
  });

  test('sign out clears only remote controller state', () async {
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(
        id: 'auth-user',
        email: 'e@example.test',
      ),
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.signOut();
    expect(repository.signedOut, isTrue);
    expect(controller.status, CloudSharingStatus.signedOut);
    expect(controller.user, isNull);
  });

  test('links household and maps auth user to local member', () async {
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(
        id: 'auth-user',
        email: 'enos@example.test',
      ),
    );
    CloudLinkResult? persisted;
    final controller = CloudSharingController(
      repository: repository,
      onLinked: (result) async => persisted = result,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.linkHousehold(book: book, activeMember: member);
    expect(repository.linkCalls, 1);
    expect(persisted?.bookId, book.id);
    expect(persisted?.householdMemberId, member.id);
    expect(persisted?.userId, 'auth-user');
    expect(controller.status, CloudSharingStatus.householdLinked);
  });

  test('relink is idempotent', () async {
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(
        id: 'auth-user',
        email: 'e@example.test',
      ),
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.linkHousehold(book: book, activeMember: member);
    await controller.linkHousehold(book: book, activeMember: member);
    expect(repository.linkCalls, 2);
    expect(repository.memberships, hasLength(1));
    expect(controller.error, isNull);
  });

  test('conflicting remote book becomes a safe visible error', () async {
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(
        id: 'auth-user',
        email: 'e@example.test',
      ),
    )..conflictingBook = true;
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.linkHousehold(book: book, activeMember: member);
    expect(controller.status, CloudSharingStatus.error);
    expect(controller.error, contains('another owner'));
  });

  test('creates one idempotent invitation', () async {
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(
        id: 'auth-user',
        email: 'e@example.test',
      ),
    );
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.inviteMember(
      book: book,
      member: member,
      email: 'Grace@Example.Test',
    );
    await controller.inviteMember(
      book: book,
      member: member,
      email: 'grace@example.test',
    );
    expect(repository.invitations, hasLength(1));
    expect(repository.invitations.single.email, 'grace@example.test');
    expect(controller.status, CloudSharingStatus.invitationPending);
  });

  test('accepts invitation and retry keeps one membership', () async {
    final invitation = _invitation();
    final repository = _FakeCloudRepository(
      initialUser: const CloudAuthUser(
        id: 'auth-user',
        email: 'grace@example.test',
      ),
    )..invitations = [invitation];
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.acceptInvitation(invitation);
    await controller.acceptInvitation(invitation);
    expect(repository.memberships, hasLength(1));
    expect(controller.status, CloudSharingStatus.membershipActive);
  });

  for (final status in const ['expired', 'revoked']) {
    test('$status invitation is rejected safely', () async {
      final invitation = _invitation(status: status);
      final repository = _FakeCloudRepository(
        initialUser: const CloudAuthUser(
          id: 'auth-user',
          email: 'grace@example.test',
        ),
      )..invitations = [invitation];
      final controller = CloudSharingController(repository: repository);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.acceptInvitation(invitation);
      expect(controller.status, CloudSharingStatus.error);
      expect(controller.error, contains(status));
    });
  }

  test('cloud failures remain isolated from local feature state', () async {
    final repository = _FakeCloudRepository()..offline = true;
    final controller = CloudSharingController(repository: repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.requestOtp('enos@example.test');
    expect(controller.status, CloudSharingStatus.error);
    expect(controller.error, contains('Local finance remains usable'));
  });
}

CloudBookInvitation _invitation({String status = 'pending'}) =>
    CloudBookInvitation(
      id: 'invitation',
      bookId: 'book',
      email: 'grace@example.test',
      householdMemberId: 'member',
      role: CloudMembershipRole.member,
      status: status,
      expiresAt: status == 'expired'
          ? DateTime(2020)
          : DateTime.now().add(const Duration(days: 1)),
    );

class _FakeCloudRepository implements CloudSharingRepository {
  _FakeCloudRepository({this.configured = true, CloudAuthUser? initialUser})
    : _user = initialUser;

  final bool configured;
  CloudAuthUser? _user;
  final changes = StreamController<CloudAuthUser?>.broadcast();
  final calls = <String>[];
  List<CloudBookMembership> memberships = [];
  List<CloudBookInvitation> invitations = [];
  String? requestedEmail;
  String? verifiedToken;
  bool signedOut = false;
  bool conflictingBook = false;
  bool offline = false;
  int linkCalls = 0;

  @override
  bool get isConfigured => configured;
  @override
  CloudAuthUser? get currentUser => _user;
  @override
  Stream<CloudAuthUser?> get authChanges => changes.stream;

  void _check() {
    if (offline) {
      throw const CloudSharingException(
        'Cloud is offline. Local finance remains usable.',
      );
    }
  }

  @override
  Future<void> requestEmailOtp(String email) async {
    _check();
    calls.add('otp');
    requestedEmail = email;
  }

  @override
  Future<CloudAuthUser> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    _check();
    verifiedToken = token;
    return _user = CloudAuthUser(id: 'auth-user', email: email);
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    _user = null;
  }

  @override
  Future<List<CloudBookMembership>> listMemberships() async {
    _check();
    return List.of(memberships);
  }

  @override
  Future<List<CloudBookInvitation>> listPendingInvitations() async {
    _check();
    return List.of(invitations);
  }

  @override
  Future<CloudLinkResult> linkHousehold({
    required FinancialBook book,
    required HouseholdMember activeMember,
  }) async {
    _check();
    linkCalls++;
    if (conflictingBook) {
      throw const CloudSharingException(
        'This household belongs to another owner.',
      );
    }
    final membership = CloudBookMembership(
      id: 'membership',
      bookId: book.id,
      householdMemberId: activeMember.id,
      role: CloudMembershipRole.owner,
      status: 'active',
    );
    memberships = [membership];
    return CloudLinkResult(
      bookId: book.id,
      membershipId: membership.id,
      userId: _user?.id ?? 'auth-user',
      householdMemberId: activeMember.id,
      linkedAt: DateTime(2026, 7, 26),
    );
  }

  @override
  Future<CloudBookInvitation> createInvitation({
    required String bookId,
    required String email,
    required HouseholdMember householdMember,
  }) async {
    _check();
    final existing = invitations
        .where((item) => item.email == email)
        .firstOrNull;
    if (existing != null) return existing;
    final invitation = CloudBookInvitation(
      id: 'invitation',
      bookId: bookId,
      email: email,
      householdMemberId: householdMember.id,
      role: CloudMembershipRole.member,
      status: 'pending',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
    invitations = [invitation];
    return invitation;
  }

  @override
  Future<CloudBookMembership> acceptInvitation(String invitationId) async {
    _check();
    final invitation = invitations.firstWhere(
      (item) => item.id == invitationId,
      orElse: () => _invitation(status: 'accepted'),
    );
    if (invitation.status == 'expired' || invitation.status == 'revoked') {
      throw CloudSharingException('${invitation.status} invitation denied');
    }
    if (memberships.isNotEmpty) return memberships.first;
    final membership = CloudBookMembership(
      id: 'accepted-membership',
      bookId: invitation.bookId,
      householdMemberId: invitation.householdMemberId,
      role: invitation.role,
      status: 'active',
    );
    memberships = [membership];
    return membership;
  }
}
