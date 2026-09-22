import '../../../transactions/domain/import/transaction_import_models.dart';

class BrokerageIdrRounding {
  const BrokerageIdrRounding({
    required this.field,
    required this.sourceValue,
    required this.roundedValue,
  });

  final String field;
  final String sourceValue;
  final int roundedValue;

  Map<String, Object?> toJson() => {
    'field': field,
    'source': sourceValue,
    'rounded': roundedValue,
  };
}

class BrokerageIdrParseResult {
  const BrokerageIdrParseResult(this.value, [this.rounding]);

  final int value;
  final BrokerageIdrRounding? rounding;
}

/// Brokerage-import-only exact parser for the accepted fractional-IDR policy.
///
/// It never uses binary floating point. Non-zero fractions are rounded to the
/// nearest rupiah using HALF_UP, with negative ties moving away from zero.
abstract final class BrokerageIdrRoundingParser {
  static BrokerageIdrParseResult parse(
    String source, {
    required String field,
    required CsvSeparator decimalSeparator,
    required CsvSeparator thousandsSeparator,
    required bool stripCurrencySymbols,
  }) {
    final original = source.trim();
    var value = original;
    if (stripCurrencySymbols) {
      value = value
          .replaceAll(
            RegExp(r'\b[A-Z]{3}\b|Rp|[$€£¥]', caseSensitive: false),
            '',
          )
          .trim();
    }
    if (value.isEmpty ||
        value.toLowerCase() == 'nan' ||
        value.toLowerCase().contains('inf')) {
      throw const TransactionImportException('The monetary value is invalid.');
    }
    var negative = false;
    if (value.startsWith('(') && value.endsWith(')')) {
      negative = true;
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.startsWith('-') || value.startsWith('+')) {
      negative = value.startsWith('-');
      value = value.substring(1);
    }
    final decimal = _character(decimalSeparator);
    final thousands = _character(thousandsSeparator);
    if (decimal != null && decimal == thousands) {
      throw const TransactionImportException('Money separators conflict.');
    }
    if (thousands != null && value.contains(thousands)) {
      final integerPart = decimal == null ? value : value.split(decimal).first;
      final grouped = RegExp('^\\d{1,3}(${RegExp.escape(thousands)}\\d{3})*\$');
      if (!grouped.hasMatch(integerPart)) {
        throw const TransactionImportException('Invalid thousands grouping.');
      }
      value = value.replaceAll(thousands, '');
    }
    if (decimal == null && RegExp(r'[.,]').hasMatch(value)) {
      throw const TransactionImportException(
        'Choose decimal and thousands separators explicitly.',
      );
    }
    final parts = decimal == null ? [value] : value.split(decimal);
    if (parts.length > 2 ||
        !RegExp(r'^\d+$').hasMatch(parts[0]) ||
        (parts.length == 2 && !RegExp(r'^\d+$').hasMatch(parts[1]))) {
      throw const TransactionImportException(
        'The monetary value is malformed.',
      );
    }
    final whole = int.parse(parts[0]);
    final fraction = parts.length == 1 ? '' : parts[1];
    final hasFraction = fraction.contains(RegExp('[1-9]'));
    var magnitude = whole;
    if (hasFraction && fraction.codeUnitAt(0) >= 53) {
      magnitude += 1;
    }
    final rounded = negative ? -magnitude : magnitude;
    return BrokerageIdrParseResult(
      rounded,
      hasFraction
          ? BrokerageIdrRounding(
              field: field,
              sourceValue: original,
              roundedValue: rounded,
            )
          : null,
    );
  }

  static String? _character(CsvSeparator value) => switch (value) {
    CsvSeparator.none => null,
    CsvSeparator.comma => ',',
    CsvSeparator.period => '.',
  };
}
