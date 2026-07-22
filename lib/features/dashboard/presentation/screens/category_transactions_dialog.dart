import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../transactions/domain/entities/transaction.dart';

enum CategoryTransactionSort { largest, newest, oldest }

class CategoryTransactionsDialog {
  const CategoryTransactionsDialog._();

  static Future<void> show(
    BuildContext context, {
    required String category,
    required Iterable<Transaction> transactions,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required ValueChanged<Transaction> onOpen,
    Listenable? transactionChanges,
    List<Transaction> Function()? transactionsProvider,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
            child: _CategoryTransactionsContent(
              category: category,
              initialTransactions: List<Transaction>.of(transactions),
              periodStart: periodStart,
              periodEndExclusive: periodEndExclusive,
              onOpen: onOpen,
              transactionChanges: transactionChanges,
              transactionsProvider: transactionsProvider,
            ),
          ),
        );
      },
    );
  }
}

class _CategoryTransactionsContent extends StatefulWidget {
  const _CategoryTransactionsContent({
    required this.category,
    required this.initialTransactions,
    required this.periodStart,
    required this.periodEndExclusive,
    required this.onOpen,
    required this.transactionChanges,
    required this.transactionsProvider,
  });

  final String category;
  final List<Transaction> initialTransactions;
  final DateTime periodStart;
  final DateTime periodEndExclusive;
  final ValueChanged<Transaction> onOpen;
  final Listenable? transactionChanges;
  final List<Transaction> Function()? transactionsProvider;

  @override
  State<_CategoryTransactionsContent> createState() {
    return _CategoryTransactionsContentState();
  }
}

class _CategoryTransactionsContentState
    extends State<_CategoryTransactionsContent> {
  CategoryTransactionSort sort = CategoryTransactionSort.largest;

  @override
  void initState() {
    super.initState();

    widget.transactionChanges?.addListener(_onTransactionsChanged);
  }

  @override
  void didUpdateWidget(covariant _CategoryTransactionsContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.transactionChanges != widget.transactionChanges) {
      oldWidget.transactionChanges?.removeListener(_onTransactionsChanged);

      widget.transactionChanges?.addListener(_onTransactionsChanged);
    }
  }

  @override
  void dispose() {
    widget.transactionChanges?.removeListener(_onTransactionsChanged);

    super.dispose();
  }

  void _onTransactionsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<Transaction> get categoryTransactions {
    final source =
        widget.transactionsProvider?.call() ?? widget.initialTransactions;

    return source
        .where((transaction) {
          return transaction.deletedAt == null &&
              transaction.type == TransactionType.expense &&
              transaction.category == widget.category &&
              !transaction.date.isBefore(widget.periodStart) &&
              transaction.date.isBefore(widget.periodEndExclusive);
        })
        .toList(growable: false);
  }

  List<Transaction> get sortedTransactions {
    final result = List<Transaction>.of(categoryTransactions);

    switch (sort) {
      case CategoryTransactionSort.largest:
        result.sort((left, right) {
          final amountComparison = right.amount.compareTo(left.amount);

          if (amountComparison != 0) {
            return amountComparison;
          }

          return right.date.compareTo(left.date);
        });

      case CategoryTransactionSort.newest:
        result.sort((left, right) => right.date.compareTo(left.date));

      case CategoryTransactionSort.oldest:
        result.sort((left, right) => left.date.compareTo(right.date));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final transactions = sortedTransactions;

    final total = transactions.fold<int>(
      0,
      (sum, transaction) => sum + transaction.amount,
    );

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.category,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${transactions.length} transactions | '
                      'Rp ${money(total)}',
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<CategoryTransactionSort>(
            initialValue: sort,
            decoration: const InputDecoration(
              labelText: 'Sort transactions',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: CategoryTransactionSort.largest,
                child: Text('Largest amount'),
              ),
              DropdownMenuItem(
                value: CategoryTransactionSort.newest,
                child: Text('Newest first'),
              ),
              DropdownMenuItem(
                value: CategoryTransactionSort.oldest,
                child: Text('Oldest first'),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                sort = value;
              });
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: transactions.isEmpty
                ? const Center(
                    child: Text(
                      'No transactions found for this category.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  )
                : ListView.separated(
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) {
                      return const Divider(height: 1);
                    },
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        title: Text(
                          transaction.title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatDate(transaction.date)} | '
                          '${transaction.account}',
                          style: const TextStyle(color: muted, fontSize: 9),
                        ),
                        trailing: Text(
                          'Rp ${money(transaction.amount)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () {
                          // Tidak menutup category dialog.
                          // Transaction detail dibuka di atasnya.
                          widget.onOpen(transaction);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');

  final month = value.month.toString().padLeft(2, '0');

  return '$day/$month/${value.year}';
}
