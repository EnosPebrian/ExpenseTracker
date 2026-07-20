import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../widgets/master_data_list.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({
    super.key,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.onSave,
  });

  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final MasterDataSaveCallback onSave;

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
