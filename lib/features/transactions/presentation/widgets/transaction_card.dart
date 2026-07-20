import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import 'transaction_tile.dart';

class TransactionCard extends StatelessWidget {
  const TransactionCard({
    super.key,
    required this.transactions,
    required this.onOpen,
  });
  final List<Transaction> transactions;
  final ValueChanged<Transaction> onOpen;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent transactions',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 3),
          const Text(
            'Your latest activity',
            style: TextStyle(color: Color(0xFF92929F), fontSize: 10),
          ),
          const SizedBox(height: 12),
          for (final transaction in transactions.take(4))
            TransactionTile(
              transaction: transaction,
              onTap: () => onOpen(transaction),
            ),
        ],
      ),
    ),
  );
}
