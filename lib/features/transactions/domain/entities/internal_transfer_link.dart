import 'package:uuid/uuid.dart';

class InternalTransferLink {
  static const _unset = Object();

  InternalTransferLink({
    String? id,
    required this.bookId,
    required this.outgoingTransactionId,
    required this.incomingTransactionId,
    required this.sourceAccountId,
    required this.destinationAccountId,
    required String currencyCode,
    required this.amount,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       currencyCode = currencyCode.trim().toUpperCase(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String bookId;
  final String outgoingTransactionId;
  final String incomingTransactionId;
  final String sourceAccountId;
  final String destinationAccountId;
  final String currencyCode;
  final int amount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  bool get isActive => deletedAt == null;

  Set<String> get transactionIds => {
    outgoingTransactionId,
    incomingTransactionId,
  };

  InternalTransferLink copyWith({
    String? id,
    String? bookId,
    String? outgoingTransactionId,
    String? incomingTransactionId,
    String? sourceAccountId,
    String? destinationAccountId,
    String? currencyCode,
    int? amount,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? version,
    String? deviceId,
    String? syncStatus,
  }) => InternalTransferLink(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    outgoingTransactionId: outgoingTransactionId ?? this.outgoingTransactionId,
    incomingTransactionId: incomingTransactionId ?? this.incomingTransactionId,
    sourceAccountId: sourceAccountId ?? this.sourceAccountId,
    destinationAccountId: destinationAccountId ?? this.destinationAccountId,
    currencyCode: currencyCode ?? this.currencyCode,
    amount: amount ?? this.amount,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    version: version ?? this.version,
    deviceId: deviceId ?? this.deviceId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'book_id': bookId,
    'outgoing_transaction_id': outgoingTransactionId,
    'incoming_transaction_id': incomingTransactionId,
    'source_account_id': sourceAccountId,
    'destination_account_id': destinationAccountId,
    'currency_code': currencyCode,
    'amount': amount,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory InternalTransferLink.fromRecord(Map<String, Object?> record) =>
      InternalTransferLink(
        id: record['id'] as String,
        bookId: record['book_id'] as String,
        outgoingTransactionId: record['outgoing_transaction_id'] as String,
        incomingTransactionId: record['incoming_transaction_id'] as String,
        sourceAccountId: record['source_account_id'] as String,
        destinationAccountId: record['destination_account_id'] as String,
        currencyCode: record['currency_code'] as String,
        amount: (record['amount'] as num).toInt(),
        createdAt: _date(record['created_at'])!,
        updatedAt: _date(record['updated_at'])!,
        deletedAt: _date(record['deleted_at']),
        version: (record['version'] as num?)?.toInt() ?? 1,
        deviceId: record['device_id'] as String? ?? 'local-device',
        syncStatus: record['sync_status'] as String? ?? 'local_only',
      );

  static DateTime? _date(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
}
