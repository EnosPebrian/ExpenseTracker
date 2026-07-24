import '../../domain/entities/asset_kind.dart';

enum AssetDefinitionLifecycle { active, archived }

enum AssetDefinitionPricingFilter { all, onlineEnabled, manualOffline }

enum AssetDefinitionSortOrder {
  nameAscending,
  nameDescending,
  recentlyUpdated,
  assetKind,
  symbol,
}

class AssetDefinitionCatalogQuery {
  const AssetDefinitionCatalogQuery({
    this.searchText = '',
    this.lifecycle = AssetDefinitionLifecycle.active,
    this.selectedKinds = const {},
    this.pricing = AssetDefinitionPricingFilter.all,
    this.sortOrder = AssetDefinitionSortOrder.nameAscending,
  });

  final String searchText;
  final AssetDefinitionLifecycle lifecycle;
  final Set<AssetKind> selectedKinds;
  final AssetDefinitionPricingFilter pricing;
  final AssetDefinitionSortOrder sortOrder;

  bool get hasActiveFilters =>
      searchText.trim().isNotEmpty ||
      selectedKinds.isNotEmpty ||
      pricing != AssetDefinitionPricingFilter.all;

  AssetDefinitionCatalogQuery copyWith({
    String? searchText,
    AssetDefinitionLifecycle? lifecycle,
    Set<AssetKind>? selectedKinds,
    AssetDefinitionPricingFilter? pricing,
    AssetDefinitionSortOrder? sortOrder,
  }) {
    return AssetDefinitionCatalogQuery(
      searchText: searchText ?? this.searchText,
      lifecycle: lifecycle ?? this.lifecycle,
      selectedKinds: Set<AssetKind>.unmodifiable(
        selectedKinds ?? this.selectedKinds,
      ),
      pricing: pricing ?? this.pricing,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  AssetDefinitionCatalogQuery clearFilters() {
    return AssetDefinitionCatalogQuery(
      lifecycle: lifecycle,
      sortOrder: sortOrder,
    );
  }
}

extension AssetKindPresentation on AssetKind {
  String get catalogLabel => switch (this) {
    AssetKind.gold => 'Gold',
    AssetKind.stock => 'Stocks',
    AssetKind.crypto => 'Cryptocurrency',
    AssetKind.foreignCurrency => 'Foreign currency',
    AssetKind.inventory => 'Inventory',
    AssetKind.other => 'Other',
  };
}

extension AssetDefinitionPricingFilterPresentation
    on AssetDefinitionPricingFilter {
  String get label => switch (this) {
    AssetDefinitionPricingFilter.all => 'All pricing',
    AssetDefinitionPricingFilter.onlineEnabled => 'Online enabled',
    AssetDefinitionPricingFilter.manualOffline => 'Manual/offline',
  };
}

extension AssetDefinitionSortOrderPresentation on AssetDefinitionSortOrder {
  String get label => switch (this) {
    AssetDefinitionSortOrder.nameAscending => 'Name A–Z',
    AssetDefinitionSortOrder.nameDescending => 'Name Z–A',
    AssetDefinitionSortOrder.recentlyUpdated => 'Recently updated',
    AssetDefinitionSortOrder.assetKind => 'Asset kind',
    AssetDefinitionSortOrder.symbol => 'Symbol',
  };
}
