import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../domain/entities/account.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.balance,
    required this.onTap,
    this.ownerLabel = 'Joint',
  });

  final Account account;
  final int balance;
  final VoidCallback onTap;
  final String ownerLabel;

  @override
  Widget build(BuildContext context) {
    final openingSummary = account.hasOpeningBalance
        ? 'Starts at ${account.currencyCode} ${money(account.openingBalance)} '
              'from ${_date(account.openingBalanceDate!)}'
        : 'No starting balance configured';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      account.accountType.label.toUpperCase(),
                      style: const TextStyle(
                        color: muted,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_outlined, color: muted, size: 16),
                ],
              ),
              const Spacer(),
              Text(
                '${account.currencyCode} ${money(balance)}',
                style: const TextStyle(
                  color: ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ownerLabel,
                style: const TextStyle(color: muted, fontSize: 9),
              ),
              const Spacer(),
              Text(
                openingSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
