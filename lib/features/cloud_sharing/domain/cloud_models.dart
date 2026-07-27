enum CloudMembershipRole { owner, member }

class CloudAuthUser {
  const CloudAuthUser({required this.id, required this.email});
  final String id;
  final String email;
}

class CloudBookMembership {
  const CloudBookMembership({
    required this.id,
    required this.bookId,
    required this.role,
    required this.status,
    this.householdMemberId,
  });

  final String id;
  final String bookId;
  final String? householdMemberId;
  final CloudMembershipRole role;
  final String status;

  factory CloudBookMembership.fromJson(Map<String, Object?> json) =>
      CloudBookMembership(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        householdMemberId: json['household_member_id'] as String?,
        role: json['role'] == 'owner'
            ? CloudMembershipRole.owner
            : CloudMembershipRole.member,
        status: json['status'] as String? ?? 'active',
      );
}

class CloudBookInvitation {
  const CloudBookInvitation({
    required this.id,
    required this.bookId,
    required this.email,
    required this.role,
    required this.status,
    required this.expiresAt,
    this.householdMemberId,
  });

  final String id;
  final String bookId;
  final String email;
  final String? householdMemberId;
  final CloudMembershipRole role;
  final String status;
  final DateTime expiresAt;

  factory CloudBookInvitation.fromJson(Map<String, Object?> json) =>
      CloudBookInvitation(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        email: json['email_normalized'] as String,
        householdMemberId: json['household_member_id'] as String?,
        role: json['role'] == 'owner'
            ? CloudMembershipRole.owner
            : CloudMembershipRole.member,
        status: json['status'] as String? ?? 'pending',
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class CloudLinkResult {
  const CloudLinkResult({
    required this.bookId,
    required this.membershipId,
    required this.userId,
    required this.householdMemberId,
    required this.linkedAt,
  });

  final String bookId;
  final String membershipId;
  final String userId;
  final String householdMemberId;
  final DateTime linkedAt;

  factory CloudLinkResult.fromJson(Map<String, Object?> json) =>
      CloudLinkResult(
        bookId: json['book_id'] as String,
        membershipId: json['membership_id'] as String,
        userId: json['user_id'] as String,
        householdMemberId: json['household_member_id'] as String,
        linkedAt: DateTime.parse(json['linked_at'] as String),
      );
}

class CloudSharingException implements Exception {
  const CloudSharingException(this.message);
  final String message;

  @override
  String toString() => message;
}
