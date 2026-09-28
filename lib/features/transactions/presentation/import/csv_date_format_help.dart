import 'package:flutter/material.dart';
import '../../domain/import/csv_date_column_policy.dart';
import '../../domain/import/csv_value_parsers.dart';
import '../../domain/import/transaction_import_models.dart';

class CsvDateFormatHelp extends StatelessWidget {
  const CsvDateFormatHelp({
    super.key,
    required this.values,
    required this.format,
  });
  final Iterable<String> values;
  final CsvDateFormat format;

  @override
  Widget build(BuildContext context) {
    final source = values.where((v) => v.trim().isNotEmpty).toList();
    if (source.isEmpty) {
      return const Text('Map a date column. ISO YYYY-MM-DD is recommended.');
    }
    final detected = format == CsvDateFormat.automatic
        ? CsvDateColumnPolicy.detect(source)
        : format;
    final candidates = detected == null
        ? CsvDateColumnPolicy.matchingFormats(source)
        : [detected];
    final examples = <String>[];
    for (final candidate in candidates) {
      for (final sample in source.take(2)) {
        try {
          final date = const CsvTransactionDateParser().parse(
            sample,
            candidate,
          );
          examples.add(
            '${CsvDateColumnPolicy.label(candidate)}: $sample → ${date.toIso8601String().split('T').first}',
          );
        } on Object {
          examples.add('Invalid date: $sample');
        }
      }
    }
    return Text(
      [
        if (detected == null)
          CsvDateColumnPolicy.issue(source)
        else
          '${format == CsvDateFormat.automatic ? 'Detected' : 'Selected'}: ${CsvDateColumnPolicy.label(detected)} for the entire import.',
        ...examples,
      ].join('\n'),
    );
  }
}
