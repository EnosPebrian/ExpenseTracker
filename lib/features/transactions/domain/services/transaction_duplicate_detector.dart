enum TransactionCandidateClassification {
  exactIdentity,
  semanticDuplicate,
  possibleDuplicate,
  newRecord,
}

class TransactionDuplicateMatch {
  const TransactionDuplicateMatch(this.classification, {this.existingId});

  final TransactionCandidateClassification classification;
  final String? existingId;
}

/// Source-neutral duplicate analysis for backup and future reviewed ingestion.
/// Normalization is applied only to comparison copies; stored text is untouched.
class TransactionDuplicateDetector {
  const TransactionDuplicateDetector();

  TransactionDuplicateMatch classify(
    Map<String, Object?> candidate,
    Iterable<Map<String, Object?>> existing,
  ) {
    for (final row in existing) {
      if (candidate['id'] == row['id']) {
        return TransactionDuplicateMatch(
          TransactionCandidateClassification.exactIdentity,
          existingId: row['id'] as String?,
        );
      }
    }
    TransactionDuplicateMatch? possible;
    for (final row in existing.where((item) => item['deleted_at'] == null)) {
      if (!_sameDirectionAmountAccount(candidate, row)) continue;
      final dayDelta = (_day(candidate) - _day(row)).abs();
      final sameDescription =
          _normalize(candidate['title']) == _normalize(row['title']);
      final sameRelation =
          _normalize(candidate['relation_type']) ==
          _normalize(row['relation_type']);
      if (dayDelta == 0 && sameDescription && sameRelation) {
        return TransactionDuplicateMatch(
          TransactionCandidateClassification.semanticDuplicate,
          existingId: row['id'] as String?,
        );
      }
      if (dayDelta <= 3 && sameDescription) {
        possible ??= TransactionDuplicateMatch(
          TransactionCandidateClassification.possibleDuplicate,
          existingId: row['id'] as String?,
        );
      }
    }
    return possible ??
        const TransactionDuplicateMatch(
          TransactionCandidateClassification.newRecord,
        );
  }

  static bool _sameDirectionAmountAccount(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) =>
      left['transaction_type'] == right['transaction_type'] &&
      left['amount'] == right['amount'] &&
      _normalize(left['account']) == _normalize(right['account']);

  static int _day(Map<String, Object?> row) {
    final milliseconds = (row['transaction_date'] as num?)?.toInt() ?? 0;
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  static String _normalize(Object? value) => (value?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_,.;:]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
