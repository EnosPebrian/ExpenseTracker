import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';

enum AssetDefinitionEmptyStateType { noDefinitions, noMatches, noArchived }

class AssetDefinitionEmptyState extends StatelessWidget {
  const AssetDefinitionEmptyState({
    super.key,
    required this.type,
    this.onAdd,
    this.onClearFilters,
  });

  final AssetDefinitionEmptyStateType type;
  final VoidCallback? onAdd;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final (title, description, icon) = switch (type) {
      AssetDefinitionEmptyStateType.noDefinitions => (
        'No assets yet',
        'Create an asset definition to start recording holdings.',
        Icons.add_business_outlined,
      ),
      AssetDefinitionEmptyStateType.noMatches => (
        'No assets match these filters',
        'Try another search or clear the active filters.',
        Icons.search_off_rounded,
      ),
      AssetDefinitionEmptyStateType.noArchived => (
        'No archived assets',
        'Archived asset definitions will appear here.',
        Icons.inventory_2_outlined,
      ),
    };

    return Padding(
      key: Key('asset-empty-${type.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 34),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            children: [
              Icon(icon, color: muted, size: 34),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              if (type == AssetDefinitionEmptyStateType.noDefinitions &&
                  onAdd != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('asset-empty-add'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add asset'),
                ),
              ],
              if (type == AssetDefinitionEmptyStateType.noMatches &&
                  onClearFilters != null) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  key: const Key('asset-empty-clear-filters'),
                  onPressed: onClearFilters,
                  child: const Text('Clear filters'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
