import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../domain/entities/transaction.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onTap,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == TransactionType.income;
    final transfer = transaction.type == TransactionType.transfer;
    final conversion = transaction.type == TransactionType.assetConversion;

    final iconColor = income
        ? violet
        : transfer
        ? success
        : conversion
        ? const Color(0xFFD39B38)
        : const Color(0xFFE89377);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: income
                  ? const Color(0xFFEEEAFE)
                  : transfer
                  ? const Color(0xFFE7F6EF)
                  : conversion
                  ? const Color(0xFFFFF4D9)
                  : const Color(0xFFFFF0EB),
              child: Icon(
                income
                    ? Icons.north_east
                    : transfer
                    ? Icons.swap_horiz
                    : conversion
                    ? Icons.currency_exchange
                    : Icons.south_west,
                size: 15,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${transaction.category} / ${transaction.account}',
                    style: const TextStyle(color: muted, fontSize: 9),
                  ),
                ],
              ),
            ),
            Text(
              '${income
                  ? '+ '
                  : transfer || conversion
                  ? ''
                  : '- '}Rp ${money(transaction.amount)}',
              style: TextStyle(
                color: income
                    ? success
                    : transfer || conversion
                    ? ink
                    : const Color(0xFFE28068),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
