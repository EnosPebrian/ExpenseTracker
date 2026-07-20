import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/widgets/page_layout.dart';

typedef MasterDataSaveCallback =
    Future<void> Function({
      required String entity,
      required String name,
      String? previousName,
      String? categoryType,
    });

class MasterDataList extends StatefulWidget {
  const MasterDataList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.itemLabel,
    required this.entity,
    required this.onSave,
    this.categoryType,
  });

  final String title;
  final String subtitle;
  final String itemLabel;
  final String entity;
  final String? categoryType;
  final List<String> items;
  final MasterDataSaveCallback onSave;

  @override
  State<MasterDataList> createState() => _MasterDataListState();
}

class _MasterDataListState extends State<MasterDataList> {
  bool _saving = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editItem([int? index]) async {
    if (_saving) {
      return;
    }

    var draftName = index == null ? '' : widget.items[index];

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            index == null
                ? 'Add ${widget.itemLabel}'
                : 'Edit ${widget.itemLabel}',
          ),
          content: SizedBox(
            width: 380,
            child: TextFormField(
              initialValue: draftName,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (value) {
                draftName = value;
              },
              onFieldSubmitted: (value) {
                Navigator.pop(dialogContext, value.trim());
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, draftName.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final normalizedName = result.trim();

    if (normalizedName.isEmpty) {
      _showMessage('${widget.itemLabel} name cannot be empty.');
      return;
    }

    final previousName = index == null ? null : widget.items[index];

    if (previousName == normalizedName) {
      return;
    }

    final normalizedComparison = normalizedName.toLowerCase();

    final duplicateIndex = widget.items.indexWhere(
      (item) => item.trim().toLowerCase() == normalizedComparison,
    );

    if (duplicateIndex >= 0 && duplicateIndex != index) {
      _showMessage('$normalizedName already exists.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await widget.onSave(
        entity: widget.entity,
        name: normalizedName,
        previousName: previousName,
        categoryType: widget.categoryType,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });
    } catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      _showMessage('Could not save ${widget.itemLabel}. $exception');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: PanelTitle(widget.title, widget.subtitle)),
                FilledButton.icon(
                  onPressed: _saving ? null : _editItem,
                  style: FilledButton.styleFrom(backgroundColor: violet),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 16),
                  label: Text(_saving ? 'Saving' : 'Add'),
                ),
              ],
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                minHeight: 2,
                color: violet,
                backgroundColor: border,
              ),
            ],
            const SizedBox(height: 16),
            for (var index = 0; index < widget.items.length; index++)
              InkWell(
                onTap: _saving
                    ? null
                    : () {
                        _editItem(index);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1EEFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.label_outline,
                          color: violet,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          widget.items[index],
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit_outlined, color: muted, size: 16),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
