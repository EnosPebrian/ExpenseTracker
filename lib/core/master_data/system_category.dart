import '../identity/uuid_v5.dart';

enum SystemCategoryKey { tithe }

enum SystemCategoryMutation { rename, delete, archive, changeType }

class SystemCategoryDefinition {
  const SystemCategoryDefinition._({
    required this.key,
    required this.identityName,
    required this.name,
    required this.categoryType,
  });

  static const tithe = SystemCategoryDefinition._(
    key: SystemCategoryKey.tithe,
    identityName: 'system-category:tithe',
    name: 'Tithe',
    categoryType: 'expense',
  );

  static const values = [tithe];

  final SystemCategoryKey key;
  final String identityName;
  final String name;
  final String categoryType;

  String idFor(String bookId) => CanonicalUuidV5.generate(bookId, identityName);

  bool isValidRecord(Map<String, Object?> record, String bookId) =>
      record['id'] == idFor(bookId) &&
      record['book_id'] == bookId &&
      record['name'] == name &&
      record['category_type'] == categoryType &&
      record['deleted_at'] == null;
}

class SystemCategoryIds {
  const SystemCategoryIds._();

  static String tithe(String bookId) =>
      SystemCategoryDefinition.tithe.idFor(bookId);

  static String? tryTithe(String bookId) {
    try {
      return tithe(bookId);
    } on FormatException {
      // Legacy fixtures and data may predate UUID household identity. They
      // cannot contain the deterministic System category introduced later.
      return null;
    }
  }

  static bool isTithe({required String bookId, required String? categoryId}) {
    final systemId = tryTithe(bookId);
    return systemId != null && categoryId == systemId;
  }

  static String? remapForHousehold({
    required String sourceBookId,
    required String destinationBookId,
    required String? categoryId,
  }) {
    try {
      return categoryId == tithe(sourceBookId)
          ? tithe(destinationBookId)
          : categoryId;
    } on FormatException {
      // Legacy households may predate UUID book identity and therefore cannot
      // carry this deterministic System category.
      return categoryId;
    }
  }
}

class SystemCategoryIntegrityException implements Exception {
  const SystemCategoryIntegrityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SystemCategoryProtection {
  const SystemCategoryProtection._();

  static void rejectMutation({
    required String bookId,
    required String categoryId,
    required SystemCategoryMutation mutation,
  }) {
    if (!SystemCategoryIds.isTithe(bookId: bookId, categoryId: categoryId)) {
      return;
    }
    throw SystemCategoryIntegrityException(
      'The System Tithe category cannot be ${switch (mutation) {
        SystemCategoryMutation.rename => 'renamed',
        SystemCategoryMutation.delete => 'deleted',
        SystemCategoryMutation.archive => 'archived',
        SystemCategoryMutation.changeType => 'changed to another type',
      }}.',
    );
  }
}
