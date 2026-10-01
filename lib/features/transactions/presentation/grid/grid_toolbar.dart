import 'package:flutter/material.dart';

class GridToolbar extends StatelessWidget {
  const GridToolbar({
    super.key,
    required this.selectedCount,
    required this.labels,
    required this.filters,
    required this.options,
    required this.onFilter,
    this.onCopy,
    this.onPaste,
    this.onBulk,
    this.onUndo,
  });
  final int selectedCount;
  final List<String> labels;
  final Map<int, String> filters;
  final Map<int, List<String>> options;
  final void Function(int, String?)? onFilter;
  final VoidCallback? onCopy, onPaste, onBulk, onUndo;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton(onPressed: onUndo, child: const Text('Undo last cell edit')),
      TextButton(onPressed: onCopy, child: const Text('Copy selection')),
      TextButton(onPressed: onPaste, child: const Text('Paste / review')),
      TextButton(
        onPressed: onBulk,
        child: Text(
          selectedCount == 1 ? 'Edit 1 row' : 'Bulk edit $selectedCount rows',
        ),
      ),
      const Text('Shift-click/Shift-arrows extend selection'),
      for (final c in options.keys)
        SizedBox(
          width: 155,
          child: DropdownButton<String>(
            key: ValueKey('grid-filter-$c'),
            isExpanded: true,
            value: filters[c],
            hint: Text(labels[c]),
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text('All ${labels[c]}'),
              ),
              for (final value in options[c]!)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    value.isEmpty ? '(None)' : value,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onFilter == null ? null : (v) => onFilter!(c, v),
          ),
        ),
    ],
  );
}
