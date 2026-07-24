import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../controllers/asset_definition_controller.dart';
import '../../domain/entities/asset_definition.dart';
import '../formatters/asset_quantity_formatter.dart';
import '../widgets/asset_definition_editor_dialog.dart';
import '../widgets/asset_definition_lifecycle_panel.dart';

class AssetManagementScreen extends StatelessWidget {
  const AssetManagementScreen({super.key, required this.controller});

  final AssetDefinitionController controller;

  static Future<void> show(
    BuildContext context, {
    required AssetDefinitionController controller,
  }) async {
    await controller.reload();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AssetManagementScreen(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage assets')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeading(
                  kicker: 'ASSET DIRECTORY',
                  title: 'Manage assets',
                  subtitle:
                      'Create concrete assets with their ticker, market, '
                      'currency, unit, and lot size.',
                ),
                const SizedBox(height: 14),
                _AssetManagementToolbar(
                  saving: controller.isSaving,
                  onAdd: () => _openEditor(context),
                ),
                if (controller.error != null &&
                    controller.integrityResult == null) ...[
                  const SizedBox(height: 12),
                  _AssetDefinitionErrorBanner(
                    message: controller.error!,
                    onDismiss: controller.clearError,
                  ),
                ],
                const SizedBox(height: 14),
                AssetDefinitionLifecyclePanel(
                  activeDefinitions: controller.definitions,
                  archivedDefinitions: controller.archivedDefinitions,
                  saving: controller.isSaving,
                  usageFor: controller.usageFor,
                  onAdd: () => _openEditor(context),
                  onEdit: (definition) {
                    _openEditor(context, definition: definition);
                  },
                  onArchive: (definition) {
                    _confirmArchive(context, definition);
                  },
                  onRestore: (definition) {
                    _restore(context, definition);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    AssetDefinition? definition,
  }) async {
    controller.clearError();
    final saved = await showDialog<AssetDefinition>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssetDefinitionEditorDialog(
        controller: controller,
        definition: definition,
      ),
    );
    if (saved == null || !context.mounted) return;
    _showMessage(
      context,
      definition == null
          ? '${saved.displayName} created.'
          : '${saved.displayName} updated.',
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    AssetDefinition definition,
  ) async {
    final usage = controller.usageFor(definition);
    if (usage.hasOpenPosition) {
      final quantity = AssetQuantityFormatter.withUnit(
        quantity: usage.openQuantity,
        kind: definition.kind,
        unit: definition.unit,
        symbol: definition.symbol,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cannot archive asset'),
          content: Text(
            'This asset still has an open holding of $quantity. '
            'Close the position before archiving it.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archive ${definition.displayName}?'),
        content: const Text(
          'It will no longer be available for new transactions. Existing '
          'transactions and reports will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await controller.archive(definition);
      if (!context.mounted) return;
      _showMessage(context, '${definition.displayName} archived.');
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, controller.error ?? 'Could not archive the asset.');
    }
  }

  Future<void> _restore(
    BuildContext context,
    AssetDefinition definition,
  ) async {
    try {
      await controller.restore(definition);
      if (!context.mounted) return;
      _showMessage(context, '${definition.displayName} restored.');
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, controller.error ?? 'Could not restore the asset.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AssetManagementToolbar extends StatelessWidget {
  const _AssetManagementToolbar({required this.saving, required this.onAdd});

  final bool saving;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const description = Text(
              'Portfolio accounts and tradable assets are different. '
              'Create one definition for each stock, crypto asset, '
              'commodity, or inventory item.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.45),
            );
            final addButton = FilledButton.icon(
              key: const Key('add-asset-button'),
              onPressed: saving ? null : onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add asset'),
            );
            if (constraints.maxWidth < 650) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [description, const SizedBox(height: 12), addButton],
              );
            }
            return Row(
              children: [
                const Expanded(child: description),
                const SizedBox(width: 18),
                addButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AssetDefinitionErrorBanner extends StatelessWidget {
  const _AssetDefinitionErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                color: colorScheme.onErrorContainer,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
