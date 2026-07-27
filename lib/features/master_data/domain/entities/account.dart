import 'package:uuid/uuid.dart';

enum AccountType {
  cash('cash', 'Cash'),
  bank('bank', 'Bank account'),
  eWallet('e_wallet', 'E-wallet'),
  asset('asset', 'Other asset'),
  liability('liability', 'Liability');

  const AccountType(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static AccountType fromStoredValue(Object? value) {
    return values.firstWhere(
      (type) => type.storedValue == value,
      orElse: () => AccountType.asset,
    );
  }
}

class Account {
  static const _unset = Object();

  Account({
    String? id,
    this.bookId,
    this.ownerMemberId,
    required String name,
    this.accountType = AccountType.asset,
    String currencyCode = 'IDR',
    this.openingBalance = 0,
    this.openingBalanceDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       name = name.trim(),
       currencyCode = _normalizeCurrency(currencyCode),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String? bookId;
  final String? ownerMemberId;
  final String name;
  final AccountType accountType;
  final String currencyCode;
  final int openingBalance;
  final DateTime? openingBalanceDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  bool get hasOpeningBalance => openingBalanceDate != null;

  Account copyWith({
    String? id,
    Object? bookId = _unset,
    Object? ownerMemberId = _unset,
    String? name,
    AccountType? accountType,
    String? currencyCode,
    int? openingBalance,
    Object? openingBalanceDate = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? version,
    String? deviceId,
    String? syncStatus,
  }) {
    return Account(
      id: id ?? this.id,
      bookId: identical(bookId, _unset) ? this.bookId : bookId as String?,
      ownerMemberId: identical(ownerMemberId, _unset)
          ? this.ownerMemberId
          : ownerMemberId as String?,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      currencyCode: currencyCode ?? this.currencyCode,
      openingBalance: openingBalance ?? this.openingBalance,
      openingBalanceDate: identical(openingBalanceDate, _unset)
          ? this.openingBalanceDate
          : openingBalanceDate as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _unset)
          ? this.deletedAt
          : deletedAt as DateTime?,
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, Object?> toRecord() => {
    'id': id,
    'book_id': bookId,
    'owner_member_id': ownerMemberId,
    'name': name,
    'account_type': accountType.storedValue,
    'currency_code': currencyCode,
    'opening_balance': openingBalance,
    'opening_balance_date': openingBalanceDate?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory Account.fromRecord(Map<String, Object?> record) {
    return Account(
      id: record['id'] as String,
      bookId: record['book_id'] as String?,
      ownerMemberId: record['owner_member_id'] as String?,
      name: record['name'] as String,
      accountType: AccountType.fromStoredValue(record['account_type']),
      currencyCode: record['currency_code'] as String? ?? 'IDR',
      openingBalance: (record['opening_balance'] as num?)?.toInt() ?? 0,
      openingBalanceDate: _dateFromRecord(record['opening_balance_date']),
      createdAt: _dateFromRecord(record['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromRecord(record['updated_at']) ?? DateTime.now(),
      deletedAt: _dateFromRecord(record['deleted_at']),
      version: (record['version'] as num?)?.toInt() ?? 1,
      deviceId: record['device_id'] as String? ?? 'local-device',
      syncStatus: record['sync_status'] as String? ?? 'local_only',
    );
  }

  static DateTime? _dateFromRecord(Object? value) {
    if (value is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  static String _normalizeCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    return normalized.isEmpty ? 'IDR' : normalized;
  }
}
