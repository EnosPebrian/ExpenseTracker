import 'dart:convert';

/// Dependency order shared by native SQLite and the in-memory web preview.
class SyncOutboxOrder {
  const SyncOutboxOrder._();

  static int priority(String entity) => switch (entity) {
    'books' => 0,
    'household_members' => 1,
    'accounts' || 'categories' || 'projects' || 'asset_definitions' => 2,
    'transactions' => 3,
    'transfer_links' || 'brokerage_settlements' => 4,
    'import_review_sessions' => 5,
    'import_review_drafts' => 6,
    _ => 7,
  };

  static List<Map<String, Object?>> eligible(
    List<Map<String, Object?>> outstanding, {
    required int now,
    required int limit,
  }) {
    final ordered = [...outstanding]
      ..sort((a, b) {
        var result = priority(
          a['entity_type'] as String,
        ).compareTo(priority(b['entity_type'] as String));
        if (result != 0) return result;
        result = (a['base_version'] as num).compareTo(b['base_version'] as num);
        if (result != 0) return result;
        result = (a['created_at'] as num).compareTo(b['created_at'] as num);
        return result != 0
            ? result
            : (a['operation_id'] as String).compareTo(
                b['operation_id'] as String,
              );
      });
    final byIdentity = <String, List<Map<String, Object?>>>{};
    for (final row in ordered) {
      byIdentity
          .putIfAbsent('${row['entity_type']}/${row['entity_id']}', () => [])
          .add(row);
    }
    final result = <Map<String, Object?>>[];
    for (final row in ordered) {
      if (result.length >= limit.clamp(1, 50)) break;
      if (!const {'pending', 'retry'}.contains(row['status']) ||
          ((row['next_attempt_at'] as num?)?.toInt() ?? 0) > now) {
        continue;
      }
      // Never send a later local version before its predecessor is acknowledged.
      if (byIdentity['${row['entity_type']}/${row['entity_id']}']!.first !=
          row) {
        continue;
      }
      final payload = row['payload_json'] is String
          ? jsonDecode(row['payload_json'] as String) as Map
          : const {};
      final dependencies = <String>[
        if (row['entity_type'] != 'books') 'books/${row['book_id']}',
        for (final field in const {
          'owner_member_id': 'household_members',
          'entered_by_member_id': 'household_members',
          'category_id': 'categories',
          'project_id': 'projects',
          'asset_definition_id': 'asset_definitions',
          'brokerage_account_id': 'accounts',
          'source_account_id': 'accounts',
          'destination_account_id': 'accounts',
          'account_id': 'accounts',
          'session_id': 'import_review_sessions',
          'related_transaction_id': 'transactions',
          'outgoing_transaction_id': 'transactions',
          'incoming_transaction_id': 'transactions',
        }.entries)
          if (payload[field.key] != null)
            '${field.value}/${payload[field.key]}',
        if (row['entity_type'] == 'brokerage_settlements' &&
            payload['trade_ids_json'] is String)
          for (final id
              in jsonDecode(payload['trade_ids_json'] as String) as List)
            'transactions/$id',
      ];
      if (dependencies.any((id) => (byIdentity[id] ?? []).isNotEmpty)) {
        continue;
      }
      result.add(row);
    }
    return result;
  }
}
