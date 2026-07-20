import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../domain/entities/transaction.dart';
import '../controllers/transaction_controller.dart';

class TransactionDetailScreen {
  const TransactionDetailScreen._();

  static Future<void> show(
    BuildContext context, {
    required Transaction transaction,
    required TransactionController controller,
    ValueChanged<Transaction>? onEdit,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _TransactionDetailDialog(
          transaction: transaction,
          controller: controller,
          onEdit: onEdit,
        );
      },
    );
  }

  static String formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '${value.day}/${value.month}/${value.year} '
        '$hour:$minute';
  }
}

class _TransactionDetailDialog extends StatefulWidget {
  const _TransactionDetailDialog({
    required this.transaction,
    required this.controller,
    required this.onEdit,
  });

  final Transaction transaction;
  final TransactionController controller;
  final ValueChanged<Transaction>? onEdit;

  @override
  State<_TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<_TransactionDetailDialog> {
  bool deleting = false;
  String? error;

  Future<void> _delete() async {
    if (deleting) {
      return;
    }

    setState(() {
      deleting = true;
      error = null;
    });

    try {
      await widget.controller.deleteTransaction(widget.transaction);

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
    } catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        error = exception.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          deleting = false;
        });
      }
    }
  }

  void _edit() {
    final onEdit = widget.onEdit;

    if (onEdit == null || deleting) {
      return;
    }

    Navigator.pop(context);
    onEdit(widget.transaction);
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;

    return PopScope(
      canPop: !deleting,
      child: AlertDialog(
        title: Text(transaction.title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${transaction.type.name.toUpperCase()} / POSTED',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Rp ${money(transaction.amount)}',
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                _DetailLine(label: 'Account', value: transaction.account),
                _DetailLine(label: 'Category', value: transaction.category),
                _DetailLine(
                  label: 'Project',
                  value: transaction.projectId ?? 'No project',
                ),
                _DetailLine(
                  label: 'Date & time',
                  value: TransactionDetailScreen.formatDateTime(
                    transaction.date,
                  ),
                ),
                _DetailLine(label: 'Sync', value: transaction.syncStatus),
                if (transaction.type == TransactionType.assetConversion) ...[
                  _DetailLine(
                    label: 'Quantity',
                    value:
                        '${transaction.quantity ?? 0} '
                        '${transaction.unit ?? 'unit'}',
                  ),
                  _DetailLine(
                    label: 'Unit value',
                    value: 'Rp ${money(transaction.unitPrice ?? 0)}',
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECEC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xFFB42318),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: deleting
                ? null
                : () {
                    Navigator.pop(context);
                  },
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: deleting ? null : _delete,
            child: Text(deleting ? 'Deleting...' : 'Delete'),
          ),
          FilledButton(
            onPressed: widget.onEdit == null || deleting ? null : _edit,
            child: const Text('Edit transaction'),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 10)),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
