import 'package:flutter/material.dart';

import '../../../../../core/shared/formatters/thousands_formatter.dart';

class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onChanged,
    this.label = 'Amount',
    this.hintText = '0',
  });

  final ValueChanged<String> onChanged;
  final String label;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: TextInputType.number,
      inputFormatters: const [ThousandsFormatter()],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: 'Rp ',
      ),
    );
  }
}
