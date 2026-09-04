import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:csv/csv.dart';

import '../domain/import/transaction_import_models.dart';

class CsvTransactionSourceParser {
  const CsvTransactionSourceParser();

  Future<CsvParsedSource> parse(
    SelectedCsvFile file, {
    CsvHeaderMode headerMode = CsvHeaderMode.firstRowHeaders,
  }) async {
    if (!file.name.toLowerCase().endsWith('.csv')) {
      throw const TransactionImportException('Select a .csv file.');
    }
    if (file.bytes.isEmpty) {
      throw const TransactionImportException('The CSV file is empty.');
    }
    if (file.bytes.length > csvImportMaxBytes) {
      throw const TransactionImportException(
        'The CSV file exceeds the 10 MB limit.',
      );
    }
    final String text;
    try {
      text = utf8.decode(file.bytes, allowMalformed: false);
    } on FormatException {
      throw const TransactionImportException('The CSV must use valid UTF-8.');
    }
    final normalized = text.startsWith('\uFEFF') ? text.substring(1) : text;
    if (normalized.trim().isEmpty) {
      throw const TransactionImportException('The CSV file is empty.');
    }
    _validateQuotes(normalized);
    final delimiter = _detectDelimiter(normalized);
    final decoded = Csv(
      fieldDelimiter: delimiter,
      autoDetect: false,
      skipEmptyLines: true,
      dynamicTyping: false,
    ).decode(normalized);
    if (decoded.isEmpty) {
      throw const TransactionImportException('The CSV file has no rows.');
    }
    final rows = decoded
        .map((row) => row.map((value) => value?.toString() ?? '').toList())
        .where((row) => row.any((field) => field.trim().isNotEmpty))
        .toList();
    final dataStart = headerMode == CsvHeaderMode.firstRowHeaders ? 1 : 0;
    final dataRows = rows.skip(dataStart).toList();
    if (dataRows.length > csvImportMaxRows) {
      throw const TransactionImportException(
        'The CSV exceeds the 5,000 data-row limit.',
      );
    }
    if (dataRows.isEmpty) {
      throw const TransactionImportException('The CSV has no data rows.');
    }
    final maxColumns = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (maxColumns > csvImportMaxColumns) {
      throw const TransactionImportException('The CSV has too many columns.');
    }
    for (final row in rows) {
      for (final field in row) {
        if (field.length > csvImportMaxFieldLength) {
          throw const TransactionImportException('A CSV field is too long.');
        }
      }
    }
    final headers = headerMode == CsvHeaderMode.firstRowHeaders
        ? List<String>.generate(maxColumns, (index) {
            final value = index < rows.first.length
                ? rows.first[index].trim()
                : '';
            return value.isEmpty ? 'Column ${index + 1}' : value;
          })
        : List<String>.generate(maxColumns, (index) => 'Column ${index + 1}');
    final digest = await Sha256().hash(file.bytes);
    return CsvParsedSource(
      fileName: file.name,
      fileFingerprint: digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      delimiter: delimiter,
      headers: headers,
      rows: List.generate(
        dataRows.length,
        (index) => CsvSourceRow(
          rowNumber: index + dataStart + 1,
          values: dataRows[index],
        ),
      ),
      headerMode: headerMode,
    );
  }

  static String _detectDelimiter(String text) {
    var comma = 0;
    var semicolon = 0;
    var quoted = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') {
        if (quoted && index + 1 < text.length && text[index + 1] == '"') {
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && (char == '\r' || char == '\n')) {
        break;
      } else if (!quoted && char == ',') {
        comma++;
      } else if (!quoted && char == ';') {
        semicolon++;
      }
    }
    return semicolon > comma ? ';' : ',';
  }

  static void _validateQuotes(String text) {
    var inQuotes = false;
    var atFieldStart = true;
    var afterQuote = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (inQuotes) {
        if (char == '"') {
          if (index + 1 < text.length && text[index + 1] == '"') {
            index++;
          } else {
            inQuotes = false;
            afterQuote = true;
          }
        }
        continue;
      }
      if (afterQuote) {
        if (char == ',' || char == ';') {
          afterQuote = false;
          atFieldStart = true;
        } else if (char == '\r' || char == '\n') {
          afterQuote = false;
          atFieldStart = true;
        } else {
          throw const TransactionImportException(
            'The CSV quoting is malformed.',
          );
        }
        continue;
      }
      if (char == '"') {
        if (!atFieldStart) {
          throw const TransactionImportException(
            'The CSV quoting is malformed.',
          );
        }
        inQuotes = true;
        atFieldStart = false;
      } else if (char == ',' || char == ';' || char == '\r' || char == '\n') {
        atFieldStart = true;
      } else {
        atFieldStart = false;
      }
    }
    if (inQuotes) {
      throw const TransactionImportException('The CSV has an unclosed quote.');
    }
  }
}
