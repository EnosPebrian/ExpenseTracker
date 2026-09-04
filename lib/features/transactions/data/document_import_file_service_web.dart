import 'package:file_picker/file_picker.dart';

import '../domain/extraction/document_extraction_models.dart';
import 'document_import_file_validation.dart';

class DocumentImportFileService {
  Future<List<FinancialDocumentSource>?> pickReceipt(
    DocumentImageSource source,
  ) async {
    if (source == DocumentImageSource.camera) {
      throw const DocumentExtractionException(
        'Camera capture is available in the Android app.',
      );
    }
    return _pick(FinancialDocumentType.receiptInvoice, false, const [
      'jpg',
      'jpeg',
      'png',
      'webp',
    ]);
  }

  Future<List<FinancialDocumentSource>?> pickStatement({
    required bool images,
  }) => _pick(
    FinancialDocumentType.bankStatement,
    images,
    images ? const ['jpg', 'jpeg', 'png', 'webp'] : const ['pdf'],
  );

  Future<List<FinancialDocumentSource>?> _pick(
    FinancialDocumentType type,
    bool multiple,
    List<String> extensions,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: multiple,
      withData: true,
    );
    if (result == null) return null;
    final sources = result.files
        .map(
          (file) => DocumentImportFileValidation.validate(
            name: file.name,
            bytes: file.bytes ?? const [],
            type: type,
          ),
        )
        .toList();
    DocumentImportFileValidation.validateSet(type, sources);
    return sources;
  }
}
