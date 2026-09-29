import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../controllers/transaction_controller.dart';
import '../filters/transaction_filter.dart';
import '../widgets/transaction_filters.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';
import '../../domain/services/transaction_grid_policy.dart';
import '../grid/transaction_grid.dart';
import '../../../sync/presentation/controllers/sync_controller.dart';

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({
    super.key,
    required this.controller,
    this.onEdit,
    this.onImportCsv,
    this.onReviewTransfers,
    this.importedTransactionIds = const {},
    this.initialDate,
    this.gridPolicy,
    this.syncController,
    this.onConflict,
  });

  final TransactionController controller;
  final ValueChanged<Transaction>? onEdit;
  final VoidCallback? onImportCsv;
  final VoidCallback? onReviewTransfers;
  final Set<String> importedTransactionIds;
  final TransactionGridPolicy? gridPolicy;
  final SyncController? syncController;
  final VoidCallback? onConflict;

  /// Primarily useful for deterministic widget tests.
  /// Production uses the current date when this is null.
  final DateTime? initialDate;

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  late DateTime from;
  late DateTime to;

  String query = '';
  bool showImportedOnly = false;

  void _changeFrom(DateTime value) {
    final range = updateTransactionFrom(selectedFrom: value, currentTo: to);

    setState(() {
      from = range.from;
      to = range.to;
    });
  }

  void _changeTo(DateTime value) {
    final range = updateTransactionTo(currentFrom: from, selectedTo: value);

    setState(() {
      from = range.from;
      to = range.to;
    });
  }

  void _resetDateRange() {
    final referenceDate = widget.initialDate ?? DateTime.now();

    setState(() {
      from = transactionMonthStart(referenceDate);
      to = transactionMonthEnd(referenceDate);
    });
  }

  @override
  void initState() {
    super.initState();

    final referenceDate = widget.initialDate ?? DateTime.now();

    from = transactionMonthStart(referenceDate);
    to = transactionMonthEnd(referenceDate);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.syncController]),
      builder: (context, _) {
        var filtered = filterTransactions(
          transactions: widget.controller.displayTransactions,
          from: from,
          to: to,
          query: query,
        );
        if (showImportedOnly && widget.importedTransactionIds.isNotEmpty) {
          filtered = filtered
              .where(
                (transaction) =>
                    widget.importedTransactionIds.contains(transaction.id),
              )
              .toList();
        }

        if (MediaQuery.sizeOf(context).width >= 1100 &&
            widget.gridPolicy != null) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Transactions',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.onReviewTransfers != null)
                      TextButton(
                        onPressed: widget.onReviewTransfers,
                        child: const Text('Review possible transfers'),
                      ),
                    if (widget.onImportCsv != null)
                      OutlinedButton(
                        onPressed: widget.onImportCsv,
                        child: const Text('Import'),
                      ),
                  ],
                ),
                TransactionFilters(
                  onSearch: (v) => setState(() => query = v),
                  from: from,
                  to: to,
                  onFromChanged: _changeFrom,
                  onToChanged: _changeTo,
                  onReset: _resetDateRange,
                ),
                if (widget.importedTransactionIds.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      selected: showImportedOnly,
                      label: Text(
                        'Current import (${widget.importedTransactionIds.length})',
                      ),
                      onSelected: (v) => setState(() => showImportedOnly = v),
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: TransactionGrid(
                    rows: filtered,
                    policy: widget.gridPolicy!,
                    onSave: widget.controller.updateTransaction,
                    readCurrent: widget.controller.transactionById,
                    onOpen: widget.onEdit,
                    onConflict: widget.onConflict,
                    syncStates:
                        widget.syncController?.transactionStates ?? const {},
                    loading: widget.controller.isLoading,
                    error: widget.controller.error,
                  ),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LEDGER',
                style: TextStyle(
                  color: Color(0xFF92929F),
                  fontSize: 9,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Transactions',
                style: TextStyle(
                  color: Color(0xFF24242F),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.onImportCsv != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.onReviewTransfers != null)
                      OutlinedButton.icon(
                        onPressed: widget.onReviewTransfers,
                        icon: const Icon(Icons.compare_arrows),
                        label: const Text('Review possible transfers'),
                      ),
                    OutlinedButton.icon(
                      onPressed: widget.onImportCsv,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                'Every movement, accounted for.',
                style: TextStyle(color: Color(0xFF92929F), fontSize: 12),
              ),
              const SizedBox(height: 28),
              if (widget.importedTransactionIds.isNotEmpty) ...[
                FilterChip(
                  selected: showImportedOnly,
                  label: Text(
                    'Current import (${widget.importedTransactionIds.length})',
                  ),
                  onSelected: (value) =>
                      setState(() => showImportedOnly = value),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      TransactionFilters(
                        onSearch: (value) {
                          setState(() {
                            query = value;
                          });
                        },
                        from: from,
                        to: to,
                        onFromChanged: _changeFrom,
                        onToChanged: _changeTo,
                        onReset: _resetDateRange,
                      ),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(36),
                          child: Text(
                            'No transactions in this date range',
                            style: TextStyle(color: Color(0xFF92929F)),
                          ),
                        )
                      else
                        for (final transaction in filtered)
                          TransactionTile(
                            transaction: transaction,
                            onTap: () {
                              TransactionDetailScreen.show(
                                context,
                                transaction: transaction,
                                controller: widget.controller,
                                onEdit: widget.onEdit,
                              );
                            },
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
