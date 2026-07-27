import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/initial_sync_models.dart';
import '../domain/initial_sync_transport.dart';
import 'supabase_sync_transport.dart';

class SupabaseInitialSyncTransport implements InitialSyncTransport {
  SupabaseInitialSyncTransport(this._client);

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;
  @override
  bool get isAuthenticated => _client.auth.currentUser != null;

  @override
  Future<InitialSyncManifest> inspect(String bookId) async {
    final response = await _guard(
      () =>
          _client.rpc('get_initial_sync_status', params: {'p_book_id': bookId}),
    );
    return InitialSyncManifest.fromJson(_map(response));
  }

  @override
  Future<InitialSyncSession> beginUpload(
    InitialSyncManifest localManifest,
  ) async {
    final response = await _guard(
      () => _client.rpc(
        'begin_initial_upload',
        params: {
          'p_book_id': localManifest.bookId,
          'p_manifest': localManifest.toJson(),
        },
      ),
    );
    return _session(response);
  }

  @override
  Future<int> uploadBatch({
    required String sessionId,
    required String entityType,
    required List<Map<String, Object?>> rows,
  }) async {
    final response = await _guard(
      () => _client.rpc(
        'upload_initial_snapshot_batch',
        params: {
          'p_session_id': sessionId,
          'p_entity_type': entityType,
          'p_rows': [
            for (final row in rows)
              SupabaseSyncTransport.toRemotePayload(entityType, row),
          ],
        },
      ),
    );
    return (_map(response)['received_count'] as num).toInt();
  }

  @override
  Future<int> completeUpload(String sessionId) async {
    final response = await _guard(
      () => _client.rpc(
        'complete_initial_upload',
        params: {'p_session_id': sessionId},
      ),
    );
    return (_map(response)['final_sequence'] as num).toInt();
  }

  @override
  Future<InitialSyncSession> beginDownload(String bookId) async {
    final response = await _guard(
      () =>
          _client.rpc('begin_initial_download', params: {'p_book_id': bookId}),
    );
    return _session(response);
  }

  @override
  Future<InitialSyncBatch> downloadBatch({
    required String sessionId,
    required String entityType,
    String? afterEntityId,
    int limit = 100,
  }) async {
    final response = await _guard(
      () => _client.rpc(
        'pull_initial_snapshot_batch',
        params: {
          'p_session_id': sessionId,
          'p_entity_type': entityType,
          'p_after_entity_id': afterEntityId,
          'p_limit': limit,
        },
      ),
    );
    final body = _map(response);
    final rawRows = body['rows'] is List ? body['rows'] as List : const [];
    return InitialSyncBatch(
      entityType: entityType,
      rows: rawRows
          .whereType<Map>()
          .map(
            (row) => SupabaseSyncTransport.toLocalPayload(
              entityType,
              row.cast<String, Object?>(),
            ),
          )
          .toList(),
      nextCursor: body['next_cursor'] as String?,
      complete: body['complete'] == true,
    );
  }

  @override
  Future<void> cancel(String sessionId) => _guard(
    () =>
        _client.rpc('cancel_initial_sync', params: {'p_session_id': sessionId}),
  );

  static InitialSyncSession _session(Object? response) {
    final body = _map(response);
    return InitialSyncSession(
      id: body['session_id'] as String,
      manifest: InitialSyncManifest.fromJson(
        (body['manifest'] as Map).cast<String, Object?>(),
      ),
      direction: body['direction'] == 'upload'
          ? InitialSyncDirection.upload
          : InitialSyncDirection.download,
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    throw const InitialSyncException(
      InitialSyncErrorCode.validation,
      'The cloud service returned an invalid initialization response.',
    );
  }

  static Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AuthException {
      throw const InitialSyncException(
        InitialSyncErrorCode.signedOut,
        'Sign in is required before initial synchronization.',
      );
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('already contains') ||
          message.contains('became occupied') ||
          message.contains('already complete')) {
        throw const InitialSyncException(
          InitialSyncErrorCode.remoteOccupied,
          'The remote household already contains financial records. Download it instead.',
        );
      }
      if (message.contains('owner')) {
        throw const InitialSyncException(
          InitialSyncErrorCode.notOwner,
          'Only an active household owner can upload the initial history.',
        );
      }
      if (message.contains('incomplete')) {
        throw const InitialSyncException(
          InitialSyncErrorCode.remoteIncomplete,
          'The primary household upload has not completed yet.',
        );
      }
      if (error.code == '42501' || error.code == 'P0001') {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'Initial synchronization was rejected by the server.',
        );
      }
      throw const InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'The cloud service is temporarily unavailable.',
      );
    } on InitialSyncException {
      rethrow;
    } catch (_) {
      throw const InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'The cloud service is temporarily unavailable.',
      );
    }
  }
}
