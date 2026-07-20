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
  }) {
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
