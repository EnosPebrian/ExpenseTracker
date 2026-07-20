import 'package:flutter/material.dart';

import '../../../domain/entities/transaction.dart';

class TransactionTypeSelector extends StatelessWidget {
  const TransactionTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TransactionType>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: const [
          ButtonSegment<TransactionType>(
            value: TransactionType.expense,
            label: Text('Expense'),
          ),
          ButtonSegment<TransactionType>(
            value: TransactionType.income,
            label: Text('Income'),
          ),
          ButtonSegment<TransactionType>(
            value: TransactionType.transfer,
            label: Text('Transfer'),
          ),
          ButtonSegment<TransactionType>(
            value: TransactionType.assetConversion,
            label: Text('Asset'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (values) {
          onChanged(values.first);
        },
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(42)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? const Color(0xFF6C5CE7)
                : const Color(0xFFF7F8FA);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFF555461);
          }),
          side: const WidgetStatePropertyAll(BorderSide.none),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
