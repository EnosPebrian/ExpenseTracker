import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../domain/entities/asset_kind.dart';
import '../models/asset_definition_catalog_query.dart';

class AssetDefinitionCatalogToolbar extends StatefulWidget {
  const AssetDefinitionCatalogToolbar({
    super.key,
    required this.query,
    required this.resultCount,
    required this.totalCount,
    required this.onChanged,
  });

  final AssetDefinitionCatalogQuery query;
  final int resultCount;
  final int totalCount;
  final ValueChanged<AssetDefinitionCatalogQuery> onChanged;

  @override
  State<AssetDefinitionCatalogToolbar> createState() =>
      _AssetDefinitionCatalogToolbarState();
}

class _AssetDefinitionCatalogToolbarState
    extends State<AssetDefinitionCatalogToolbar> {
  late final TextEditingController searchController;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: widget.query.searchText);
  }

  @override
  void didUpdateWidget(AssetDefinitionCatalogToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (searchController.text != widget.query.searchText) {
      searchController.value = TextEditingValue(
        text: widget.query.searchText,
        selection: TextSelection.collapsed(
          offset: widget.query.searchText.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          key: const Key('asset-catalog-search'),
          controller: searchController,
          decoration: InputDecoration(
            labelText: 'Search assets',
            hintText: 'Name, symbol, exchange, currency, or unit',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('asset-search-clear'),
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      widget.onChanged(widget.query.copyWith(searchText: ''));
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (value) {
            widget.onChanged(widget.query.copyWith(searchText: value));
            setState(() {});
          },
        );

        final dropdowns = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: constraints.maxWidth < 620 ? 170 : 190,
              child: _CatalogDropdown<AssetDefinitionPricingFilter>(
                dropdownKey: const Key('asset-pricing-filter'),
                label: 'Pricing',
                value: widget.query.pricing,
                values: AssetDefinitionPricingFilter.values,
                itemLabel: (value) => value.label,
                onChanged: (value) =>
                    widget.onChanged(widget.query.copyWith(pricing: value)),
              ),
            ),
            SizedBox(
              width: constraints.maxWidth < 620 ? 170 : 200,
              child: _CatalogDropdown<AssetDefinitionSortOrder>(
                dropdownKey: const Key('asset-sort-order'),
                label: 'Sort',
                value: widget.query.sortOrder,
                values: AssetDefinitionSortOrder.values,
                itemLabel: (value) => value.label,
                onChanged: (value) =>
                    widget.onChanged(widget.query.copyWith(sortOrder: value)),
              ),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (constraints.maxWidth >= 760)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  dropdowns,
                ],
              )
            else ...[
              search,
              const SizedBox(height: 10),
              dropdowns,
            ],
            const SizedBox(height: 12),
            Wrap(
              key: const Key('asset-kind-filters'),
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  key: const Key('asset-kind-all'),
                  label: const Text('All'),
                  selected: widget.query.selectedKinds.isEmpty,
                  onSelected: (_) {
                    widget.onChanged(
                      widget.query.copyWith(selectedKinds: const {}),
                    );
                  },
                ),
                for (final kind in AssetKind.values)
                  FilterChip(
                    key: Key('asset-kind-${kind.name}'),
                    avatar: Icon(_kindIcon(kind), size: 16),
                    label: Text(kind.catalogLabel),
                    selected: widget.query.selectedKinds.contains(kind),
                    onSelected: (selected) {
                      final kinds = Set<AssetKind>.of(
                        widget.query.selectedKinds,
                      );
                      selected ? kinds.add(kind) : kinds.remove(kind);
                      widget.onChanged(
                        widget.query.copyWith(selectedKinds: kinds),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _resultLabel(),
                    key: const Key('asset-result-count'),
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.query.hasActiveFilters)
                  TextButton.icon(
                    key: const Key('asset-clear-filters'),
                    onPressed: () {
                      widget.onChanged(widget.query.clearFilters());
                    },
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                    label: const Text('Clear filters'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _resultLabel() {
    final suffix = widget.query.lifecycle == AssetDefinitionLifecycle.archived
        ? 'archived assets'
        : 'assets';
    if (widget.query.hasActiveFilters &&
        widget.resultCount != widget.totalCount) {
      return '${widget.resultCount} of ${widget.totalCount} $suffix';
    }
    return '${widget.resultCount} $suffix';
  }
}

class _CatalogDropdown<T> extends StatelessWidget {
  const _CatalogDropdown({
    required this.dropdownKey,
    required this.label,
    required this.value,
    required this.values,
    required this.itemLabel,
    required this.onChanged,
  });

  final Key dropdownKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: dropdownKey,
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final option in values)
              DropdownMenuItem(value: option, child: Text(itemLabel(option))),
          ],
          onChanged: (selection) {
            if (selection != null) onChanged(selection);
          },
        ),
      ),
    );
  }
}

IconData _kindIcon(AssetKind kind) => switch (kind) {
  AssetKind.gold => Icons.diamond_outlined,
  AssetKind.stock => Icons.candlestick_chart_outlined,
  AssetKind.crypto => Icons.currency_bitcoin_rounded,
  AssetKind.foreignCurrency => Icons.currency_exchange_rounded,
  AssetKind.inventory => Icons.inventory_2_outlined,
  AssetKind.other => Icons.account_balance_wallet_outlined,
};
