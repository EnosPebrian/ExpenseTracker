import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/extraction/document_extraction_models.dart';
import '../domain/extraction/document_extraction_provider.dart';

class SupabaseDocumentExtractionProvider implements DocumentExtractionProvider {
  SupabaseDocumentExtractionProvider(this._client);

  final SupabaseClient _client;

  @override
  Future<DocumentExtractionResult> extract(
    DocumentExtractionRequest request,
  ) async {
    if (_client.auth.currentSession == null) {
      throw const DocumentExtractionException(
        'Sign in to use secure document extraction. Your household does not need to be cloud-linked.',
      );
    }
    try {
      final response = await _client.functions.invoke(
        'extract-financial-document',
        body: request.toJson(),
      );
      if (response.status < 200 || response.status >= 300) {
        throw DocumentExtractionException(
          _safeStatusMessage(response.status),
          retryable: response.status == 429 || response.status >= 500,
        );
      }
      final data = response.data;
      if (data is! Map) {
        throw const DocumentExtractionException(
          'The extraction service returned an invalid response.',
        );
      }
      return DocumentExtractionResult.fromJson(data.cast<String, Object?>());
    } on DocumentExtractionException {
      rethrow;
    } on AuthException {
      throw const DocumentExtractionException(
        'Your extraction session expired. Sign in again and retry.',
      );
    } catch (_) {
      throw const DocumentExtractionException(
        'The extraction service is temporarily unavailable.',
        retryable: true,
      );
    }
  }

  static String _safeStatusMessage(int status) => switch (status) {
    401 => 'Your extraction session expired. Sign in again and retry.',
    413 => 'The selected document is too large.',
    415 => 'The selected document type is not supported.',
    422 => 'The document could not be read safely.',
    429 => 'Document extraction is busy. Wait, then retry once.',
    _ => 'The extraction service is temporarily unavailable.',
  };
}
