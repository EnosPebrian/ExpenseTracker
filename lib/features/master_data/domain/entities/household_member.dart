import 'package:uuid/uuid.dart';

enum HouseholdMemberRole {
  owner('owner', 'Owner'),
  member('member', 'Member');

  const HouseholdMemberRole(this.storedValue, this.label);
  final String storedValue;
  final String label;

  static HouseholdMemberRole fromStoredValue(Object? value) => values
      .firstWhere((role) => role.storedValue == value, orElse: () => member);
}

class HouseholdMember {
  static const _unset = Object();

  HouseholdMember({
    String? id,
    required this.bookId,
    required String displayName,
    this.role = HouseholdMemberRole.member,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.authUserId,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       displayName = displayName.trim(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String bookId;
  final String displayName;
  final HouseholdMemberRole role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? authUserId;
  final int version;
  final String deviceId;
  final String syncStatus;

  HouseholdMember copyWith({
    String? displayName,
    HouseholdMemberRole? role,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? authUserId = _unset,
    int? version,
    String? syncStatus,
  }) => HouseholdMember(
    id: id,
    bookId: bookId,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    authUserId: identical(authUserId, _unset)
        ? this.authUserId
        : authUserId as String?,
    version: version ?? this.version,
    deviceId: deviceId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'book_id': bookId,
    'display_name': displayName,
    'role': role.storedValue,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'auth_user_id': authUserId,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory HouseholdMember.fromRecord(Map<String, Object?> record) =>
      HouseholdMember(
        id: record['id'] as String,
        bookId: record['book_id'] as String,
        displayName: record['display_name'] as String,
        role: HouseholdMemberRole.fromStoredValue(record['role']),
        createdAt: _date(record['created_at']) ?? DateTime.now(),
        updatedAt: _date(record['updated_at']) ?? DateTime.now(),
        deletedAt: _date(record['deleted_at']),
        authUserId: record['auth_user_id'] as String?,
        version: (record['version'] as num?)?.toInt() ?? 1,
        deviceId: record['device_id'] as String? ?? 'local-device',
        syncStatus: record['sync_status'] as String? ?? 'local_only',
      );

  static DateTime? _date(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
}
