import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/sync_models.dart';
import '../domain/sync_transport.dart';

class SupabaseSyncTransport
    implements SyncTransport, ConflictResolutionTransport, SyncWakeupTransport {
  SupabaseSyncTransport(this._client);

  final SupabaseClient _client;
  RealtimeChannel? _syncChannel;

  @override
  bool get isConfigured => true;

  @override
  bool get isAuthenticated => _client.auth.currentUser != null;

  @override
  Future<List<PushOperationResult>> push(
    String bookId,
    List<SyncOperation> operations,
  ) async {
    final response = await _guard(
      () => _client.rpc(
        'push_book_changes',
        params: {
          'p_book_id': bookId,
          'p_operations': [
            for (final operation in operations)
              {
                'operationId': operation.operationId,
                'entityType': operation.entityType,
                'entityId': operation.entityId,
                'operationType': operation.operationType.name,
                'baseVersion': operation.baseVersion,
                'deviceId': operation.payload?['device_id'] ?? 'local-device',
                'payload': toRemotePayload(
                  operation.entityType,
                  operation.payload ?? const {},
                ),
              },
          ],
        },
      ),
    );
    return _maps(response).map((row) {
      final storedStatus = row['status'] as String;
      return PushOperationResult(
        operationId: row['operation_id'] as String,
        status: switch (storedStatus) {
          'applied' => PushResultStatus.applied,
          'already_applied' => PushResultStatus.alreadyApplied,
          'version_conflict' => PushResultStatus.versionConflict,
          'unauthorized' => PushResultStatus.unauthorized,
          _ => PushResultStatus.validationError,
        },
        serverVersion: (row['server_version'] as num?)?.toInt(),
        serverSequence: (row['server_sequence'] as num?)?.toInt(),
        serverPayload: row['server_payload'] is Map
            ? toLocalPayload(
                row['entity_type'] as String? ?? '',
                (row['server_payload'] as Map).cast<String, Object?>(),
              )
            : null,
        errorCode: row['error_code'] as String?,
      );
    }).toList();
  }

  @override
  Future<PullBatch> pull(
    String bookId, {
    required int afterSequence,
    int limit = 100,
  }) async {
    final response = await _guard(
      () => _client.rpc(
        'pull_book_changes',
        params: {
          'p_book_id': bookId,
          'p_after_sequence': afterSequence,
          'p_limit': limit,
        },
      ),
    );
    final body = _map(response);
    final rows = _maps(body['changes']);
    final changes = rows.map((row) {
      final entityType = row['entity_type'] as String;
      return RemoteChange(
        sequence: (row['sequence'] as num).toInt(),
        entityType: entityType,
        entityId: row['entity_id'] as String,
        serverVersion: (row['server_version'] as num).toInt(),
        operationType: row['operation'] == 'delete'
            ? SyncOperationType.delete
            : SyncOperationType.upsert,
        payload: toLocalPayload(
          entityType,
          (row['snapshot'] as Map).cast<String, Object?>(),
        ),
      );
    }).toList();
    return PullBatch(
      changes: changes,
      finalSequence: (body['final_sequence'] as num?)?.toInt() ?? afterSequence,
    );
  }

  static Future<Object?> _guard(Future<Object?> Function() operation) async {
    try {
      return await operation();
    } on AuthException {
      throw const SyncTransportException(
        SyncTransportErrorKind.authentication,
        'Sign in is required before synchronization.',
      );
    } on PostgrestException catch (error) {
      final authorization = error.code == '42501' || error.code == 'P0001';
      throw SyncTransportException(
        authorization
            ? SyncTransportErrorKind.authorization
            : SyncTransportErrorKind.network,
        authorization
            ? 'Synchronization permission was denied.'
            : 'The cloud service is temporarily unavailable.',
      );
    } catch (_) {
      throw const SyncTransportException(
        SyncTransportErrorKind.network,
        'The cloud service is temporarily unavailable.',
      );
    }
  }

  @override
  Future<ConflictResolutionResult> resolveConflict({
    required SyncConflict conflict,
    required String resolutionOperationId,
    required ConflictResolutionType resolutionType,
    Map<String, Object?>? resolvedPayload,
  }) async {
    final response = _map(
      await _guard(
        () => _client.rpc(
          'resolve_sync_conflict',
          params: {
            'p_book_id': conflict.bookId,
            'p_entity_type': conflict.entityType,
            'p_entity_id': conflict.entityId,
            'p_expected_server_version': conflict.serverVersion,
            'p_resolution_operation_id': resolutionOperationId,
            'p_resolution_type': resolutionType.name,
            'p_resolved_payload': resolvedPayload == null
                ? null
                : toRemotePayload(conflict.entityType, resolvedPayload),
          },
        ),
      ),
    );
    final payload = response['canonical_snapshot'];
    return ConflictResolutionResult(
      status: response['status'] as String,
      canonicalPayload: payload is Map
          ? toLocalPayload(conflict.entityType, payload.cast<String, Object?>())
          : null,
      serverVersion: (response['server_version'] as num?)?.toInt(),
      serverSequence: (response['server_sequence'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> subscribeToBookChanges(
    String bookId,
    void Function() onWakeup,
  ) async {
    await unsubscribeFromBookChanges();
    _syncChannel = _client.channel('sync-wakeup-$bookId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'app_changes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'book_id',
          value: bookId,
        ),
        callback: (_) => onWakeup(),
      )
      ..subscribe();
  }

  @override
  Future<void> unsubscribeFromBookChanges() async {
    final channel = _syncChannel;
    _syncChannel = null;
    if (channel != null) await _client.removeChannel(channel);
  }

  static Map<String, Object?> toRemotePayload(
    String entityType,
    Map<String, Object?> payload,
  ) {
    final allowed = _remoteFields[entityType] ?? const <String>{};
    final result = <String, Object?>{};
    for (final entry in payload.entries) {
      if (!allowed.contains(entry.key)) continue;
      final value = entry.value;
      result[entry.key] = _timestampFields.contains(entry.key) && value is num
          ? DateTime.fromMillisecondsSinceEpoch(
              value.toInt(),
              isUtc: true,
            ).toIso8601String()
          : _booleanFields.contains(entry.key) && value is num
          ? value.toInt() == 1
          : value;
    }
    return result;
  }

  static Map<String, Object?> toLocalPayload(
    String entityType,
    Map<String, Object?> payload,
  ) {
    final allowed = _remoteFields[entityType] ?? const <String>{};
    final result = <String, Object?>{};
    for (final entry in payload.entries) {
      if (!allowed.contains(entry.key)) continue;
      final value = entry.value;
      result[entry.key] =
          _timestampFields.contains(entry.key) && value is String
          ? DateTime.parse(value).millisecondsSinceEpoch
          : _booleanFields.contains(entry.key) && value is bool
          ? value
                ? 1
                : 0
          : value;
    }
    result['sync_status'] = 'synced';
    return result;
  }

  static List<Map<String, Object?>> _maps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    throw const SyncTransportException(
      SyncTransportErrorKind.validation,
      'The cloud service returned an invalid sync response.',
    );
  }

  static const _timestampFields = {
    'transaction_date',
    'opening_balance_date',
    'market_reference_quoted_at',
    'created_at',
    'updated_at',
    'deleted_at',
    'completed_at',
  };

  static const _booleanFields = {
    'online_pricing_enabled',
    'enabled',
    'included',
  };

  static const Map<String, Set<String>> _remoteFields = {
    'books': {
      'id',
      'name',
      'base_currency_code',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'household_members': {
      'id',
      'book_id',
      'display_name',
      'role',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'accounts': {
      'id',
      'book_id',
      'owner_member_id',
      'name',
      'account_type',
      'currency_code',
      'opening_balance',
      'opening_balance_date',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'categories': {
      'id',
      'book_id',
      'name',
      'category_type',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'projects': {
      'id',
      'book_id',
      'name',
      'status',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'asset_definitions': {
      'id',
      'book_id',
      'display_name',
      'asset_kind',
      'symbol',
      'provider_code',
      'provider_symbol',
      'exchange_code',
      'currency_code',
      'unit',
      'lot_size',
      'online_pricing_enabled',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'transactions': {
      'id',
      'book_id',
      'entered_by_member_id',
      'project_id',
      'title',
      'category',
      'account',
      'transaction_date',
      'amount',
      'transaction_type',
      'quantity',
      'unit',
      'unit_price',
      'asset_definition_id',
      'asset_name',
      'asset_symbol',
      'asset_action',
      'fee_amount',
      'fee_treatment',
      'related_transaction_id',
      'relation_type',
      'market_reference_unit_price',
      'market_reference_currency_code',
      'market_reference_unit',
      'market_reference_source',
      'market_reference_quoted_at',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'transfer_links': {
      'id',
      'book_id',
      'outgoing_transaction_id',
      'incoming_transaction_id',
      'source_account_id',
      'destination_account_id',
      'currency_code',
      'amount',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'monthly_category_budgets': {
      'id',
      'book_id',
      'category_id',
      'month_start',
      'limit_minor',
      'currency_code',
      'note',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'transaction_import_rules': {
      'id',
      'book_id',
      'name',
      'enabled',
      'priority',
      'transaction_type',
      'match_field',
      'match_operator',
      'pattern',
      'pattern_key',
      'account_id',
      'category_id',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'import_review_sessions': {
      'id',
      'book_id',
      'source_type',
      'title',
      'source_fingerprint',
      'destination_account_id',
      'state',
      'created_by_member_id',
      'summary_json',
      'created_at',
      'updated_at',
      'completed_at',
      'deleted_at',
      'version',
      'device_id',
    },
    'import_review_drafts': {
      'id',
      'session_id',
      'book_id',
      'source_row_identity',
      'source_row_key',
      'deterministic_transaction_id',
      'deterministic_transaction_account_id',
      'source_index',
      'transaction_date',
      'description',
      'amount_minor',
      'currency_code',
      'transaction_type',
      'category_name',
      'category_id',
      'category_provenance',
      'reference_text',
      'note_text',
      'merchant_hint',
      'included',
      'user_edited_fields_json',
      'warnings_json',
      'created_at',
      'updated_at',
      'deleted_at',
      'version',
      'device_id',
    },
  };
}
