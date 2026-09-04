import 'document_extraction_models.dart';

abstract interface class DocumentExtractionProvider {
  Future<DocumentExtractionResult> extract(DocumentExtractionRequest request);
}

class UnavailableDocumentExtractionProvider
    implements DocumentExtractionProvider {
  const UnavailableDocumentExtractionProvider();

  @override
  Future<DocumentExtractionResult> extract(DocumentExtractionRequest request) =>
      throw const DocumentExtractionException(
        'Secure document extraction is not configured in this build.',
      );
}
