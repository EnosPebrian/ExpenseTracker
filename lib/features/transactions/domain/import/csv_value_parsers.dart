import 'transaction_import_models.dart';

class CsvTransactionDateParser {
  const CsvTransactionDateParser();

  DateTime parse(String source, CsvDateFormat format) {
    final value = source.trim();
    if (value.isEmpty) {
      throw const TransactionImportException('Transaction date is required.');
    }
    if (format == CsvDateFormat.automatic) {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        return _numeric(value, '-');
      }
      if (RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(value)) {
        return _numeric(value, '/');
      }
      throw const TransactionImportException(
        'Choose an explicit date format for this CSV.',
      );
    }
    return switch (format) {
      CsvDateFormat.yyyyMmDd => _numeric(value, '-'),
      CsvDateFormat.yyyyMmDdSlash => _numeric(value, '/'),
      CsvDateFormat.ddMmYyyySlash => _dayFirst(value, '/'),
      CsvDateFormat.mmDdYyyySlash => _monthFirst(value, '/'),
      CsvDateFormat.ddMmYyyyDash => _dayFirst(value, '-'),
      CsvDateFormat.ddMmmYyyy || CsvDateFormat.ddMmmmYyyy => _named(value),
      CsvDateFormat.automatic => throw StateError('unreachable'),
    };
  }

  DateTime _numeric(String value, String separator) {
    final parts = value.split(separator);
    if (parts.length != 3 || parts[0].length != 4) return _invalid();
    return _valid(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  DateTime _dayFirst(String value, String separator) {
    final parts = value.split(separator);
    if (parts.length != 3 || parts[2].length != 4) return _invalid();
    return _valid(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  }

  DateTime _monthFirst(String value, String separator) {
    final parts = value.split(separator);
    if (parts.length != 3 || parts[2].length != 4) return _invalid();
    return _valid(
      int.parse(parts[2]),
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  DateTime _named(String value) {
    final parts = value.split(RegExp(r'\s+'));
    if (parts.length != 3) return _invalid();
    const months = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    final month = months[parts[1].toLowerCase()];
    if (month == null) return _invalid();
    return _valid(int.parse(parts[2]), month, int.parse(parts[0]));
  }

  DateTime _valid(int year, int month, int day) {
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return _invalid();
    }
    return value;
  }

  Never _invalid() => throw const TransactionImportException(
    'The transaction date is invalid for the selected format.',
  );
}

class CsvMoneyParser {
  const CsvMoneyParser();

  int parse(
    String source, {
    required String currencyCode,
    required CsvSeparator decimalSeparator,
    required CsvSeparator thousandsSeparator,
    required bool stripCurrencySymbols,
    bool allowZero = false,
  }) {
    var value = source.trim();
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
    final digits = _fractionDigits(currencyCode);
    final fraction = parts.length == 1 ? '' : parts[1];
    if (fraction.length > digits) {
      throw const TransactionImportException(
        'The monetary value has too many decimal places.',
      );
    }
    final scale = _pow10(digits);
    final minor =
        int.parse(parts[0]) * scale +
        (fraction.isEmpty ? 0 : int.parse(fraction.padRight(digits, '0')));
    if (!allowZero && minor == 0) {
      throw const TransactionImportException(
        'Transaction amount must be greater than zero.',
      );
    }
    return negative ? -minor : minor;
  }

  static String? _character(CsvSeparator value) => switch (value) {
    CsvSeparator.none => null,
    CsvSeparator.comma => ',',
    CsvSeparator.period => '.',
  };

  static int _fractionDigits(String code) =>
      const {'IDR', 'JPY', 'KRW', 'VND'}.contains(code.toUpperCase()) ? 0 : 2;

  static int _pow10(int exponent) {
    var value = 1;
    for (var index = 0; index < exponent; index++) {
      value *= 10;
    }
    return value;
  }
}
