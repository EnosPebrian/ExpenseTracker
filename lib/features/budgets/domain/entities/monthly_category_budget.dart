import 'package:uuid/uuid.dart';

class MonthlyCategoryBudget {
  MonthlyCategoryBudget({
    String? id,
    required this.bookId,
    required this.categoryId,
    required DateTime monthStart,
    required this.limitMinor,
    required this.currencyCode,
    this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.version = 1,
    this.deviceId = 'local-device',
    this.syncStatus = 'local_only',
  }) : id = id ?? const Uuid().v4(),
       monthStart = DateTime(monthStart.year, monthStart.month),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now() {
    if (limitMinor <= 0) {
      throw ArgumentError.value(limitMinor, 'limitMinor', 'Must be positive.');
    }
    if (note != null && note!.length > 120) {
      throw ArgumentError.value(
        note,
        'note',
        'Must be 120 characters or less.',
      );
    }
  }

  final String id;
  final String bookId;
  final String categoryId;
  final DateTime monthStart;
  final int limitMinor;
  final String currencyCode;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;
  final String syncStatus;

  String get monthKey =>
      '${monthStart.year.toString().padLeft(4, '0')}-'
      '${monthStart.month.toString().padLeft(2, '0')}-01';

  MonthlyCategoryBudget copyWith({
    int? limitMinor,
    String? currencyCode,
    String? note,
    bool clearNote = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? updatedAt,
    int? version,
    String? syncStatus,
  }) => MonthlyCategoryBudget(
    id: id,
    bookId: bookId,
    categoryId: categoryId,
    monthStart: monthStart,
    limitMinor: limitMinor ?? this.limitMinor,
    currencyCode: currencyCode ?? this.currencyCode,
    note: clearNote ? null : note ?? this.note,
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
    'category_id': categoryId,
    'month_start': monthKey,
    'limit_minor': limitMinor,
    'currency_code': currencyCode,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'version': version,
    'device_id': deviceId,
    'sync_status': syncStatus,
  };

  factory MonthlyCategoryBudget.fromRecord(Map<String, Object?> record) {
    final parts = (record['month_start'] as String).split('-');
    return MonthlyCategoryBudget(
      id: record['id'] as String,
      bookId: record['book_id'] as String,
      categoryId: record['category_id'] as String,
      monthStart: DateTime(int.parse(parts[0]), int.parse(parts[1])),
      limitMinor: (record['limit_minor'] as num).toInt(),
      currencyCode: record['currency_code'] as String,
      note: record['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (record['created_at'] as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (record['updated_at'] as num).toInt(),
      ),
      deletedAt: record['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (record['deleted_at'] as num).toInt(),
            ),
      version: (record['version'] as num?)?.toInt() ?? 1,
      deviceId: record['device_id'] as String? ?? 'local-device',
      syncStatus: record['sync_status'] as String? ?? 'local_only',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthlyCategoryBudget &&
          id == other.id &&
          bookId == other.bookId &&
          categoryId == other.categoryId &&
          monthStart == other.monthStart &&
          limitMinor == other.limitMinor &&
          currencyCode == other.currencyCode &&
          note == other.note &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          deletedAt == other.deletedAt &&
          version == other.version &&
          deviceId == other.deviceId &&
          syncStatus == other.syncStatus;

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    categoryId,
    monthStart,
    limitMinor,
    currencyCode,
    note,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    deviceId,
    syncStatus,
  );
}
