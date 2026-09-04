import 'dart:collection';

enum HealthCheckItemStatus { healthy, info, warning, error }

enum HealthCheckOverallStatus { healthy, attentionNeeded, critical }

enum HealthCloudState {
  localOnly,
  ready,
  pending,
  unavailable,
  signedOut,
  notConfigured,
  initializing,
  failed,
}

class HealthCheckItem {
  const HealthCheckItem({
    required this.code,
    required this.title,
    required this.status,
    required this.summary,
    this.detail,
    this.suggestedAction,
  });

  final String code;
  final String title;
  final HealthCheckItemStatus status;
  final String summary;
  final String? detail;
  final String? suggestedAction;
}

class HealthCheckSection {
  HealthCheckSection({
    required this.id,
    required this.title,
    required List<HealthCheckItem> checks,
  }) : checks = List<HealthCheckItem>.unmodifiable(checks);

  final String id;
  final String title;
  final List<HealthCheckItem> checks;

  HealthCheckItemStatus get status => checks.fold(
    HealthCheckItemStatus.healthy,
    (result, item) => _moreSevere(result, item.status),
  );
}

class HealthCheckReport {
  HealthCheckReport({
    required this.generatedAt,
    required List<HealthCheckSection> sections,
  }) : sections = List<HealthCheckSection>.unmodifiable(sections);

  final DateTime generatedAt;
  final List<HealthCheckSection> sections;

  HealthCheckOverallStatus get overallStatus {
    final statuses = sections.map((section) => section.status);
    if (statuses.contains(HealthCheckItemStatus.error)) {
      return HealthCheckOverallStatus.critical;
    }
    if (statuses.contains(HealthCheckItemStatus.warning)) {
      return HealthCheckOverallStatus.attentionNeeded;
    }
    return HealthCheckOverallStatus.healthy;
  }

  String privacySafeSummary() {
    final lines = <String>[
      'Pilgrim Tracker Health Check',
      'Overall: ${_overallLabel(overallStatus)}',
    ];
    for (final section in sections) {
      final warnings = section.checks
          .where((item) => item.status == HealthCheckItemStatus.warning)
          .length;
      final errors = section.checks
          .where((item) => item.status == HealthCheckItemStatus.error)
          .length;
      lines.add(
        '${section.title}: ${_statusLabel(section.status)}'
        '${errors == 0 ? '' : ', $errors issue${errors == 1 ? '' : 's'}'}'
        '${warnings == 0 ? '' : ', $warnings warning${warnings == 1 ? '' : 's'}'}',
      );
    }
    return lines.join('\n');
  }

  static String _overallLabel(HealthCheckOverallStatus status) =>
      switch (status) {
        HealthCheckOverallStatus.healthy => 'Healthy',
        HealthCheckOverallStatus.attentionNeeded => 'Attention needed',
        HealthCheckOverallStatus.critical => 'Critical',
      };

  static String _statusLabel(HealthCheckItemStatus status) => switch (status) {
    HealthCheckItemStatus.healthy => 'Healthy',
    HealthCheckItemStatus.info => 'Information',
    HealthCheckItemStatus.warning => 'Attention needed',
    HealthCheckItemStatus.error => 'Critical',
  };
}

class HealthSyncSnapshot {
  const HealthSyncSnapshot({
    required this.cloudState,
    required this.pendingOutboxCount,
    required this.failedOutboxCount,
    required this.unresolvedConflictCount,
    this.lastSuccessfulSyncAt,
  });

  final HealthCloudState cloudState;
  final int pendingOutboxCount;
  final int failedOutboxCount;
  final int unresolvedConflictCount;
  final DateTime? lastSuccessfulSyncAt;
}

class HealthCheckSnapshot {
  HealthCheckSnapshot({
    required this.schemaVersion,
    required this.expectedSchemaVersion,
    required this.bookId,
    required this.backupFormatVersion,
    required this.sync,
    required Map<String, Object?> localSession,
    required Map<String, List<Map<String, Object?>>> records,
    required List<Map<String, Object?>> importSessions,
    required List<Map<String, Object?>> importDrafts,
  }) : localSession = Map<String, Object?>.unmodifiable(localSession),
       records = Map<String, List<Map<String, Object?>>>.unmodifiable({
         for (final entry in records.entries)
           entry.key: List<Map<String, Object?>>.unmodifiable(
             entry.value.map(Map<String, Object?>.unmodifiable),
           ),
       }),
       importSessions = List<Map<String, Object?>>.unmodifiable(
         importSessions.map(Map<String, Object?>.unmodifiable),
       ),
       importDrafts = List<Map<String, Object?>>.unmodifiable(
         importDrafts.map(Map<String, Object?>.unmodifiable),
       );

  final int schemaVersion;
  final int expectedSchemaVersion;
  final String bookId;
  final int backupFormatVersion;
  final HealthSyncSnapshot sync;
  final Map<String, Object?> localSession;
  final Map<String, List<Map<String, Object?>>> records;
  final List<Map<String, Object?>> importSessions;
  final List<Map<String, Object?>> importDrafts;

  List<Map<String, Object?>> rows(String key) =>
      UnmodifiableListView(records[key] ?? const []);
}

HealthCheckItemStatus _moreSevere(
  HealthCheckItemStatus left,
  HealthCheckItemStatus right,
) => left.index >= right.index ? left : right;
