import 'backup_models.dart';

class RestoreClassifier {
  const RestoreClassifier._();

  static RestorePreview classify({
    required Map<String, List<Map<String, Object?>>> incoming,
    required Map<String, List<Map<String, Object?>>> existing,
    required RestoreMode mode,
  }) {
    final newCounts = <String, int>{};
    final identicalCounts = <String, int>{};
    final replacementCounts = <String, int>{};
    final conflictCounts = <String, int>{};
    final invalidCounts = <String, int>{};
    final finalTotals = <String, int>{};
    final blockingErrors = <String>[];
    final details = <String>[];
    final bookId = incoming['household']?.singleOrNull?['id'];

    for (final key in portableBackupEntityKeys) {
      final current = existing[key] ?? const [];
      final currentByIdentity = <String, Map<String, Object?>>{
        for (final row in current) _identity(key, row): row,
      };
      var additions = 0;
      var validIncoming = 0;
      for (final row in incoming[key] ?? const []) {
        final identity = _identityOrNull(key, row);
        final rowBookId = key == 'household' ? row['id'] : row['book_id'];
        if (identity == null || rowBookId != bookId) {
          invalidCounts[key] = (invalidCounts[key] ?? 0) + 1;
          final message =
              '$key contains an invalid or foreign-household record.';
          blockingErrors.add(message);
          details.add(message);
          continue;
        }
        validIncoming++;
        final local = currentByIdentity[identity];
        if (local == null) {
          newCounts[key] = (newCounts[key] ?? 0) + 1;
          additions++;
        } else if (mode == RestoreMode.newHousehold) {
          conflictCounts[key] = (conflictCounts[key] ?? 0) + 1;
          final message =
              '$key record $identity already belongs to a local household.';
          blockingErrors.add(message);
          details.add(message);
        } else if (_sameRecord(local, row)) {
          identicalCounts[key] = (identicalCounts[key] ?? 0) + 1;
        } else {
          replacementCounts[key] = (replacementCounts[key] ?? 0) + 1;
          details.add('$key record $identity will replace the local record.');
        }
      }
      finalTotals[key] = mode == RestoreMode.replaceMatchingHousehold
          ? validIncoming
          : current.length + additions;
    }
    return RestorePreview(
      mode: mode,
      newByEntity: newCounts,
      identicalByEntity: identicalCounts,
      replacementByEntity: replacementCounts,
      conflictingByEntity: conflictCounts,
      invalidByEntity: invalidCounts,
      expectedFinalTotals: finalTotals,
      blockingErrors: blockingErrors,
      details: details,
    );
  }

  static String identity(String key, Map<String, Object?> row) =>
      _identityOrNull(key, row) ?? '';

  static bool sameRecord(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) => _sameRecord(left, right);

  static String _identity(String key, Map<String, Object?> row) =>
      _identityOrNull(key, row)!;

  static String? _identityOrNull(String key, Map<String, Object?> row) {
    if (key == 'manual_market_prices') {
      final bookId = row['book_id'];
      final assetKey = row['asset_key'];
      return bookId is String && assetKey is String
          ? '$bookId::$assetKey'
          : null;
    }
    final id = row['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  static bool _sameRecord(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final keys = {...left.keys, ...right.keys}..remove('_entity_type');
    for (final key in keys) {
      if (!_sameValue(left[key], right[key])) return false;
    }
    return true;
  }

  static bool _sameValue(Object? left, Object? right) {
    if (left is bool && right is num) return (left ? 1 : 0) == right;
    if (right is bool && left is num) return (right ? 1 : 0) == left;
    return left == right;
  }
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
