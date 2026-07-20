import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../controllers/transaction_controller.dart';
import '../filters/transaction_filter.dart';
import '../widgets/transaction_filters.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({
    super.key,
    required this.controller,
    this.onEdit,
    this.initialDate,
  });

  final TransactionController controller;
  final ValueChanged<Transaction>? onEdit;

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
      animation: widget.controller,
      builder: (context, _) {
        final filtered = filterTransactions(
          transactions: widget.controller.transactions,
          from: from,
          to: to,
          query: query,
        );

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
              const SizedBox(height: 6),
              const Text(
                'Every movement, accounted for.',
                style: TextStyle(color: Color(0xFF92929F), fontSize: 12),
              ),
              const SizedBox(height: 28),
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
