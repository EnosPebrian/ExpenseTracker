import 'dart:convert';

import '../entities/transaction.dart';

enum TransactionImportCategoryResolution {
  notRequired,
  unresolved,
  mapToExisting,
  createCategory,
  ignore,
}

class TransactionImportCategoryCreation {
  const TransactionImportCategoryCreation({
    required this.id,
    required this.bookId,
    required this.name,
    required this.type,
  });

  final String id;
  final String bookId;
  final String name;
  final TransactionType type;
}

class TransactionImportCategoryReviewState {
  const TransactionImportCategoryReviewState({
    required this.resolution,
    required this.sourceCategory,
    this.plannedCategoryId,
    this.explicitMap = false,
  });

  final TransactionImportCategoryResolution resolution;
  final String sourceCategory;
  final String? plannedCategoryId;
  final bool explicitMap;
}

class TransactionImportCategoryReviewCodec {
  const TransactionImportCategoryReviewCodec._();

  static const _resolutionPrefix = 'category_resolution:';
  static const _sourcePrefix = 'category_source:';
  static const _plannedIdPrefix = 'category_planned_id:';
  static const _explicitMap = 'category_explicit_map';
  static const _legacyIgnored = 'category_ignored';

  static Set<String> encode({
    required Set<String> existingFields,
    required TransactionImportCategoryResolution resolution,
    required String sourceCategory,
    String? plannedCategoryId,
    bool explicitMap = false,
  }) {
    final result = Set<String>.of(existingFields)
      ..removeWhere(
        (field) =>
            field == _legacyIgnored ||
            field == _explicitMap ||
            field.startsWith(_resolutionPrefix) ||
            field.startsWith(_sourcePrefix) ||
            field.startsWith(_plannedIdPrefix),
      )
      ..add('$_resolutionPrefix${resolution.name}');
    if (sourceCategory.trim().isNotEmpty) {
      result.add('$_sourcePrefix${_encode(sourceCategory.trim())}');
    }
    if (resolution == TransactionImportCategoryResolution.createCategory &&
        plannedCategoryId != null) {
      result.add('$_plannedIdPrefix$plannedCategoryId');
    }
    if (resolution == TransactionImportCategoryResolution.mapToExisting &&
        explicitMap) {
      result.add(_explicitMap);
    }
    return result;
  }

  static TransactionImportCategoryReviewState decode({
    required Set<String> fields,
    required String categoryName,
    required String? categoryId,
    required String categoryProvenance,
  }) {
    final resolutionName = _value(fields, _resolutionPrefix);
    final explicitResolution = resolutionName == null
        ? null
        : TransactionImportCategoryResolution.values
              .where((value) => value.name == resolutionName)
              .firstOrNull;
    final resolution =
        explicitResolution ??
        (fields.contains(_legacyIgnored)
            ? TransactionImportCategoryResolution.ignore
            : categoryId != null
            ? TransactionImportCategoryResolution.mapToExisting
            : categoryProvenance == 'unresolved' &&
                  categoryName.trim().isNotEmpty
            ? TransactionImportCategoryResolution.unresolved
            : TransactionImportCategoryResolution.notRequired);
    final source = _value(fields, _sourcePrefix);
    return TransactionImportCategoryReviewState(
      resolution: resolution,
      sourceCategory: source == null ? categoryName : _decode(source),
      plannedCategoryId: _value(fields, _plannedIdPrefix),
      explicitMap: fields.contains(_explicitMap),
    );
  }

  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String? _value(Set<String> fields, String prefix) {
    for (final field in fields) {
      if (field.startsWith(prefix)) return field.substring(prefix.length);
    }
    return null;
  }

  static String _encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static String _decode(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64Url.decode(padded));
  }
}
