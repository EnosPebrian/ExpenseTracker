import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../domain/entities/asset_definition.dart';
import '../../domain/entities/asset_kind.dart';
import '../../domain/services/asset_definition_usage_policy.dart';
import '../../domain/services/asset_definition_retirement_policy.dart';
import '../formatters/asset_quantity_formatter.dart';
import '../models/asset_definition_catalog_query.dart';
import '../services/asset_definition_catalog_filter.dart';
import 'asset_definition_catalog_toolbar.dart';
import 'asset_definition_empty_state.dart';

class AssetDefinitionLifecyclePanel extends StatefulWidget {
  const AssetDefinitionLifecyclePanel({
    super.key,
    required this.activeDefinitions,
    required this.archivedDefinitions,
    required this.saving,
    required this.usageFor,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.onAdd,
  });

  final List<AssetDefinition> activeDefinitions;
  final List<AssetDefinition> archivedDefinitions;
  final bool saving;
  final AssetDefinitionUsageResult Function(AssetDefinition) usageFor;
  final ValueChanged<AssetDefinition> onEdit;
  final ValueChanged<AssetDefinition> onArchive;
  final ValueChanged<AssetDefinition> onRestore;
  final VoidCallback onAdd;

  @override
  State<AssetDefinitionLifecyclePanel> createState() =>
      _AssetDefinitionLifecyclePanelState();
}

class _AssetDefinitionLifecyclePanelState
    extends State<AssetDefinitionLifecyclePanel> {
  static const catalogFilter = AssetDefinitionCatalogFilter();
  AssetDefinitionCatalogQuery query = const AssetDefinitionCatalogQuery();

  @override
  Widget build(BuildContext context) {
    final lifecycleDefinitions =
        query.lifecycle == AssetDefinitionLifecycle.active
        ? widget.activeDefinitions
        : widget.archivedDefinitions;
    final definitions = catalogFilter.apply(
      definitions: [...widget.activeDefinitions, ...widget.archivedDefinitions],
      query: query,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle(
              'Asset definitions',
              'Identity and market settings used by transactions',
            ),
            const SizedBox(height: 14),
            SegmentedButton<AssetDefinitionLifecycle>(
              key: const Key('asset-lifecycle-segments'),
              segments: const [
                ButtonSegment(
                  value: AssetDefinitionLifecycle.active,
                  label: Text('Active'),
                ),
                ButtonSegment(
                  value: AssetDefinitionLifecycle.archived,
                  label: Text('Archived'),
                ),
              ],
              selected: {query.lifecycle},
              onSelectionChanged: (selection) {
                setState(() {
                  query = query.copyWith(lifecycle: selection.single);
                });
              },
            ),
            const SizedBox(height: 16),
            AssetDefinitionCatalogToolbar(
              query: query,
              resultCount: definitions.length,
              totalCount: lifecycleDefinitions.length,
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 8),
            if (definitions.isEmpty)
              AssetDefinitionEmptyState(
                type: _emptyStateType(lifecycleDefinitions),
                onAdd: widget.onAdd,
                onClearFilters: () {
                  setState(() => query = query.clearFilters());
                },
              )
            else
              for (var index = 0; index < definitions.length; index++) ...[
                _AssetDefinitionLifecycleTile(
                  definition: definitions[index],
                  usage: widget.usageFor(definitions[index]),
                  enabled: !widget.saving,
                  archived:
                      query.lifecycle == AssetDefinitionLifecycle.archived,
                  onEdit: () => widget.onEdit(definitions[index]),
                  onArchive: () => widget.onArchive(definitions[index]),
                  onRestore: () => widget.onRestore(definitions[index]),
                ),
                if (index != definitions.length - 1) const Divider(height: 28),
              ],
          ],
        ),
      ),
    );
  }

  AssetDefinitionEmptyStateType _emptyStateType(
    List<AssetDefinition> lifecycleDefinitions,
  ) {
    if (lifecycleDefinitions.isNotEmpty) {
      return AssetDefinitionEmptyStateType.noMatches;
    }
    if (query.lifecycle == AssetDefinitionLifecycle.archived) {
      return AssetDefinitionEmptyStateType.noArchived;
    }
    return AssetDefinitionEmptyStateType.noDefinitions;
  }
}

enum _AssetDefinitionAction { edit, archive, restore }

class _AssetDefinitionLifecycleTile extends StatelessWidget {
  const _AssetDefinitionLifecycleTile({
    required this.definition,
    required this.usage,
    required this.enabled,
    required this.archived,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
  });

  final AssetDefinition definition;
  final AssetDefinitionUsageResult usage;
  final bool enabled;
  final bool archived;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    const retirementPolicy = AssetDefinitionRetirementPolicy();
    final retiredSystemDefinition = retirementPolicy.isRetiredSystemDefinition(
      definition,
    );
    final usageText = usage.hasOpenPosition
        ? 'Open holding: ${AssetQuantityFormatter.withUnit(quantity: usage.openQuantity, kind: definition.kind, unit: definition.unit, symbol: definition.symbol)}'
        : usage.hasLinkedTransactions
        ? 'Historical activity · No open holding'
        : 'No linked transactions';

    return ListTile(
      key: Key('asset-definition-${definition.id}'),
      contentPadding: EdgeInsets.zero,
      leading: _DefinitionIcon(kind: definition.kind),
      title: Row(
        children: [
          Flexible(
            child: Text(
              definition.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          if (archived) ...[
            const SizedBox(width: 8),
            const Chip(
              key: Key('archived-status'),
              label: Text('Archived'),
              visualDensity: VisualDensity.compact,
            ),
          ],
          if (retiredSystemDefinition) ...[
            const SizedBox(width: 8),
            const Chip(
              key: Key('legacy-definition-status'),
              label: Text('Legacy'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          [
            _identityText(definition),
            ?_measurementText(definition),
            _pricingText(definition),
            '${usage.linkedTransactionCount} linked transactions · $usageText',
            if (retiredSystemDefinition && !archived)
              AssetDefinitionRetirementPolicy.legacyPositionMessage,
          ].join('\n'),
          style: const TextStyle(color: muted, fontSize: 10, height: 1.45),
        ),
      ),
      trailing: retiredSystemDefinition && archived
          ? null
          : PopupMenuButton<_AssetDefinitionAction>(
              key: Key('asset-actions-${definition.id}'),
              enabled: enabled,
              tooltip: 'Asset actions',
              onSelected: (action) {
                switch (action) {
                  case _AssetDefinitionAction.edit:
                    onEdit();
                  case _AssetDefinitionAction.archive:
                    onArchive();
                  case _AssetDefinitionAction.restore:
                    onRestore();
                }
              },
              itemBuilder: (_) => archived
                  ? const [
                      PopupMenuItem(
                        value: _AssetDefinitionAction.restore,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.restore),
                          title: Text('Restore'),
                        ),
                      ),
                    ]
                  : retiredSystemDefinition
                  ? const [
                      PopupMenuItem(
                        value: _AssetDefinitionAction.archive,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.archive_outlined),
                          title: Text('Archive when closed'),
                        ),
                      ),
                    ]
                  : const [
                      PopupMenuItem(
                        value: _AssetDefinitionAction.edit,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _AssetDefinitionAction.archive,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.archive_outlined),
                          title: Text('Archive'),
                        ),
                      ),
                    ],
            ),
    );
  }

  String _identityText(AssetDefinition definition) {
    final symbol = definition.normalizedSymbol;
    return switch (definition.kind) {
      AssetKind.stock => [
        ?symbol,
        ?definition.normalizedExchangeCode,
      ].join(' · '),
      AssetKind.foreignCurrency => [
        ?symbol,
        'Valued in ${definition.normalizedCurrencyCode}',
      ].join(' · '),
      _ => [
        ?symbol,
        definition.normalizedUnit,
        definition.normalizedCurrencyCode,
      ].join(' · '),
    };
  }

  String? _measurementText(AssetDefinition definition) {
    if (definition.kind != AssetKind.stock) {
      return null;
    }
    return '${definition.normalizedCurrencyCode} · '
        '${definition.normalizedUnit} · '
        '${definition.lotSize} shares/lot';
  }

  String _pricingText(AssetDefinition definition) {
    if (!definition.onlinePricingEnabled) {
      return 'Manual pricing';
    }
    return [
      'Online pricing enabled',
      ?definition.normalizedProviderSymbol,
    ].join(' · ');
  }
}

class _DefinitionIcon extends StatelessWidget {
  const _DefinitionIcon({required this.kind});

  final AssetKind kind;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      AssetKind.gold => Icons.diamond_outlined,
      AssetKind.stock => Icons.candlestick_chart_outlined,
      AssetKind.crypto => Icons.currency_bitcoin_rounded,
      AssetKind.foreignCurrency => Icons.currency_exchange_rounded,
      AssetKind.inventory => Icons.inventory_2_outlined,
      AssetKind.other => Icons.account_balance_wallet_outlined,
    };
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: violet.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: violet, size: 21),
    );
  }
}
