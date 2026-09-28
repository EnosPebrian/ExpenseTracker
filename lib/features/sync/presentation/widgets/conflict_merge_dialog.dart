import 'package:flutter/material.dart';
import '../../domain/conflict_merge_policy.dart';
import '../../domain/sync_models.dart';
import '../controllers/sync_conflict_controller.dart';

class ConflictMergeDialog extends StatefulWidget {
  const ConflictMergeDialog({
    super.key,
    required this.conflict,
    required this.controller,
  });
  final SyncConflict conflict;
  final SyncConflictController controller;
  @override
  State<ConflictMergeDialog> createState() => _ConflictMergeDialogState();
}

class _ConflictMergeDialogState extends State<ConflictMergeDialog> {
  final choices = <String, bool>{};
  bool busy = false;
  bool retrySaved = false;
  bool stale = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final fields = ConflictMergePolicy.fields(widget.conflict);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Merge transaction fields'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose Local or Cloud for each differing field. Identity is not editable.',
                ),
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_labels[field] ?? field),
                        SegmentedButton<bool>(
                          emptySelectionAllowed: true,
                          segments: [
                            ButtonSegment(
                              value: true,
                              label: Text(
                                'Local: ${_value(field, widget.conflict.localPayload?[field])}',
                              ),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text(
                                'Cloud: ${_value(field, widget.conflict.serverPayload?[field])}',
                              ),
                            ),
                          ],
                          selected: choices.containsKey(field)
                              ? {choices[field]!}
                              : {},
                          onSelectionChanged: busy || retrySaved || stale
                              ? null
                              : (value) => setState(() {
                                  if (value.isEmpty) {
                                    choices.remove(field);
                                  } else {
                                    choices[field] = value.single;
                                  }
                                }),
                        ),
                      ],
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy || stale || choices.length != fields.length
                ? null
                : _resolve,
            child: Text(
              retrySaved ? 'Retry saved resolution' : 'Apply reviewed merge',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve() async {
    final merged = {...?widget.conflict.serverPayload};
    for (final entry in choices.entries.where((entry) => entry.value)) {
      merged[entry.key] = widget.conflict.localPayload?[entry.key];
      if (entry.key == 'category') {
        merged['category_id'] = widget.conflict.localPayload?['category_id'];
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    final success = await widget.controller.resolve(
      widget.conflict,
      ConflictResolutionType.manualMerge,
      mergedPayload: merged,
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        busy = false;
        error = widget.controller.error;
        final current = widget.controller.conflicts
            .where((item) => item.id == widget.conflict.id)
            .firstOrNull;
        retrySaved = current?.resolutionIntent != null;
        stale = current?.serverVersion != widget.conflict.serverVersion;
        if (stale) {
          error =
              '${error ?? ''} Close and reopen review for the latest cloud values.';
        }
      });
    }
  }

  static const _labels = {
    'transaction_date': 'Date',
    'title': 'Description',
    'amount': 'Amount',
    'category': 'Category',
    'account': 'Account',
    'project_id': 'Project',
    'reference': 'Reference',
    'note': 'Note',
  };
  static String _value(String field, Object? value) {
    if (field == 'transaction_date' && value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      ).toIso8601String().split('T').first;
    }
    return value?.toString() ?? 'None';
  }
}
