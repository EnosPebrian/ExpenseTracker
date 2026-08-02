import 'package:flutter/material.dart';

import '../controllers/transaction_controller.dart';
import 'quick_add_controller.dart';
import 'widgets/quick_add_form.dart';

class QuickAddScreen {
  const QuickAddScreen._();

  static Future<void> show(
    BuildContext context, {
    required TransactionController transactionController,
    required QuickAddConfig config,
    VoidCallback? onAddAccount,
    VoidCallback? onAddCategory,
  }) {
    if (config.accounts.isEmpty) {
      return _showMissingSetupDialog(
        context,
        message:
            'Add an account and opening balance before recording activity.',
        actionLabel: 'Add account',
        onAction: onAddAccount,
      );
    }
    if (config.expenseCategories.isEmpty) {
      return _showMissingSetupDialog(
        context,
        message: 'Add an expense category before recording a transaction.',
        actionLabel: 'Add category',
        onAction: onAddCategory,
      );
    }
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (dialogContext) {
        return _QuickAddDialogHost(
          transactionController: transactionController,
          config: config,
        );
      },
    );
  }

  static Future<void> _showMissingSetupDialog(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback? onAction,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set up your finances'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: onAction == null
                ? null
                : () {
                    Navigator.pop(dialogContext);
                    onAction();
                  },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _QuickAddDialogHost extends StatefulWidget {
  const _QuickAddDialogHost({
    required this.transactionController,
    required this.config,
  });

  final TransactionController transactionController;
  final QuickAddConfig config;

  @override
  State<_QuickAddDialogHost> createState() => _QuickAddDialogHostState();
}

class _QuickAddDialogHostState extends State<_QuickAddDialogHost> {
  late final QuickAddController controller;

  @override
  void initState() {
    super.initState();

    controller = QuickAddController(
      transactions: widget.transactionController,
      config: widget.config,
    );
  }

  @override
  void dispose() {
    // The dialog route has now completely removed its TextFields,
    // so their TextEditingControllers are safe to dispose.
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !controller.saving,
      child: Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
          child: QuickAddForm(controller: controller),
        ),
      ),
    );
  }
}
