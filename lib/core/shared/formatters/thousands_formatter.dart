import 'package:flutter/services.dart';

class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return const TextEditingValue();
    }

    final parsed = int.tryParse(digits);

    if (parsed == null) {
      return oldValue;
    }

    final formatted = money(parsed);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String money(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final result = StringBuffer();

  if (negative) {
    result.write('-');
  }

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      result.write('.');
    }

    result.write(digits[index]);
  }

  return result.toString();
}
