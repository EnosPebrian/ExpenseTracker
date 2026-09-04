import 'package:uuid/uuid.dart';

enum TransactionImportRuleType { expense, income }

enum TransactionImportRuleMatchField {
  description,
  reference,
  merchantHint,
  descriptionOrReference,
}

enum TransactionImportRuleOperator { contains, equals, startsWith }

String normalizeImportRuleText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'^[\s.,;:!?()\[\]{}]+|[\s.,;:!?()\[\]{}]+$'), '');

class TransactionImportRule {
  TransactionImportRule({
    String? id,
    required this.bookId,
    required this.name,
    this.enabled = true,
    this.priority = 0,
    required this.transactionType,
    required this.matchField,
    required this.operator,
    required this.pattern,
    String? patternKey,
    this.accountId,
    required this.categoryId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       patternKey = patternKey ?? normalizeImportRuleText(pattern),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now() {
    if (name.trim().isEmpty || name.length > 80) {
      throw ArgumentError.value(name, 'name', 'Must contain 1–80 characters.');
    }
    if (pattern.length > 160) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        'Must not exceed 160 characters.',
      );
    }
    final meaningful = this.patternKey.replaceAll(
      RegExp(r'[\s.,;:!?()\[\]{}_\-\/\\@#\$%^&*+=|~`"<>]'),
      '',
    );
    if (meaningful.length < 3) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        'Must contain at least 3 letters or digits.',
      );
    }
  }

  final String id;
  final String bookId;
  final String name;
  final bool enabled;
  final int priority;
  final TransactionImportRuleType transactionType;
  final TransactionImportRuleMatchField matchField;
  final TransactionImportRuleOperator operator;
  final String pattern;
  final String patternKey;
  final String? accountId;
  final String categoryId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  bool get active => enabled && deletedAt == null;

  String get semanticKey => [
    bookId,
    transactionType.name,
    matchField.name,
    operator.name,
    patternKey,
    accountId ?? '',
  ].join('|');

  TransactionImportRule copyWith({
    String? name,
    bool? enabled,
    int? priority,
    TransactionImportRuleType? transactionType,
    TransactionImportRuleMatchField? matchField,
    TransactionImportRuleOperator? operator,
    String? pattern,
    String? accountId,
    bool clearAccountId = false,
    String? categoryId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? version,
    String? syncStatus,
  }) => TransactionImportRule(
    id: id,
    bookId: bookId,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    transactionType: transactionType ?? this.transactionType,
    matchField: matchField ?? this.matchField,
    operator: operator ?? this.operator,
    pattern: pattern ?? this.pattern,
    accountId: clearAccountId ? null : accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
    deviceId: deviceId,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'book_id': bookId,
    'name': name.trim(),
    'enabled': enabled ? 1 : 0,
    'priority': priority,
    'transaction_type': transactionType.name,
    'match_field': matchField.name,
    'match_operator': operator.name,
    'pattern': pattern.trim(),
    'pattern_key': patternKey,
    'account_id': accountId,
    'category_id': categoryId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory TransactionImportRule.fromRecord(Map<String, Object?> row) =>
      TransactionImportRule(
        id: row['id'] as String,
        bookId: row['book_id'] as String,
        name: row['name'] as String,
        enabled: (row['enabled'] as num).toInt() != 0,
        priority: (row['priority'] as num).toInt(),
        transactionType: TransactionImportRuleType.values.byName(
          row['transaction_type'] as String,
        ),
        matchField: TransactionImportRuleMatchField.values.byName(
          row['match_field'] as String,
        ),
        operator: TransactionImportRuleOperator.values.byName(
          row['match_operator'] as String,
        ),
        pattern: row['pattern'] as String,
        patternKey: row['pattern_key'] as String,
        accountId: row['account_id'] as String?,
        categoryId: row['category_id'] as String,
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
