import 'package:uuid/uuid.dart';

import 'transaction_relation_type.dart';
import 'asset_market_reference_source.dart';

enum TransactionType { expense, income, transfer, assetConversion }

enum AssetAction { buy, sell }

enum AssetFeeTreatment {
  none,
  capitalizeIntoCostBasis,
  deductFromSaleProceeds,
  recordAsSeparateExpense,
}

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
    this.assetDefinitionId,
    this.assetName,
    this.assetSymbol,
    this.assetAction,
    this.marketReferenceUnitPrice,
    this.marketReferenceCurrencyCode,
    this.marketReferenceUnit,
    this.marketReferenceSource,
    this.marketReferenceQuotedAt,
    this.feeAmount = 0,
    AssetFeeTreatment feeTreatment = AssetFeeTreatment.none,
    this.relatedTransactionId,
    this.relationType = TransactionRelationType.none,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : feeTreatment = feeAmount == 0 ? AssetFeeTreatment.none : feeTreatment,
       id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String? projectId;

  final String title;
  final String category;
  final String account;

  final DateTime date;
  final int amount;
  final TransactionType type;

  /// Quantity bought or sold.
  ///
  /// Examples:
  /// - 20 grams of gold
  /// - 1000 stock shares
  /// - 0.05 BTC
  final double? quantity;

  /// Unit associated with [quantity].
  ///
  /// Examples: gram, share, BTC, unit.
  final String? unit;

  /// Acquisition or sale price for one quantity unit.
  final int? unitPrice;

  /// Stable identifier of the concrete asset definition.
  ///
  /// This links the transaction to market settings such as provider symbol,
  /// exchange, currency, unit, and lot size.
  ///
  /// Older transactions may have a null value and continue using their stored
  /// asset name and symbol snapshots.
  final String? assetDefinitionId;

  /// Asset account or general asset name.
  ///
  /// Examples:
  /// - Gold Holdings
  /// - Stock Portfolio
  /// - Bitcoin Wallet
  final String? assetName;

  /// Market symbol used for online prices.
  ///
  /// Examples:
  /// - BBCA
  /// - TLKM
  /// - AAPL
  ///
  /// Gold does not require this field because it uses XAU automatically.
  final String? assetSymbol;

  /// Whether an asset-conversion transaction bought or sold the asset.
  final AssetAction? assetAction;

  /// Immutable market-reference snapshot selected explicitly by the user.
  final int? marketReferenceUnitPrice;
  final String? marketReferenceCurrencyCode;
  final String? marketReferenceUnit;
  final AssetMarketReferenceSource? marketReferenceSource;
  final DateTime? marketReferenceQuotedAt;

  /// Fee charged in the same settlement currency as [amount].
  final int feeAmount;

  /// Accounting treatment applied to [feeAmount].
  final AssetFeeTreatment feeTreatment;

  /// Parent transaction for a system-managed related record.
  final String? relatedTransactionId;

  /// Purpose of the relationship represented by [relatedTransactionId].
  final TransactionRelationType relationType;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  final int version;
  final String deviceId;
  final String syncStatus;

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
    Object? assetDefinitionId = _unset,
    Object? assetName = _unset,
    Object? assetSymbol = _unset,
    Object? assetAction = _unset,
    Object? marketReferenceUnitPrice = _unset,
    Object? marketReferenceCurrencyCode = _unset,
    Object? marketReferenceUnit = _unset,
    Object? marketReferenceSource = _unset,
    Object? marketReferenceQuotedAt = _unset,
    int? feeAmount,
    AssetFeeTreatment? feeTreatment,
    Object? relatedTransactionId = _unset,
    TransactionRelationType? relationType,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    int? version,
    String? deviceId,
    String? syncStatus,
  }) {
    return Transaction(
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
      quantity: identical(quantity, _unset)
          ? this.quantity
          : quantity as double?,
      unit: identical(unit, _unset) ? this.unit : unit as String?,
      unitPrice: identical(unitPrice, _unset)
          ? this.unitPrice
          : unitPrice as int?,
      assetDefinitionId: identical(assetDefinitionId, _unset)
          ? this.assetDefinitionId
          : assetDefinitionId as String?,
      assetName: identical(assetName, _unset)
          ? this.assetName
          : assetName as String?,
      assetSymbol: identical(assetSymbol, _unset)
          ? this.assetSymbol
          : assetSymbol as String?,
      assetAction: identical(assetAction, _unset)
          ? this.assetAction
          : assetAction as AssetAction?,
      marketReferenceUnitPrice: identical(marketReferenceUnitPrice, _unset)
          ? this.marketReferenceUnitPrice
          : marketReferenceUnitPrice as int?,
      marketReferenceCurrencyCode:
          identical(marketReferenceCurrencyCode, _unset)
          ? this.marketReferenceCurrencyCode
          : marketReferenceCurrencyCode as String?,
      marketReferenceUnit: identical(marketReferenceUnit, _unset)
          ? this.marketReferenceUnit
          : marketReferenceUnit as String?,
      marketReferenceSource: identical(marketReferenceSource, _unset)
          ? this.marketReferenceSource
          : marketReferenceSource as AssetMarketReferenceSource?,
      marketReferenceQuotedAt: identical(marketReferenceQuotedAt, _unset)
          ? this.marketReferenceQuotedAt
          : marketReferenceQuotedAt as DateTime?,
      feeAmount: feeAmount ?? this.feeAmount,
      feeTreatment: feeTreatment ?? this.feeTreatment,
      relatedTransactionId: identical(relatedTransactionId, _unset)
          ? this.relatedTransactionId
          : relatedTransactionId as String?,
      relationType: relationType ?? this.relationType,
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
  }

  Map<String, Object?> toRecord() {
    return {
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
      'asset_definition_id': assetDefinitionId,
      'asset_name': assetName,
      'asset_symbol': assetSymbol,
      'asset_action': assetAction?.name,
      'market_reference_unit_price': marketReferenceUnitPrice,
      'market_reference_currency_code': marketReferenceCurrencyCode,
      'market_reference_unit': marketReferenceUnit,
      'market_reference_source': marketReferenceSource?.storedValue,
      'market_reference_quoted_at':
          marketReferenceQuotedAt?.millisecondsSinceEpoch,
      'fee_amount': feeAmount,
      'fee_treatment': feeTreatment.name,
      'related_transaction_id': relatedTransactionId,
      'relation_type': relationType.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
      'version': version,
      'device_id': deviceId,
      'sync_status': syncStatus,
    };
  }

  factory Transaction.fromRecord(Map<String, Object?> record) {
    final storedAssetAction = record['asset_action'] as String?;
    final storedFeeTreatment = record['fee_treatment'] as String?;

    return Transaction(
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
      assetDefinitionId: record['asset_definition_id'] as String?,
      assetName: record['asset_name'] as String?,
      assetSymbol: record['asset_symbol'] as String?,
      assetAction: storedAssetAction == null
          ? null
          : AssetAction.values.byName(storedAssetAction),
      marketReferenceUnitPrice: (record['market_reference_unit_price'] as num?)
          ?.toInt(),
      marketReferenceCurrencyCode:
          record['market_reference_currency_code'] as String?,
      marketReferenceUnit: record['market_reference_unit'] as String?,
      marketReferenceSource: AssetMarketReferenceSource.fromStoredValue(
        record['market_reference_source'],
      ),
      marketReferenceQuotedAt: record['market_reference_quoted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (record['market_reference_quoted_at'] as num).toInt(),
            ),
      feeAmount: (record['fee_amount'] as num?)?.toInt() ?? 0,
      feeTreatment: _readFeeTreatment(storedFeeTreatment),
      relatedTransactionId: record['related_transaction_id'] as String?,
      relationType: TransactionRelationType.fromStoredValue(
        record['relation_type'] as String?,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        record['created_at'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        record['updated_at'] as int,
      ),
      deletedAt: record['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(record['deleted_at'] as int),
      version: record['version'] as int,
      deviceId: record['device_id'] as String,
      syncStatus: record['sync_status'] as String,
    );
  }

  static AssetFeeTreatment _readFeeTreatment(String? value) {
    for (final treatment in AssetFeeTreatment.values) {
      if (treatment.name == value) {
        return treatment;
      }
    }

    return AssetFeeTreatment.none;
  }
}
