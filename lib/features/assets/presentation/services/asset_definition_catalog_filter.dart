import '../../domain/entities/asset_definition.dart';
import '../models/asset_definition_catalog_query.dart';

class AssetDefinitionCatalogFilter {
  const AssetDefinitionCatalogFilter();

  List<AssetDefinition> apply({
    required Iterable<AssetDefinition> definitions,
    required AssetDefinitionCatalogQuery query,
  }) {
    final normalizedQuery = _normalize(query.searchText);
    final matches = definitions
        .where((definition) {
          final isArchived = definition.deletedAt != null;
          if ((query.lifecycle == AssetDefinitionLifecycle.archived) !=
              isArchived) {
            return false;
          }
          if (query.selectedKinds.isNotEmpty &&
              !query.selectedKinds.contains(definition.kind)) {
            return false;
          }
          if (query.pricing == AssetDefinitionPricingFilter.onlineEnabled &&
              !definition.onlinePricingEnabled) {
            return false;
          }
          if (query.pricing == AssetDefinitionPricingFilter.manualOffline &&
              definition.onlinePricingEnabled) {
            return false;
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }

          final searchableValues = <String?>[
            definition.displayName,
            definition.symbol,
            definition.providerSymbol,
            definition.exchangeCode,
            definition.currencyCode,
            definition.unit,
            definition.kind.catalogLabel,
          ];
          return searchableValues.any(
            (value) =>
                value != null && _normalize(value).contains(normalizedQuery),
          );
        })
        .toList(growable: false);

    return List<AssetDefinition>.unmodifiable(
      List<AssetDefinition>.of(matches)..sort(_comparator(query.sortOrder)),
    );
  }

  Comparator<AssetDefinition> _comparator(AssetDefinitionSortOrder order) {
    return (left, right) {
      final primary = switch (order) {
        AssetDefinitionSortOrder.nameAscending => _compareName(left, right),
        AssetDefinitionSortOrder.nameDescending => _compareName(right, left),
        AssetDefinitionSortOrder.recentlyUpdated => right.updatedAt.compareTo(
          left.updatedAt,
        ),
        AssetDefinitionSortOrder.assetKind => _compare(
          left.kind.catalogLabel,
          right.kind.catalogLabel,
        ),
        AssetDefinitionSortOrder.symbol => _compareSymbols(left, right),
      };
      if (primary != 0) {
        return primary;
      }

      final name = _compareName(left, right);
      if (name != 0) {
        return name;
      }
      return left.id.compareTo(right.id);
    };
  }

  int _compareName(AssetDefinition left, AssetDefinition right) {
    return _compare(left.displayName, right.displayName);
  }

  int _compareSymbols(AssetDefinition left, AssetDefinition right) {
    final leftSymbol = left.normalizedSymbol ?? '';
    final rightSymbol = right.normalizedSymbol ?? '';
    if (leftSymbol.isEmpty != rightSymbol.isEmpty) {
      return leftSymbol.isEmpty ? 1 : -1;
    }
    return _compare(leftSymbol, rightSymbol);
  }

  int _compare(String left, String right) {
    return _normalize(left).compareTo(_normalize(right));
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
