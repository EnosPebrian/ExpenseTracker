import 'package:uuid/uuid.dart';

enum TransactionType { expense, income, transfer, assetConversion }

class Transaction {
  static const _unset = Object();

  Transaction({
    String? id,
    this.projectId,
    required this.title,
    required this.category,
    required this.account,
    required this.date,
    required this.amount,
    required this.type,
    this.quantity,
    this.unit,
    this.unitPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String? projectId;
  final String title, category, account;
  final DateTime date;
  final int amount;
  final TransactionType type;
  final double? quantity;
  final String? unit;
  final int? unitPrice;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId, syncStatus;

  Transaction copyWith({
    String? id,
    Object? projectId = _unset,
    String? title,
    String? category,
    String? account,
    DateTime? date,
    int? amount,
    TransactionType? type,
    Object? quantity = _unset,
    Object? unit = _unset,
    Object? unitPrice = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    int? version,
    String? deviceId,
    String? syncStatus,
  }) => Transaction(
    id: id ?? this.id,
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    title: title ?? this.title,
    category: category ?? this.category,
    account: account ?? this.account,
    date: date ?? this.date,
    amount: amount ?? this.amount,
    type: type ?? this.type,
    quantity: identical(quantity, _unset) ? this.quantity : quantity as double?,
    unit: identical(unit, _unset) ? this.unit : unit as String?,
    unitPrice: identical(unitPrice, _unset)
        ? this.unitPrice
        : unitPrice as int?,
    createdAt: identical(createdAt, _unset)
        ? this.createdAt
        : createdAt as DateTime?,
    updatedAt: identical(updatedAt, _unset)
        ? this.updatedAt
        : updatedAt as DateTime?,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    version: version ?? this.version,
    deviceId: deviceId ?? this.deviceId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'project_id': projectId,
    'title': title,
    'category': category,
    'account': account,
    'transaction_date': date.millisecondsSinceEpoch,
    'amount': amount,
    'transaction_type': type.name,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory Transaction.fromRecord(Map<String, Object?> record) => Transaction(
    id: record['id'] as String,
    projectId: record['project_id'] as String?,
    title: record['title'] as String,
    category: record['category'] as String,
    account: record['account'] as String,
    date: DateTime.fromMillisecondsSinceEpoch(
      record['transaction_date'] as int,
    ),
    amount: record['amount'] as int,
    type: TransactionType.values.byName(record['transaction_type'] as String),
    quantity: (record['quantity'] as num?)?.toDouble(),
    unit: record['unit'] as String?,
    unitPrice: record['unit_price'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(record['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(record['updated_at'] as int),
    deletedAt: record['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(record['deleted_at'] as int),
    version: record['version'] as int,
    deviceId: record['device_id'] as String,
    syncStatus: record['sync_status'] as String,
  );
}
