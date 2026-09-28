import 'csv_value_parsers.dart';
import 'transaction_import_models.dart';

/// One interpretation for a complete mapped column, never a per-row guess.
class CsvDateColumnPolicy {
  const CsvDateColumnPolicy._();

  static List<CsvDateFormat> matchingFormats(Iterable<String> source) {
    final values = source
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (values.isEmpty) return const [];
    const parser = CsvTransactionDateParser();
    return const [
          CsvDateFormat.yyyyMmDd,
          CsvDateFormat.ddMmYyyySlash,
          CsvDateFormat.mmDdYyyySlash,
          CsvDateFormat.yyyyMmDdSlash,
          CsvDateFormat.ddMmYyyyDash,
          // Both named-month enum variants already share the same parser.
          CsvDateFormat.ddMmmYyyy,
        ]
        .where(
          (format) => values.every((value) {
            try {
              parser.parse(value, format);
              return true;
            } on TransactionImportException {
              return false;
            } on FormatException {
              return false;
            }
          }),
        )
        .toList();
  }

  static CsvDateFormat? detect(Iterable<String> source) {
    final candidates = matchingFormats(source);
    if (candidates.contains(CsvDateFormat.yyyyMmDd)) {
      return CsvDateFormat.yyyyMmDd;
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  static String issue(Iterable<String> source) =>
      matchingFormats(source).length > 1
      ? 'Dates are ambiguous. Choose DD/MM/YYYY or MM/DD/YYYY once for this import.'
      : 'Date column contains invalid or inconsistent dates. Correct the source dates.';

  static String label(CsvDateFormat format) => switch (format) {
    CsvDateFormat.automatic => 'Automatic (whole column)',
    CsvDateFormat.yyyyMmDd => 'YYYY-MM-DD (ISO)',
    CsvDateFormat.ddMmYyyySlash => 'DD/MM/YYYY',
    CsvDateFormat.mmDdYyyySlash => 'MM/DD/YYYY',
    CsvDateFormat.yyyyMmDdSlash => 'YYYY/MM/DD',
    CsvDateFormat.ddMmYyyyDash => 'DD-MM-YYYY',
    CsvDateFormat.ddMmmYyyy => 'DD MMM YYYY',
    CsvDateFormat.ddMmmmYyyy => 'DD MMMM YYYY',
  };
}
