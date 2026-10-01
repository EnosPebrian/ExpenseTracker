import '../entities/transaction.dart';
import 'transaction_grid_policy.dart';

class GridRowEdit {
  const GridRowEdit(
    this.before,
    this.after, {
    this.values = const {},
    this.choices = const {},
  });
  final Transaction before;
  final Transaction after;
  final Map<TransactionGridField, String> values;
  final Map<TransactionGridField, GridCatalogChoice> choices;
}

/// Undo is a new validated update, never a storage/history rewind.
class GridUndoChange {
  const GridUndoChange(this.expected, this.field, this.previousValue);
  final Transaction expected;
  final TransactionGridField field;
  final String previousValue;
  static bool supports(TransactionGridField field) => const {
    TransactionGridField.date,
    TransactionGridField.description,
    TransactionGridField.amount,
    TransactionGridField.reference,
    TransactionGridField.note,
  }.contains(field);

  Transaction prepare(Transaction? current, TransactionGridPolicy policy) {
    if (!supports(field) ||
        current == null ||
        current.id != expected.id ||
        current.version != expected.version ||
        current.updatedAt != expected.updatedAt) {
      throw StateError(
        'Cannot undo: this record changed. Review its current state.',
      );
    }
    return policy.prepare(current, field, previousValue);
  }
}

class GridEditPlan {
  const GridEditPlan(this.edits, this.errors);
  final List<GridRowEdit> edits;
  final List<String> errors;
  bool get canApply => errors.isEmpty && edits.isNotEmpty;
}

/// Validates the complete rectangle before any mutation. No writes here.
class TransactionGridBatch {
  static GridEditPlan plan({
    required List<Transaction> rows,
    required List<TransactionGridField> fields,
    required List<List<String>> values,
    required TransactionGridPolicy policy,
    Map<TransactionGridField, GridCatalogChoice> choices = const {},
  }) {
    final errors = <String>[];
    final edits = <GridRowEdit>[];
    if (values.length != rows.length || rows.isEmpty || fields.isEmpty) {
      return const GridEditPlan([], [
        'Clipboard rectangle must fit the selected rows and columns.',
      ]);
    }
    for (var r = 0; r < rows.length; r++) {
      if (values[r].length != fields.length) {
        errors.add('Row ${r + 1}: inconsistent clipboard width.');
        continue;
      }
      var candidate = rows[r];
      for (var c = 0; c < fields.length; c++) {
        try {
          candidate = choices[fields[c]] != null
              ? policy.prepareChoice(candidate, fields[c], choices[fields[c]]!)
              : policy.prepare(candidate, fields[c], values[r][c]);
        } catch (e) {
          errors.add('Row ${r + 1} (${rows[r].title}), ${fields[c].label}: $e');
        }
      }
      edits.add(
        GridRowEdit(
          rows[r],
          candidate,
          choices: choices,
          values: {
            for (var c = 0; c < fields.length; c++) fields[c]: values[r][c],
          },
        ),
      );
    }
    return GridEditPlan(edits, errors);
  }
}

class GridRowOutcome {
  const GridRowOutcome(this.id, this.message, this.saved);
  final String id;
  final String message;
  final bool saved;
}

/// Existing updates are individually durable, not an atomic multi-row update.
class GridBatchCommit {
  static Future<List<GridRowOutcome>> apply(
    GridEditPlan plan, {
    required Transaction? Function(String) current,
    required Future<void> Function(Transaction) save,
    TransactionGridPolicy Function()? currentPolicy,
  }) async {
    if (!plan.canApply) {
      throw StateError('Resolve every review error before applying.');
    }
    final results = <GridRowOutcome>[];
    var stopped = false;
    for (final edit in plan.edits) {
      if (stopped) {
        results.add(
          GridRowOutcome(
            edit.before.id,
            'Not attempted after earlier failure',
            false,
          ),
        );
        continue;
      }
      try {
        final latest = current(edit.before.id);
        if (latest == null ||
            latest.version != edit.before.version ||
            latest.updatedAt != edit.before.updatedAt) {
          throw StateError(
            'Record changed since review. Replan before saving.',
          );
        }
        var candidate = edit.after;
        if (currentPolicy != null) {
          candidate = latest;
          for (final entry in edit.values.entries) {
            final choice = edit.choices[entry.key];
            candidate = choice != null
                ? currentPolicy().prepareChoice(candidate, entry.key, choice)
                : currentPolicy().prepare(candidate, entry.key, entry.value);
          }
          final expected = edit.after.toRecord();
          if (candidate.toRecord().entries.any(
            (e) => expected[e.key] != e.value,
          )) {
            throw StateError(
              'Catalog or record changed since review. Replan before saving.',
            );
          }
        }
        await save(candidate);
        results.add(
          GridRowOutcome(
            edit.before.id,
            'Saved locally; sync status is separate',
            true,
          ),
        );
      } catch (e) {
        stopped = true;
        results.add(
          GridRowOutcome(
            edit.before.id,
            'Save failed or completion uncertain: $e. Inspect current data before retry.',
            false,
          ),
        );
      }
    }
    return results;
  }
}
