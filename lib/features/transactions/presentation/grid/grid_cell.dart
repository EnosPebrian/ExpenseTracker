import 'package:flutter/material.dart';

class GridCell extends StatelessWidget {
  const GridCell({
    super.key,
    required this.width,
    required this.value,
    required this.selected,
    required this.inRange,
    required this.even,
    required this.numeric,
    required this.editing,
    required this.saving,
    required this.editor,
    required this.onSave,
    required this.onSelect,
    required this.onEdit,
  });
  final double width;
  final String value;
  final bool selected, inRange, even, numeric, editing, saving;
  final TextEditingController editor;
  final VoidCallback onSave, onSelect, onEdit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 44,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: inRange
            ? Theme.of(context).colorScheme.primaryContainer
            : even
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: .5,
        ),
      ),
      child: editing
          ? TextField(
              key: const Key('grid-editor'),
              controller: editor,
              autofocus: true,
              enabled: !saving,
              onSubmitted: (_) => onSave(),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.all(8),
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: onEdit,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => onSelect(),
                child: Tooltip(
                  message: value,
                  child: Align(
                    alignment: numeric
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}
