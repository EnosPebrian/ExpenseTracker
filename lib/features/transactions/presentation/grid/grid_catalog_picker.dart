import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/services/transaction_grid_policy.dart';

/// Search narrows discovery only; a catalog option must be explicitly selected.
class GridCatalogPicker extends StatefulWidget {
  const GridCatalogPicker({
    super.key,
    required this.choices,
    required this.onSelected,
    required this.onChanged,
    this.initial,
    this.label = 'New value',
    this.autofocus = false,
    this.onTab,
    this.onCancel,
    this.enabled = true,
  });
  final List<GridCatalogChoice> choices;
  final GridCatalogChoice? initial;
  final ValueChanged<GridCatalogChoice> onSelected;
  final VoidCallback onChanged;
  final String label;
  final bool autofocus;
  final ValueChanged<int>? onTab;
  final VoidCallback? onCancel;
  final bool enabled;
  @override
  State<GridCatalogPicker> createState() => _GridCatalogPickerState();
}

class _GridCatalogPickerState extends State<GridCatalogPicker> {
  late final text = TextEditingController(text: widget.initial?.label ?? '');
  final focus = FocusNode();
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<GridCatalogChoice>(
    textEditingController: text,
    focusNode: focus,
    displayStringForOption: (c) => c.label,
    optionsBuilder: (v) => widget.choices.where(
      (c) => c.label.toLowerCase().contains(v.text.toLowerCase()),
    ),
    onSelected: widget.onSelected,
    fieldViewBuilder: (context, controller, node, submit) => CallbackShortcuts(
      bindings: {
        if (widget.enabled)
          const SingleActivator(LogicalKeyboardKey.enter): submit,
        if (widget.onTab != null) ...{
          const SingleActivator(LogicalKeyboardKey.tab): () => widget.onTab!(1),
          const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
              widget.onTab!(-1),
        },
        if (widget.onCancel != null)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel!,
      },
      child: TextField(
        enabled: widget.enabled,
        key: const Key('grid-catalog-input'),
        controller: controller,
        focusNode: node,
        autofocus: widget.autofocus,
        onChanged: (_) => widget.onChanged(),
        onSubmitted: (_) => submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'Show choices',
            icon: const Icon(Icons.arrow_drop_down),
            onPressed: !widget.enabled
                ? null
                : () {
                    controller.clear();
                    widget.onChanged();
                    node.requestFocus();
                  },
          ),
        ),
      ),
    ),
    optionsViewBuilder: (context, select, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: SizedBox(
          width: 300,
          height: 220,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final choice = options.elementAt(index);
              return ListTile(
                dense: true,
                selected: AutocompleteHighlightedOption.of(context) == index,
                title: Text(choice.label),
                onTap: () => select(choice),
              );
            },
          ),
        ),
      ),
    ),
  );
}
