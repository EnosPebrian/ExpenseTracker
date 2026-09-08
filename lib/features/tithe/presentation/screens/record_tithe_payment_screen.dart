import 'package:flutter/material.dart';

import '../../../../core/master_data/system_category.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/presentation/controllers/transaction_controller.dart';
import '../../../transactions/presentation/edit/transaction_form.dart';

class RecordTithePaymentScreen {
  const RecordTithePaymentScreen._();

  static Future<void> show(
    BuildContext context, {
    required String bookId,
    required String? memberId,
    required TransactionController controller,
    required TransactionFormOptions options,
    required DateTime now,
  }) {
    if (options.accounts.isEmpty) {
      throw StateError('Add an account before recording a tithe payment.');
    }
    final categoryId = SystemCategoryIds.tithe(bookId);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TransactionForm(
        transaction: Transaction(
          bookId: bookId,
          enteredByMemberId: memberId,
          title: 'Tithe payment',
          category: SystemCategoryDefinition.tithe.name,
          categoryId: categoryId,
          account: options.accounts.first,
          date: now,
          amount: 0,
          type: TransactionType.expense,
        ),
        options: options,
        title: 'Record Tithe Payment',
        submitLabel: 'Record payment',
        lockType: true,
        lockedCategoryId: categoryId,
        onSubmit: controller.createTransaction,
      ),
    );
  }
}
