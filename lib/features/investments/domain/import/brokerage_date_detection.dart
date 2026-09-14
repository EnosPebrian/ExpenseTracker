import '../../../transactions/domain/import/csv_value_parsers.dart';
import '../../../transactions/domain/import/transaction_import_models.dart';

/// Detects one format for the whole mapped column, never one guess per row.
class BrokerageDateDetection {
  const BrokerageDateDetection._();

  static CsvDateFormat? detect(Iterable<String> source) {
    final values = source
        .map((value) => value.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (values.isEmpty) return null;
    if (values.every(
      (value) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value),
    )) {
      return CsvDateFormat.yyyyMmDd;
    }
    final candidates = matchingFormats(values);
    return candidates.length == 1 ? candidates.single : null;
  }

  static List<CsvDateFormat> matchingFormats(Iterable<String> source) {
    final values = source
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (values.isEmpty) return const [];
    const parser = CsvTransactionDateParser();
    bool accepts(CsvDateFormat format) => values.every((value) {
      try {
        parser.parse(value, format);
        return true;
      } on Object {
        return false;
      }
    });
    return [
      CsvDateFormat.yyyyMmDd,
      CsvDateFormat.ddMmYyyySlash,
      CsvDateFormat.mmDdYyyySlash,
      CsvDateFormat.yyyyMmDdSlash,
    ].where(accepts).toList();
  }
}
