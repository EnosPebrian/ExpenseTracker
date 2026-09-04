import '../domain/extraction/document_extraction_models.dart';

class DocumentImportFileValidation {
  const DocumentImportFileValidation._();

  static FinancialDocumentSource validate({
    required String name,
    required List<int> bytes,
    required FinancialDocumentType type,
  }) {
    if (bytes.isEmpty) {
      throw const DocumentExtractionException('The selected file is empty.');
    }
    final mime = _mime(bytes);
    final allowed = type == FinancialDocumentType.receiptInvoice
        ? const {'image/jpeg', 'image/png', 'image/webp'}
        : const {'application/pdf', 'image/jpeg', 'image/png', 'image/webp'};
    if (mime == null || !allowed.contains(mime)) {
      throw const DocumentExtractionException(
        'Choose a supported JPEG, PNG, WebP, or statement PDF.',
      );
    }
    final max = type == FinancialDocumentType.receiptInvoice
        ? receiptDocumentMaxBytes
        : bankStatementMaxBytes;
    if (bytes.length > max) {
      throw DocumentExtractionException(
        'The selected document exceeds the ${max ~/ (1024 * 1024)} MB limit.',
      );
    }
    if (mime.startsWith('image/') && _imageDimensions(bytes, mime) == null) {
      throw const DocumentExtractionException(
        'The selected image has invalid or unsupported dimensions.',
      );
    }
    return FinancialDocumentSource(name: name, mimeType: mime, bytes: bytes);
  }

  static void validateSet(
    FinancialDocumentType type,
    List<FinancialDocumentSource> sources,
  ) {
    if (sources.isEmpty) {
      throw const DocumentExtractionException('Choose a document first.');
    }
    if (type == FinancialDocumentType.receiptInvoice && sources.length != 1) {
      throw const DocumentExtractionException(
        'Receipt extraction accepts one image at a time.',
      );
    }
    if (sources.length > bankStatementMaxPages) {
      throw const DocumentExtractionException(
        'A statement may contain at most 50 page images.',
      );
    }
    final totalBytes = sources.fold<int>(
      0,
      (total, source) => total + source.bytes.length,
    );
    final maxBytes = type == FinancialDocumentType.receiptInvoice
        ? receiptDocumentMaxBytes
        : bankStatementMaxBytes;
    if (totalBytes > maxBytes) {
      throw DocumentExtractionException(
        'The selected documents exceed the ${maxBytes ~/ (1024 * 1024)} MB session limit.',
      );
    }
    final hasPdf = sources.any(
      (source) => source.mimeType == 'application/pdf',
    );
    if (hasPdf && sources.length != 1) {
      throw const DocumentExtractionException(
        'Choose one PDF or an ordered set of page images, not both.',
      );
    }
  }

  static String? _mime(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-') {
      return 'application/pdf';
    }
    return null;
  }

  static (int, int)? _imageDimensions(List<int> bytes, String mime) {
    int u16(int offset) => bytes[offset] << 8 | bytes[offset + 1];
    int u24le(int offset) =>
        bytes[offset] | bytes[offset + 1] << 8 | bytes[offset + 2] << 16;
    int u32(int offset) =>
        bytes[offset] << 24 |
        bytes[offset + 1] << 16 |
        bytes[offset + 2] << 8 |
        bytes[offset + 3];
    if (mime == 'image/png' && bytes.length >= 24) {
      final width = u32(16);
      final height = u32(20);
      return width > 0 && height > 0 ? (width, height) : null;
    }
    if (mime == 'image/webp' && bytes.length >= 30) {
      final kind = String.fromCharCodes(bytes.skip(12).take(4));
      if (kind == 'VP8X') {
        return (u24le(24) + 1, u24le(27) + 1);
      }
      return null;
    }
    if (mime == 'image/jpeg') {
      var offset = 2;
      while (offset + 8 < bytes.length) {
        if (bytes[offset] != 0xff) {
          offset++;
          continue;
        }
        final marker = bytes[offset + 1];
        if (marker == 0xd8 || marker == 0xd9) {
          offset += 2;
          continue;
        }
        if (offset + 3 >= bytes.length) return null;
        final length = u16(offset + 2);
        if (length < 2 || offset + length + 2 > bytes.length) return null;
        if (const {
          0xc0,
          0xc1,
          0xc2,
          0xc3,
          0xc5,
          0xc6,
          0xc7,
          0xc9,
          0xca,
          0xcb,
          0xcd,
          0xce,
          0xcf,
        }.contains(marker)) {
          final height = u16(offset + 5);
          final width = u16(offset + 7);
          return width > 0 && height > 0 ? (width, height) : null;
        }
        offset += length + 2;
      }
    }
    return null;
  }
}
