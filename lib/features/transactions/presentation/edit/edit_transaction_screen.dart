import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';
import '../controllers/transaction_controller.dart';
import 'transaction_form.dart';

class EditTransactionScreen {
  const EditTransactionScreen._();

  static Future<void> show(
    BuildContext context, {
    required Transaction transaction,
    required TransactionController controller,
    required TransactionFormOptions options,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return TransactionForm(
          transaction: transaction,
          options: options,
          onSubmit: controller.updateTransaction,
        );
      },
    );
  }
}
