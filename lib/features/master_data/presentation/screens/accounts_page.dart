import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../widgets/account_card.dart';
import '../widgets/master_data_list.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.accounts, required this.onSave});

  final List<String> accounts;
  final MasterDataSaveCallback onSave;

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
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 850
                    ? 3
                    : constraints.maxWidth > 500
                    ? 2
                    : 1,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.8,
                children: const [
                  AccountCard(
                    'BANK ACCOUNT',
                    'Bank BCA / 9042',
                    'Rp 31.240.000',
                    true,
                  ),
                  AccountCard('E-WALLET', 'Jago / 1138', 'Rp 4.180.000', false),
                  AccountCard(
                    'GOLD HOLDINGS',
                    '20.00 gram / Rp 54m value',
                    '+Rp 4m gain',
                    false,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          MasterDataList(
            title: 'All accounts',
            subtitle: 'Used by transactions and transfers',
            items: accounts,
            itemLabel: 'account',
            entity: 'accounts',
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}
