import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../widgets/master_data_list.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({
    super.key,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.onSave,
    this.onManageImportRules,
  });

  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final MasterDataSaveCallback onSave;
  final VoidCallback? onManageImportRules;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            kicker: 'MASTER DATA',
            title: 'Categories',
            subtitle:
                'Maintain the categories available during transaction entry.',
          ),
          if (onManageImportRules != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.tonalIcon(
                onPressed: onManageImportRules,
                icon: const Icon(Icons.rule),
                label: const Text('Manage import rules'),
              ),
            ),
          ResponsivePair(
            left: MasterDataList(
              title: 'Expense categories',
              subtitle: '${expenseCategories.length} default categories',
              items: expenseCategories,
              itemLabel: 'expense category',
              entity: 'categories',
              categoryType: 'expense',
              onSave: onSave,
            ),
            right: MasterDataList(
              title: 'Income categories',
              subtitle: '${incomeCategories.length} default categories',
              items: incomeCategories,
              itemLabel: 'income category',
              entity: 'categories',
              categoryType: 'income',
              onSave: onSave,
            ),
          ),
        ],
      ),
    );
  }
}
