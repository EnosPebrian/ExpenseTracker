import 'package:flutter/material.dart';

import '../../../../../core/shared/widgets/searchable_dropdown.dart';

class ContextSelectorButtons extends StatelessWidget {
  const ContextSelectorButtons({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.allOptions,
    required this.onChanged,
  });

  final String label;
  final String? selected;
  final List<String> options;
  final List<String> allOptions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF92929F), fontSize: 10),
      ),
      const SizedBox(height: 7),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final option in options)
            ChoiceChip(
              label: Text(option),
              selected: option == selected,
              onSelected: (_) => onChanged(option),
            ),
          if (allOptions.length > options.length)
            ActionChip(
              avatar: const Icon(Icons.search, size: 15),
              label: const Text('More'),
              onPressed: () async {
                final chosen = await showSearchablePicker<String>(
                  context,
                  label: label,
                  items: allOptions,
                  selectedValue: selected ?? allOptions.first,
                  idOf: (item) => item,
                  labelOf: (item) => item,
                );
                if (chosen != null) onChanged(chosen);
              },
            ),
        ],
      ),
    ],
  );
}
