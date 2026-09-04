import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/extraction/document_extraction_models.dart';
import 'document_import_file_validation.dart';

class DocumentImportFileService {
  DocumentImportFileService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<List<FinancialDocumentSource>?> pickReceipt(
    DocumentImageSource source,
  ) async {
    if (source == DocumentImageSource.files) {
      return _pickFiles(FinancialDocumentType.receiptInvoice, multiple: false);
    }
    final image = await _imagePicker.pickImage(
      source: source == DocumentImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      requestFullMetadata: true,
    );
    if (image == null) return null;
    final document = DocumentImportFileValidation.validate(
      name: image.name,
      bytes: await image.readAsBytes(),
      type: FinancialDocumentType.receiptInvoice,
    );
    return [document];
  }

  Future<List<FinancialDocumentSource>?> pickStatement({
    required bool images,
  }) => _pickFiles(
    FinancialDocumentType.bankStatement,
    multiple: images,
    pdfOnly: !images,
  );

  Future<List<FinancialDocumentSource>?> _pickFiles(
    FinancialDocumentType type, {
    required bool multiple,
    bool pdfOnly = false,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: pdfOnly
          ? const ['pdf']
          : const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: multiple,
      withData: true,
    );
    if (result == null) return null;
    final sources = <FinancialDocumentSource>[];
    for (final file in result.files) {
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const DocumentExtractionException(
          'Could not read the selected document.',
        );
      }
      sources.add(
        DocumentImportFileValidation.validate(
          name: file.name,
          bytes: bytes,
          type: type,
        ),
      );
    }
    DocumentImportFileValidation.validateSet(type, sources);
    return sources;
  }
}
