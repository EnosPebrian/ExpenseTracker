import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/household_member.dart';
import '../../domain/services/account_balance_calculator.dart';
import '../widgets/account_card.dart';
import '../widgets/account_editor_dialog.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({
    super.key,
    required this.accountRecords,
    required this.transactions,
    required this.defaultCurrencyCode,
    required this.onSave,
    this.members = const [],
  });

  final List<Account> accountRecords;
  final List<Transaction> transactions;
  final String defaultCurrencyCode;
  final Future<void> Function(Account account) onSave;
  final List<HouseholdMember> members;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  static const _all = '__all__';
  static const _joint = '__joint__';
  String _ownerFilter = _all;

  List<Account> get _visibleAccounts => widget.accountRecords.where((account) {
    if (_ownerFilter == _all) return true;
    if (_ownerFilter == _joint) return account.ownerMemberId == null;
    return account.ownerMemberId == _ownerFilter;
  }).toList();

  String _ownerLabel(Account account) {
    if (account.ownerMemberId == null) return 'Joint';
    for (final member in widget.members) {
      if (member.id == account.ownerMemberId) return member.displayName;
    }
    return 'Former member';
  }

  Future<void> _edit(BuildContext context, [Account? account]) {
    return AccountEditorDialog.show(
      context,
      account: account,
      defaultCurrencyCode: widget.defaultCurrencyCode,
      transactions: widget.transactions,
      members: widget.members,
      onSave: widget.onSave,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'YOUR MONEY',
            title: 'Accounts',
            subtitle: 'A calm view of everything you own and owe.',
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Balances include each account’s starting position and '
                  'eligible transactions.',
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('create-account-button'),
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create account'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButton<String>(
            key: const Key('account-owner-filter'),
            value: _ownerFilter,
            items: [
              const DropdownMenuItem(value: _all, child: Text('All owners')),
              const DropdownMenuItem(value: _joint, child: Text('Joint')),
              for (final member in widget.members)
                DropdownMenuItem(
                  value: member.id,
                  child: Text(member.displayName),
                ),
            ],
            onChanged: (value) => setState(() => _ownerFilter = value ?? _all),
          ),
          const SizedBox(height: 14),
          if (_visibleAccounts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Create an account to begin tracking balances.'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 850
                    ? 3
                    : constraints.maxWidth > 500
                    ? 2
                    : 1;
                return GridView.builder(
                  key: const Key('accounts-grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _visibleAccounts.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: columns == 1 ? 2.1 : 1.65,
                  ),
                  itemBuilder: (context, index) {
                    final account = _visibleAccounts[index];
                    return AccountCard(
                      key: ValueKey(account.id),
                      account: account,
                      balance: AccountBalanceCalculator.calculate(
                        account: account,
                        transactions: widget.transactions,
                      ),
                      ownerLabel: _ownerLabel(account),
                      onTap: () => _edit(context, account),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}
