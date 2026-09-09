import 'package:flutter/material.dart';

import '../../domain/entities/transaction.dart';

class TransactionImportCategoryResolutionPanel extends StatelessWidget {
  const TransactionImportCategoryResolutionPanel({
    super.key,
    required this.sourceCategory,
    required this.transactionType,
    required this.existingCategories,
    required this.onMap,
    required this.onCreate,
    required this.onIgnore,
    required this.canCreate,
  });

  final String sourceCategory;
  final TransactionType transactionType;
  final List<String> existingCategories;
  final ValueChanged<String> onMap;
  final Future<bool> Function(String name) onCreate;
  final VoidCallback onIgnore;
  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unknown CSV category: “$sourceCategory”',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Choose how this category should be handled.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PopupMenuButton<String>(
                enabled: existingCategories.isNotEmpty,
                tooltip: 'Map to existing category',
                onSelected: onMap,
                itemBuilder: (context) => existingCategories
                    .map(
                      (category) =>
                          PopupMenuItem(value: category, child: Text(category)),
                    )
                    .toList(),
                child: const _ActionLabel(
                  icon: Icons.compare_arrows,
                  label: 'Map to existing',
                ),
              ),
              _ActionLabel(
                icon: Icons.add_circle_outline,
                label: 'Create category',
                enabled: canCreate,
                onTap: canCreate ? () => _showCreateDialog(context) : null,
              ),
              _ActionLabel(
                icon: Icons.remove_circle_outline,
                label: 'Ignore category',
                onTap: onIgnore,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final input = TextEditingController(text: sourceCategory);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: input,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New ${transactionType.name} category',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This plans a household category. It is created only when the import commits successfully.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Plan category'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name == null || name.isEmpty) return;
    final created = await onCreate(name);
    if (!context.mounted || created) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not create the category.')),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: foreground),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: foreground)),
          ],
        ),
      ),
    );
  }
}
