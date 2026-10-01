import 'package:flutter/material.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/transaction_grid_batch.dart';
import '../../domain/services/transaction_grid_policy.dart';
import 'grid_bulk_dialog.dart';

class GridBatchReview {
  static Future<bool> confirm(
    BuildContext context,
    GridEditPlan plan, {
    TransactionGridPolicy? policy,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review bulk changes'),
          content: SizedBox(
            width: 750,
            height: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${plan.edits.length} rows will change'),
                const Text(
                  'Rows save individually, not atomically. If a save fails, earlier successes remain saved and later rows stop. Review all outcomes.',
                ),
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
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            for (final label in [
                              'Description',
                              'Field',
                              'Old',
                              'New',
                            ])
                              DataColumn(label: Text(label)),
                          ],
                          rows: [
                            for (final edit in plan.edits)
                              for (final field in edit.values.keys)
                                DataRow(
                                  cells: [
                                    DataCell(Text(edit.before.title)),
                                    DataCell(Text(field.label)),
                                    DataCell(
                                      Text(_value(edit.before, field, policy)),
                                    ),
                                    DataCell(
                                      Text(_value(edit.after, field, policy)),
                                    ),
                                  ],
                                ),
                          ],
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

  static String _value(
    Transaction r,
    TransactionGridField f,
    TransactionGridPolicy? p,
  ) => switch (f) {
    TransactionGridField.date =>
      '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
    TransactionGridField.description => r.title,
    TransactionGridField.amount => '${r.amount}',
    TransactionGridField.category => r.category,
    TransactionGridField.account => r.account,
    TransactionGridField.project =>
      r.projectId == null
          ? '(No project)'
          : p?.projects.entries
                    .where((e) => e.value == r.projectId)
                    .firstOrNull
                    ?.key ??
                '(Unavailable project)',
    TransactionGridField.reference => r.reference ?? '(Empty)',
    TransactionGridField.note => r.note ?? '(Empty)',
    _ => 'Read only',
  };

  static Future<GridBulkInput?> bulkInput(
    BuildContext context,
    List<Transaction> rows,
    TransactionGridPolicy policy,
  ) => showDialog<GridBulkInput>(
    context: context,
    builder: (_) => GridBulkDialog(rows: rows, policy: policy),
  );
}
