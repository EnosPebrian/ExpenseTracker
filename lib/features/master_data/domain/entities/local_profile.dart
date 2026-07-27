import 'package:uuid/uuid.dart';

class LocalProfile {
  LocalProfile({
    String? id,
    required String displayName,
    String defaultCurrencyCode = 'IDR',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       displayName = displayName.trim(),
       defaultCurrencyCode = _normalizeCurrency(defaultCurrencyCode),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String displayName;
  final String defaultCurrencyCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toRecord() => {
    'id': id,
    'display_name': displayName,
    'default_currency_code': defaultCurrencyCode,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory LocalProfile.fromRecord(Map<String, Object?> record) {
    return LocalProfile(
      id: record['id'] as String,
      displayName: record['display_name'] as String,
      defaultCurrencyCode: record['default_currency_code'] as String? ?? 'IDR',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (record['created_at'] as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (record['updated_at'] as num).toInt(),
      ),
    );
  }

  static String _normalizeCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    return normalized.isEmpty ? 'IDR' : normalized;
  }
}

class LocalSessionState {
  const LocalSessionState({
    required this.activeProfileId,
    required this.onboardingCompleted,
    this.activeBookId,
    this.activeMemberId,
  });

  final String? activeProfileId;
  final bool onboardingCompleted;
  final String? activeBookId;
  final String? activeMemberId;
}
