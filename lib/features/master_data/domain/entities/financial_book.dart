import 'package:uuid/uuid.dart';

class FinancialBook {
  static const _unset = Object();

  FinancialBook({
    String? id,
    required String name,
    String baseCurrencyCode = 'IDR',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.remoteLinkedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       name = name.trim(),
       baseCurrencyCode = _normalizeCurrency(baseCurrencyCode),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String baseCurrencyCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? remoteLinkedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  FinancialBook copyWith({
    String? name,
    String? baseCurrencyCode,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? remoteLinkedAt = _unset,
    int? version,
    String? syncStatus,
  }) => FinancialBook(
    id: id,
    name: name ?? this.name,
    baseCurrencyCode: baseCurrencyCode ?? this.baseCurrencyCode,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    remoteLinkedAt: identical(remoteLinkedAt, _unset)
        ? this.remoteLinkedAt
        : remoteLinkedAt as DateTime?,
    version: version ?? this.version,
    deviceId: deviceId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'name': name,
    'base_currency_code': baseCurrencyCode,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'remote_linked_at': remoteLinkedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory FinancialBook.fromRecord(Map<String, Object?> record) =>
      FinancialBook(
        id: record['id'] as String,
        name: record['name'] as String,
        baseCurrencyCode: record['base_currency_code'] as String? ?? 'IDR',
        createdAt: _date(record['created_at']) ?? DateTime.now(),
        updatedAt: _date(record['updated_at']) ?? DateTime.now(),
        deletedAt: _date(record['deleted_at']),
        remoteLinkedAt: _date(record['remote_linked_at']),
        version: (record['version'] as num?)?.toInt() ?? 1,
        deviceId: record['device_id'] as String? ?? 'local-device',
        syncStatus: record['sync_status'] as String? ?? 'local_only',
      );

  static DateTime? _date(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

  static String _normalizeCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    return normalized.isEmpty ? 'IDR' : normalized;
  }
}
