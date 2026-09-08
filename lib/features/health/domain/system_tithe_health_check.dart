import '../../../core/master_data/system_category.dart';
import 'health_check_models.dart';

class SystemTitheHealthCheck {
  const SystemTitheHealthCheck();

  HealthCheckItem evaluate({
    required String bookId,
    required Iterable<Map<String, Object?>> categories,
  }) {
    final definition = SystemCategoryDefinition.tithe;
    late final String id;
    try {
      id = definition.idFor(bookId);
    } on FormatException {
      return const HealthCheckItem(
        code: 'system_category_tithe_not_applicable',
        title: 'System Tithe category',
        status: HealthCheckItemStatus.healthy,
        summary:
            'System Tithe identity is not applicable to this legacy test household.',
      );
    }
    final matches = categories
        .where((row) => row['id'] == id)
        .toList(growable: false);
    if (matches.isEmpty) {
      return const HealthCheckItem(
        code: 'system_category_tithe_missing',
        title: 'System Tithe category',
        status: HealthCheckItemStatus.warning,
        summary: 'The canonical System Tithe category is missing.',
        suggestedAction: 'Close and reopen the app to retry initialization.',
      );
    }
    if (matches.length != 1 ||
        !definition.isValidRecord(matches.single, bookId)) {
      return const HealthCheckItem(
        code: 'system_category_tithe_invalid',
        title: 'System Tithe category',
        status: HealthCheckItemStatus.error,
        summary: 'The canonical System Tithe category is malformed.',
        suggestedAction:
            'Stop editing this household and contact support. Health Check does not alter records.',
      );
    }
    return const HealthCheckItem(
      code: 'system_category_tithe_valid',
      title: 'System Tithe category',
      status: HealthCheckItemStatus.healthy,
      summary: 'The canonical System Tithe category is valid and protected.',
    );
  }
}
