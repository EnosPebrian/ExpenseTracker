import 'package:flutter/material.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/transaction_grid_policy.dart';
import 'grid_catalog_picker.dart';

typedef GridBulkInput = (TransactionGridField, String, GridCatalogChoice?);

class GridBulkDialog extends StatefulWidget {
  const GridBulkDialog({super.key, required this.rows, required this.policy});
  final List<Transaction> rows;
  final TransactionGridPolicy policy;
  @override
  State<GridBulkDialog> createState() => _GridBulkDialogState();
}

class _GridBulkDialogState extends State<GridBulkDialog> {
  var field = TransactionGridField.category;
  GridCatalogChoice? choice;
  var text = '';
  var clear = false;
  @override
  Widget build(BuildContext context) {
    final problem = field.catalogBacked
        ? widget.policy.catalogProblem(widget.rows, field)
        : null;
    final valid =
        problem == null &&
        (field.catalogBacked
            ? choice != null
            : clear || text.trim().isNotEmpty);
    return AlertDialog(
      title: Text('${widget.rows.length} rows selected'),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<TransactionGridField>(
              initialValue: field,
              decoration: const InputDecoration(labelText: 'Field'),
              items: [
                for (final f in [
                  TransactionGridField.category,
                  TransactionGridField.account,
                  TransactionGridField.project,
                  TransactionGridField.reference,
                  TransactionGridField.note,
                ])
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    field = v;
                    choice = null;
                    text = '';
                    clear = false;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            if (problem != null)
              Text(problem)
            else if (field.catalogBacked)
              GridCatalogPicker(
                key: ValueKey(field),
                choices: widget.policy.choices(widget.rows, field),
                onSelected: (v) => setState(() => choice = v),
                onChanged: () => setState(() => choice = null),
              )
            else ...[
              TextField(
                key: ValueKey(field),
                enabled: !clear,
                decoration: InputDecoration(labelText: field.label),
                onChanged: (v) => setState(() => text = v),
              ),
              CheckboxListTile(
                title: const Text('Clear value'),
                value: clear,
                onChanged: (v) => setState(() => clear = v ?? false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, (
                  field,
                  field.catalogBacked
                      ? choice!.value
                      : clear
                      ? ''
                      : text,
                  choice,
                ))
              : null,
          child: const Text('Review'),
        ),
      ],
    );
  }
}
