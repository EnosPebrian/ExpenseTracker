import 'dart:convert';

import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';

enum BrokerageSettlementType {
  buySettlement,
  sellSettlement;

  static BrokerageSettlementType? parse(String value) =>
      switch (value.trim().toUpperCase().replaceAll(' ', '_')) {
        'BUY_SETTLEMENT' => buySettlement,
        'SELL_SETTLEMENT' => sellSettlement,
        _ => null,
      };

  String get sourceName =>
      this == buySettlement ? 'BUY_SETTLEMENT' : 'SELL_SETTLEMENT';
  BrokerageActivityType get tradeType => this == buySettlement
      ? BrokerageActivityType.buy
      : BrokerageActivityType.sell;
}

/// Non-financial source evidence. Never materialize this as a Transaction.
/// A set of reviewed references permits many-to-many relationships without
/// changing or allocating the authoritative trade's financial identity/value.
class BrokerageSettlement {
  BrokerageSettlement({
    required this.id,
    required this.bookId,
    required this.brokerageAccountId,
    required this.date,
    required this.type,
    required this.amount,
    required this.currencyCode,
    required this.sourceFingerprint,
    required this.sourceRowIdentity,
    required this.sourceRowFingerprint,
    required this.reference,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    Iterable<String> tradeIds = const [],
    this.version = 1,
    this.deletedAt,
    this.deviceId,
    this.syncStatus = 'pending',
  }) : tradeIds = Set.unmodifiable(tradeIds) {
    if (id.isEmpty ||
        bookId.isEmpty ||
        brokerageAccountId.isEmpty ||
        amount <= 0 ||
        currencyCode.isEmpty ||
        sourceFingerprint.isEmpty ||
        sourceRowIdentity.isEmpty ||
        sourceRowFingerprint.isEmpty ||
        this.tradeIds.any((id) => id.isEmpty)) {
      throw ArgumentError('Incomplete settlement evidence.');
    }
  }

  final String id;
  final String bookId;
  final String brokerageAccountId;
  final DateTime date;
  final BrokerageSettlementType type;
  final int amount;
  final String currencyCode;
  final String sourceFingerprint;
  final String sourceRowIdentity;
  final String sourceRowFingerprint;
  final String reference;
  final String note;
  final Set<String> tradeIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final String? deviceId;
  final String syncStatus;

  String get state => tradeIds.isEmpty ? 'unmatched' : 'reconciled';

  bool isCompatibleTrade(Transaction trade, Account account) =>
      account.id == brokerageAccountId &&
      account.bookId == bookId &&
      account.deletedAt == null &&
      account.accountType == AccountType.brokerage &&
      account.currencyCode == currencyCode &&
      trade.deletedAt == null &&
      trade.bookId == bookId &&
      trade.brokerageAccountId == brokerageAccountId &&
      trade.brokerageActivityType == type.tradeType;

  /// Requires an explicit caller review action; suggestions never call this.
  BrokerageSettlement reconcile(
    Iterable<Transaction> selectedTrades, {
    required Account account,
    required DateTime reviewedAt,
  }) {
    final selected = selectedTrades.toList();
    if (selected.any((trade) => !isCompatibleTrade(trade, account))) {
      throw StateError('Settlement links require compatible active trades.');
    }
    return BrokerageSettlement.fromRecord({
      ...toRecord(),
      'trade_ids_json': jsonEncode(
        selected.map((trade) => trade.id).toSet().toList()..sort(),
      ),
      'updated_at': reviewedAt.millisecondsSinceEpoch,
      'version': version + 1,
      'sync_status': 'pending',
    });
  }

  Map<String, Object?> toRecord() => {
    'id': id,
    'book_id': bookId,
    'brokerage_account_id': brokerageAccountId,
    'statement_date': date.millisecondsSinceEpoch,
    'settlement_type': type.sourceName,
    'amount': amount,
    'currency_code': currencyCode,
    'source_fingerprint': sourceFingerprint,
    'source_row_identity': sourceRowIdentity,
    'source_row_fingerprint': sourceRowFingerprint,
    'reference': reference,
    'note': note,
    'trade_ids_json': jsonEncode(tradeIds.toList()..sort()),
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory BrokerageSettlement.fromRecord(Map<String, Object?> row) =>
      BrokerageSettlement(
        id: row['id'] as String,
        bookId: row['book_id'] as String,
        brokerageAccountId: row['brokerage_account_id'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(
          (row['statement_date'] as num).toInt(),
        ),
        type:
            BrokerageSettlementType.parse(row['settlement_type'] as String) ??
            (throw ArgumentError('Unknown settlement type.')),
        amount: (row['amount'] as num).toInt(),
        currencyCode: row['currency_code'] as String,
        sourceFingerprint: row['source_fingerprint'] as String,
        sourceRowIdentity: row['source_row_identity'] as String,
        sourceRowFingerprint: row['source_row_fingerprint'] as String,
        reference: row['reference'] as String? ?? '',
        note: row['note'] as String? ?? '',
        tradeIds: (jsonDecode(row['trade_ids_json'] as String? ?? '[]') as List)
            .cast<String>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_at'] as num).toInt(),
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['updated_at'] as num).toInt(),
        ),
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (row['deleted_at'] as num).toInt(),
              ),
        version: (row['version'] as num?)?.toInt() ?? 1,
        deviceId: row['device_id'] as String?,
        syncStatus: row['sync_status'] as String? ?? 'synced',
      );
}
