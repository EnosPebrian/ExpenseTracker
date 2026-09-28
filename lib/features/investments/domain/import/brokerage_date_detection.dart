import '../../../transactions/domain/import/csv_date_column_policy.dart';
import '../../../transactions/domain/import/transaction_import_models.dart';

/// Detects one format for the whole mapped column, never one guess per row.
class BrokerageDateDetection {
  const BrokerageDateDetection._();

  static CsvDateFormat? detect(Iterable<String> source) =>
      CsvDateColumnPolicy.detect(source);

  static List<CsvDateFormat> matchingFormats(Iterable<String> source) =>
      CsvDateColumnPolicy.matchingFormats(source);
}
