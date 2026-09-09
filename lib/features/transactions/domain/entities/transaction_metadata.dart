abstract final class TransactionMetadataPolicy {
  static const referenceMaxLength = 256;
  static const noteMaxLength = 4000;

  static String? normalizeReference(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? normalizeNote(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static String? validationMessage({String? reference, String? note}) {
    if ((reference?.length ?? 0) > referenceMaxLength) {
      return 'Reference must be $referenceMaxLength characters or fewer.';
    }
    if ((note?.length ?? 0) > noteMaxLength) {
      return 'Note must be $noteMaxLength characters or fewer.';
    }
    return null;
  }
}
