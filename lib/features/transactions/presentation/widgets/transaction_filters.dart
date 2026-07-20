import 'package:flutter/material.dart';

class TransactionFilters extends StatelessWidget {
  const TransactionFilters({
    super.key,
    required this.onSearch,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onReset,
  });

  final ValueChanged<String> onSearch;
  final DateTime from;
  final DateTime to;
  final ValueChanged<DateTime> onFromChanged;
  final ValueChanged<DateTime> onToChanged;
  final VoidCallback onReset;

  Future<void> _pick(
    BuildContext context,
    DateTime initial,
    ValueChanged<DateTime> onChanged,
  ) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
      initialDate: initial,
    );

    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            onChanged: onSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search transactions',
              isDense: true,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            _pick(context, from, onFromChanged);
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(
            'From  ${_formatDate(from)}',
            style: const TextStyle(fontSize: 10),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            _pick(context, to, onToChanged);
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(
            'To  ${_formatDate(to)}',
            style: const TextStyle(fontSize: 10),
          ),
        ),
        TextButton.icon(
          key: const Key('transaction-filter-reset'),
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded, size: 17),
          label: const Text('Reset month', style: TextStyle(fontSize: 10)),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    return '${value.day}/${value.month}/${value.year}';
  }
}
