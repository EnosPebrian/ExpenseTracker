import '../../../../core/master_data/system_category.dart';
import '../../../master_data/domain/entities/account.dart';
import '../entities/transaction.dart';
import '../entities/transaction_relation_type.dart';
import '../import/csv_value_parsers.dart';
import '../import/transaction_import_models.dart';
import '../usecases/transaction_usecases.dart';

enum TransactionGridField {
  date,
  description,
  type,
  amount,
  category,
  account,
  project,
  asset,
  reference,
  note,
  sync;

  bool get editable => !{type, asset, sync}.contains(this);
  bool get catalogBacked => {category, account, project}.contains(this);
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

class GridCatalogChoice {
  const GridCatalogChoice(this.id, this.value, this.label);
  final String? id;
  final String value;
  final String label;
}

/// A strict editing boundary, not a second ledger. Saving still uses UpdateTransaction.
class TransactionGridPolicy {
  const TransactionGridPolicy({
    required this.accounts,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.projects,
  });

  final List<Account> accounts;
  final Map<String, String> expenseCategories;
  final Map<String, String> incomeCategories;
  final Map<String, String> projects;

  String? catalogProblem(List<Transaction> rows, TransactionGridField field) {
    if (field == TransactionGridField.category &&
        rows.map((r) => r.type).toSet().length > 1) {
      return 'Selected rows contain both Income and Expense transactions. '
          'Select rows of one type to bulk-change Category.';
    }
    if (choices(rows, field).isEmpty) {
      return field == TransactionGridField.account
          ? 'No account is compatible with all selected rows.'
          : 'No valid ${field.label.toLowerCase()} choices for these rows.';
    }
    return null;
  }

  /// Discovery delegates validity to the same final editing authority.
  List<GridCatalogChoice> choices(
    List<Transaction> rows,
    TransactionGridField field,
  ) {
    if (rows.isEmpty || !field.catalogBacked) return [];
    if (field == TransactionGridField.category &&
        rows.map((r) => r.type).toSet().length != 1) {
      return [];
    }
    final candidates = switch (field) {
      TransactionGridField.category => [
        for (final e
            in (rows.first.type == TransactionType.income
                    ? incomeCategories
                    : expenseCategories)
                .entries)
          GridCatalogChoice(e.value, e.key, e.key),
      ],
      TransactionGridField.account => [
        for (final a in accounts) GridCatalogChoice(a.id, a.name, a.name),
      ],
      TransactionGridField.project => [
        const GridCatalogChoice(null, '', '(No project)'),
        for (final e in projects.entries)
          GridCatalogChoice(e.value, e.key, e.key),
      ],
      _ => <GridCatalogChoice>[],
    };
    return candidates
        .where(
          (choice) => rows.every((row) {
            try {
              prepareChoice(row, field, choice);
              return true;
            } catch (_) {
              return false;
            }
          }),
        )
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  Transaction prepareChoice(
    Transaction row,
    TransactionGridField field,
    GridCatalogChoice choice,
  ) {
    final next = prepare(row, field, choice.value);
    final id = switch (field) {
      TransactionGridField.category => next.categoryId,
      TransactionGridField.project => next.projectId,
      TransactionGridField.account => _account(next.account, row.bookId).id,
      _ => throw StateError('Not a catalog field.'),
    };
    if (id != choice.id) {
      throw StateError('Catalog changed. Select the value again.');
    }
    return next;
  }

  bool canEdit(Transaction row) =>
      (row.type == TransactionType.expense ||
          row.type == TransactionType.income) &&
      row.deletedAt == null &&
      row.relatedTransactionId == null &&
      row.relationType == TransactionRelationType.none &&
      row.assetDefinitionId == null &&
      row.assetAction == null &&
      row.brokerageAccountId == null &&
      row.brokerageActivityType == null &&
      row.feeAmount == 0 &&
      !SystemCategoryIds.isTithe(
        bookId: row.bookId ?? '',
        categoryId: row.categoryId,
      );

  Transaction prepare(
    Transaction row,
    TransactionGridField field,
    String input,
  ) {
    if (!canEdit(row) || !field.editable) {
      throw TransactionValidationException(
        'Use the coordinated editor for this record.',
      );
    }
    final value = input.trim();
    Transaction next;
    switch (field) {
      case TransactionGridField.date:
        next = row.copyWith(
          date: const CsvTransactionDateParser().parse(
            value,
            CsvDateFormat.yyyyMmDd,
          ),
        );
      case TransactionGridField.description:
        next = row.copyWith(title: value);
      case TransactionGridField.amount:
        // Storage units are explicit in the grid; no currency or precision conversion.
        if (!RegExp(r'^\d+$').hasMatch(value)) {
          throw TransactionValidationException(
            'Enter a non-negative integer in account storage units.',
          );
        }
        final amount = int.tryParse(value);
        if (amount == null || amount > 9007199254740991) {
          throw TransactionValidationException(
            'Amount exceeds the exact supported integer range.',
          );
        }
        next = row.copyWith(amount: amount);
      case TransactionGridField.category:
        final catalog = row.type == TransactionType.income
            ? incomeCategories
            : expenseCategories;
        final entry = _match(catalog, value, 'category');
        if (SystemCategoryIds.isTithe(
          bookId: row.bookId ?? '',
          categoryId: entry.value,
        )) {
          throw TransactionValidationException(
            'Use Record Tithe Payment for System Tithe.',
          );
        }
        next = row.copyWith(category: entry.key, categoryId: entry.value);
      case TransactionGridField.account:
        final current = _account(row.account, row.bookId);
        final target = _account(value, row.bookId);
        if (current.currencyCode != target.currencyCode) {
          throw TransactionValidationException(
            'Account currencies must match.',
          );
        }
        if (target.accountType == AccountType.brokerage ||
            current.accountType == AccountType.brokerage) {
          throw TransactionValidationException(
            'Use the coordinated brokerage editor.',
          );
        }
        next = row.copyWith(account: target.name);
      case TransactionGridField.project:
        next = row.copyWith(
          projectId: value.isEmpty
              ? null
              : _match(projects, value, 'project').value,
        );
      case TransactionGridField.reference:
        next = row.copyWith(reference: value.isEmpty ? null : value);
      case TransactionGridField.note:
        next = row.copyWith(note: value.isEmpty ? null : value);
      default:
        throw TransactionValidationException('This field is read-only.');
    }
    validateTransaction(next);
    return next;
  }

  Account _account(String name, String? bookId) {
    final matches = accounts
        .where(
          (a) =>
              a.deletedAt == null &&
              a.bookId == bookId &&
              a.name.toLowerCase() == name.toLowerCase(),
        )
        .toList();
    if (matches.length != 1) {
      throw TransactionValidationException(
        'Choose one active, unambiguous account in this household.',
      );
    }
    return matches.single;
  }

  MapEntry<String, String> _match(
    Map<String, String> values,
    String name,
    String kind,
  ) {
    final matches = values.entries
        .where((e) => e.key.toLowerCase() == name.toLowerCase())
        .toList();
    if (matches.length != 1) {
      throw TransactionValidationException(
        'Choose an existing unambiguous $kind.',
      );
    }
    return matches.single;
  }
}
