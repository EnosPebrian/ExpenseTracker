import 'package:flutter/material.dart';
import '../../domain/services/transaction_grid_batch.dart';
import '../../domain/services/transaction_grid_policy.dart';

class GridBatchReview {
  static Future<bool> confirm(BuildContext context, GridEditPlan plan) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review bulk changes'),
          content: SizedBox(
            width: 650,
            height: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rows save individually, not atomically. If a save fails, earlier successes remain saved and later rows stop. Review all outcomes.',
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final error in plan.errors)
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      for (final edit in plan.edits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${edit.before.title}\n${_changes(edit)}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: plan.canApply
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text('Apply ${plan.edits.length} rows'),
            ),
          ],
        ),
      ) ??
      false;

  static String _changes(GridRowEdit edit) {
    final a = edit.before.toRecord();
    final b = edit.after.toRecord();
    return [
      for (final key in b.keys)
        if (a[key] != b[key])
          '$key: ${a[key] ?? "(empty)"} → ${b[key] ?? "(empty)"}',
    ].join('\n');
  }

  static Future<(TransactionGridField, String)?> bulkInput(
    BuildContext context,
  ) async {
    var field = TransactionGridField.category;
    var text = '';
    final result = await showDialog<(TransactionGridField, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set selected rows'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<TransactionGridField>(
                  value: field,
                  isExpanded: true,
                  items: [
                    for (final f in [
                      TransactionGridField.category,
                      TransactionGridField.account,
                      TransactionGridField.project,
                      TransactionGridField.reference,
                      TransactionGridField.note,
                    ])
                      DropdownMenuItem(value: f, child: Text(f.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => field = v);
                  },
                ),
                TextField(
                  onChanged: (value) => text = value,
                  decoration: const InputDecoration(
                    labelText: 'Existing name or text value',
                    helperText: 'Blank clears project, reference or note.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (field, text)),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
    return result;
  }
}
