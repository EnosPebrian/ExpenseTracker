import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'transaction.dart';
import '../import/transaction_import_models.dart';

class ImportReviewDraft {
  ImportReviewDraft({
    String? id,
    required this.sessionId,
    required this.bookId,
    required this.sourceRowIdentity,
    this.sourceRowKey,
    this.deterministicTransactionId,
    this.deterministicTransactionAccountId,
    required this.sourceIndex,
    required this.transactionDate,
    required this.description,
    required this.amountMinor,
    required this.currencyCode,
    required this.transactionType,
    this.categoryName = '',
    this.categoryId,
    this.categoryProvenance = TransactionImportCategorySource.unresolved,
    this.referenceText = '',
    this.noteText = '',
    this.merchantHint = '',
    this.included = true,
    this.userEditedFields = const {},
    this.warnings = const [],
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
  final String sessionId;
  final String bookId;
  final String sourceRowIdentity;

  /// Canonical parser/extractor row key. Null only for migrated v24 drafts.
  final String? sourceRowKey;
  final String? deterministicTransactionId;
  final String? deterministicTransactionAccountId;
  final int sourceIndex;
  final DateTime transactionDate;
  final String description;
  final int amountMinor;
  final String currencyCode;
  final TransactionType transactionType;
  final String categoryName;
  final String? categoryId;
  final TransactionImportCategorySource categoryProvenance;
  final String referenceText;
  final String noteText;
  final String merchantHint;
  final bool included;
  final Set<String> userEditedFields;
  final List<String> warnings;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  Map<String, Object?> toRecord() => {
    'id': id,
    'session_id': sessionId,
    'book_id': bookId,
    'source_row_identity': sourceRowIdentity,
    'source_row_key': sourceRowKey,
    'deterministic_transaction_id': deterministicTransactionId,
    'deterministic_transaction_account_id': deterministicTransactionAccountId,
    'source_index': sourceIndex,
    'transaction_date': transactionDate.millisecondsSinceEpoch,
    'description': description,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'transaction_type': transactionType.name,
    'category_name': categoryName,
    'category_id': categoryId,
    'category_provenance': categoryProvenance.name,
    'reference_text': referenceText,
    'note_text': noteText,
    'merchant_hint': merchantHint,
    'included': included ? 1 : 0,
    'user_edited_fields_json': jsonEncode(userEditedFields.toList()..sort()),
    'warnings_json': jsonEncode(warnings),
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory ImportReviewDraft.fromRecord(
    Map<String, Object?> row,
  ) => ImportReviewDraft(
    id: row['id'] as String,
    sessionId: row['session_id'] as String,
    bookId: row['book_id'] as String,
    sourceRowIdentity: row['source_row_identity'] as String,
    sourceRowKey: row['source_row_key'] as String?,
    deterministicTransactionId: row['deterministic_transaction_id'] as String?,
    deterministicTransactionAccountId:
        row['deterministic_transaction_account_id'] as String?,
    sourceIndex: (row['source_index'] as num).toInt(),
    transactionDate: DateTime.fromMillisecondsSinceEpoch(
      (row['transaction_date'] as num).toInt(),
    ),
    description: row['description'] as String,
    amountMinor: (row['amount_minor'] as num).toInt(),
    currencyCode: row['currency_code'] as String,
    transactionType: TransactionType.values.byName(
      row['transaction_type'] as String,
    ),
    categoryName: row['category_name'] as String? ?? '',
    categoryId: row['category_id'] as String?,
    categoryProvenance: TransactionImportCategorySource.values.byName(
      row['category_provenance'] as String,
    ),
    referenceText: row['reference_text'] as String? ?? '',
    noteText: row['note_text'] as String? ?? '',
    merchantHint: row['merchant_hint'] as String? ?? '',
    included: (row['included'] as num?)?.toInt() != 0,
    userEditedFields:
        (jsonDecode(row['user_edited_fields_json'] as String? ?? '[]') as List)
            .cast<String>()
            .toSet(),
    warnings: (jsonDecode(row['warnings_json'] as String? ?? '[]') as List)
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
    deviceId: row['device_id'] as String? ?? 'local-device',
    syncStatus: row['sync_status'] as String? ?? 'local_only',
  );
}
