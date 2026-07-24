import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/presentation/models/asset_definition_catalog_query.dart';
import 'package:pilgrim_tracker/features/assets/presentation/services/asset_definition_catalog_filter.dart';

void main() {
  const filter = AssetDefinitionCatalogFilter();
  final definitions = [
    _definition(
      id: 'bbca',
      name: 'Bank   Central Asia',
      kind: AssetKind.stock,
      symbol: 'BBCA',
      providerSymbol: 'BBCA.JK',
      exchange: 'IDX',
      currency: 'IDR',
      unit: 'share',
      online: true,
      updatedAt: DateTime.utc(2026, 7, 20),
    ),
    _definition(
      id: 'usd',
      name: 'US Dollar Cash',
      kind: AssetKind.foreignCurrency,
      symbol: 'USD',
      providerSymbol: 'USD/IDR',
      currency: 'IDR',
      unit: 'usd',
      online: true,
      updatedAt: DateTime.utc(2026, 7, 22),
    ),
    _definition(
      id: 'gold',
      name: 'Gold Holdings',
      kind: AssetKind.gold,
      currency: 'IDR',
      unit: 'gram',
      updatedAt: DateTime.utc(2026, 7, 21),
    ),
    _definition(
      id: 'archived-stock',
      name: 'Archived IDX Stock',
      kind: AssetKind.stock,
      symbol: 'OLD',
      exchange: 'IDX',
      currency: 'IDR',
      unit: 'share',
      deletedAt: DateTime.utc(2026, 7, 23),
    ),
  ];

  test(
    'empty query returns every active definition in deterministic order',
    () {
      final result = filter.apply(
        definitions: definitions,
        query: const AssetDefinitionCatalogQuery(),
      );
      expect(result.map((item) => item.id), ['bbca', 'gold', 'usd']);
    },
  );

  for (final searchCase in <String, String>{
    'central asia': 'bbca',
    'BBCA': 'bbca',
    'bbca.jk': 'bbca',
    'idx': 'bbca',
    'dollar': 'usd',
    'usd': 'usd',
    'gram': 'gold',
    'gold': 'gold',
    'foreign currency': 'usd',
  }.entries) {
    test('searches visible identity field "${searchCase.key}"', () {
      final result = filter.apply(
        definitions: definitions,
        query: AssetDefinitionCatalogQuery(searchText: searchCase.key),
      );
      expect(result.map((item) => item.id), contains(searchCase.value));
    });
  }

  test('normalizes query whitespace and combines search with kind', () {
    final result = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(
        searchText: ' bank   central ',
        selectedKinds: {AssetKind.stock},
      ),
    );
    expect(result.single.id, 'bbca');
  });

  test('supports one or multiple selected kinds', () {
    final oneKind = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(selectedKinds: {AssetKind.gold}),
    );
    final multipleKinds = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(
        selectedKinds: {AssetKind.gold, AssetKind.foreignCurrency},
      ),
    );
    expect(oneKind.map((item) => item.id), ['gold']);
    expect(multipleKinds.map((item) => item.id), ['gold', 'usd']);
  });

  test('filters online and manual pricing independently', () {
    final online = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(
        pricing: AssetDefinitionPricingFilter.onlineEnabled,
      ),
    );
    final manual = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(
        pricing: AssetDefinitionPricingFilter.manualOffline,
      ),
    );
    expect(online.map((item) => item.id), ['bbca', 'usd']);
    expect(manual.map((item) => item.id), ['gold']);
  });

  test('keeps active and archived lifecycle results separate', () {
    final active = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(searchText: 'idx'),
    );
    final archived = filter.apply(
      definitions: definitions,
      query: const AssetDefinitionCatalogQuery(
        searchText: 'idx',
        lifecycle: AssetDefinitionLifecycle.archived,
      ),
    );
    expect(active.map((item) => item.id), ['bbca']);
    expect(archived.map((item) => item.id), ['archived-stock']);
  });

  test('clear filters preserves lifecycle and sorting only', () {
    const query = AssetDefinitionCatalogQuery(
      searchText: 'usd',
      lifecycle: AssetDefinitionLifecycle.archived,
      selectedKinds: {AssetKind.stock},
      pricing: AssetDefinitionPricingFilter.onlineEnabled,
      sortOrder: AssetDefinitionSortOrder.symbol,
    );
    final cleared = query.clearFilters();
    expect(cleared.searchText, isEmpty);
    expect(cleared.selectedKinds, isEmpty);
    expect(cleared.pricing, AssetDefinitionPricingFilter.all);
    expect(cleared.lifecycle, AssetDefinitionLifecycle.archived);
    expect(cleared.sortOrder, AssetDefinitionSortOrder.symbol);
  });

  test('supports every sort order and deterministic tie-breaking', () {
    final tied = [
      _definition(id: 'z', name: 'Same', symbol: 'ZZZ'),
      _definition(id: 'a', name: 'Same', symbol: 'AAA'),
      ...definitions,
    ];
    List<String> ids(AssetDefinitionSortOrder order) => filter
        .apply(
          definitions: tied,
          query: AssetDefinitionCatalogQuery(sortOrder: order),
        )
        .map((item) => item.id)
        .toList();

    expect(ids(AssetDefinitionSortOrder.nameAscending).first, 'bbca');
    expect(ids(AssetDefinitionSortOrder.nameDescending).first, 'usd');
    expect(ids(AssetDefinitionSortOrder.recentlyUpdated).first, 'usd');
    expect(ids(AssetDefinitionSortOrder.assetKind).first, 'usd');
    expect(ids(AssetDefinitionSortOrder.symbol).first, 'a');
    expect(
      ids(
        AssetDefinitionSortOrder.nameAscending,
      ).where((id) => id == 'a' || id == 'z'),
      ['a', 'z'],
    );
  });

  test('does not mutate source definitions or list order', () {
    final source = definitions.toList();
    final originalIds = source.map((item) => item.id).toList();
    filter.apply(
      definitions: source,
      query: const AssetDefinitionCatalogQuery(
        sortOrder: AssetDefinitionSortOrder.nameDescending,
      ),
    );
    expect(source.map((item) => item.id), originalIds);
  });
}

AssetDefinition _definition({
  required String id,
  required String name,
  AssetKind kind = AssetKind.stock,
  String? symbol,
  String? providerSymbol,
  String? exchange,
  String currency = 'IDR',
  String unit = 'share',
  bool online = false,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return AssetDefinition(
    id: id,
    displayName: name,
    kind: kind,
    symbol: symbol,
    providerCode: online ? 'alpha_vantage' : null,
    providerSymbol: providerSymbol,
    exchangeCode: exchange,
    currencyCode: currency,
    unit: unit,
    lotSize: 1,
    onlinePricingEnabled: online,
    createdAt: DateTime.utc(2026),
    updatedAt: updatedAt ?? DateTime.utc(2026),
    deletedAt: deletedAt,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}
