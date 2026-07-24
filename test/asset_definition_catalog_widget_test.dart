import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_usage_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_retirement_policy.dart';
import 'package:pilgrim_tracker/features/assets/presentation/widgets/asset_definition_lifecycle_panel.dart';

void main() {
  testWidgets('searches locally, reports count, and clears active filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      _catalog(
        active: [
          _definition(
            id: 'bbca',
            name: 'Bank Central Asia',
            symbol: 'BBCA',
            providerSymbol: 'BBCA.JK',
            online: true,
          ),
          _definition(
            id: 'gold',
            name: 'Gold Holdings',
            kind: AssetKind.gold,
            symbol: null,
            unit: 'gram',
          ),
          _definition(
            id: 'usd',
            name: 'US Dollar Cash',
            kind: AssetKind.foreignCurrency,
            symbol: 'USD',
            unit: 'usd',
            providerSymbol: 'USD/IDR',
            online: true,
          ),
        ],
      ),
    );

    expect(find.text('3 assets'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('asset-catalog-search')),
      'bbca.jk',
    );
    await tester.pump();
    expect(find.text('Bank Central Asia'), findsOneWidget);
    expect(find.text('Gold Holdings'), findsNothing);
    expect(find.text('1 of 3 assets'), findsOneWidget);

    await tester.tap(find.byKey(const Key('asset-clear-filters')));
    await tester.pump();
    expect(find.text('3 assets'), findsOneWidget);
    expect(find.text('Gold Holdings'), findsOneWidget);
  });

  testWidgets('combines kind and pricing filters and supports sorting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _catalog(
        active: [
          _definition(id: 'b', name: 'Beta', online: true),
          _definition(id: 'a', name: 'Alpha'),
          _definition(
            id: 'gold',
            name: 'Gold',
            kind: AssetKind.gold,
            symbol: null,
            unit: 'gram',
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('asset-kind-stock')));
    await tester.pump();
    expect(find.byKey(const Key('asset-definition-gold')), findsNothing);
    expect(find.text('2 of 3 assets'), findsOneWidget);

    await tester.tap(find.byKey(const Key('asset-pricing-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online enabled').last);
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.byKey(const Key('asset-clear-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset-sort-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name Z–A').last);
    await tester.pumpAndSettle();
    final goldName = find.descendant(
      of: find.byKey(const Key('asset-definition-gold')),
      matching: find.text('Gold'),
    );
    final betaName = find.descendant(
      of: find.byKey(const Key('asset-definition-b')),
      matching: find.text('Beta'),
    );
    expect(
      tester.getTopLeft(goldName).dy,
      lessThan(tester.getTopLeft(betaName).dy),
    );
  });

  testWidgets('shows distinct active, filtered, and archived empty states', (
    tester,
  ) async {
    var addCount = 0;
    await tester.pumpWidget(_catalog(onAdd: () => addCount++));
    expect(find.text('No assets yet'), findsOneWidget);
    expect(find.byKey(const Key('asset-empty-add')), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-empty-add')));
    expect(addCount, 1);

    await tester.tap(_archivedSegment());
    await tester.pump();
    expect(find.text('No archived assets'), findsOneWidget);
    expect(find.byKey(const Key('asset-empty-add')), findsNothing);

    await tester.pumpWidget(
      _catalog(
        active: [_definition(id: 'bbca', name: 'Bank Central Asia')],
      ),
    );
    await tester.enterText(
      find.byKey(const Key('asset-catalog-search')),
      'no match',
    );
    await tester.pump();
    expect(find.text('No assets match these filters'), findsOneWidget);
    expect(find.byKey(const Key('asset-empty-clear-filters')), findsOneWidget);
  });

  testWidgets('catalog toolbar and cards do not overflow on narrow layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _catalog(
        active: [
          _definition(id: 'bbca', name: 'Bank Central Asia'),
          _definition(
            id: 'usd',
            name: 'US Dollar Cash',
            kind: AssetKind.foreignCurrency,
            symbol: 'USD',
            unit: 'usd',
          ),
        ],
      ),
    );
    expect(find.byKey(const Key('asset-catalog-search')), findsOneWidget);
    expect(find.byKey(const Key('asset-kind-filters')), findsOneWidget);
  });

  testWidgets('legacy definition is identified, read-only, and not restorable', (
    tester,
  ) async {
    final activeLegacy = _definition(
      id: AssetDefinitionRetirementPolicy.retiredStockPortfolioId,
      name: 'Stock Portfolio',
      symbol: 'STOCK',
    );
    await tester.pumpWidget(
      _catalog(active: [activeLegacy], usageFor: (_) => _openUsage),
    );

    expect(find.byKey(const Key('legacy-definition-status')), findsOneWidget);
    expect(find.text('Legacy'), findsOneWidget);
    expect(find.textContaining('can only be used to close'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const Key(
          'asset-actions-${AssetDefinitionRetirementPolicy.retiredStockPortfolioId}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Archive when closed'), findsOneWidget);
    await tester.tap(find.text('Archive when closed'));
    await tester.pumpAndSettle();

    final archivedLegacy = activeLegacy.copyWith(
      deletedAt: DateTime.utc(2026, 7, 24),
    );
    await tester.pumpWidget(_catalog(archived: [archivedLegacy]));
    await tester.tap(_archivedSegment());
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key(
          'asset-actions-${AssetDefinitionRetirementPolicy.retiredStockPortfolioId}',
        ),
      ),
      findsNothing,
    );
    expect(find.text('Restore'), findsNothing);
  });
}

Widget _catalog({
  List<AssetDefinition> active = const [],
  List<AssetDefinition> archived = const [],
  VoidCallback? onAdd,
  AssetDefinitionUsageResult Function(AssetDefinition)? usageFor,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AssetDefinitionLifecyclePanel(
          key: UniqueKey(),
          activeDefinitions: active,
          archivedDefinitions: archived,
          saving: false,
          usageFor: usageFor ?? (_) => _unused,
          onEdit: (_) {},
          onArchive: (_) {},
          onRestore: (_) {},
          onAdd: onAdd ?? () {},
        ),
      ),
    ),
  );
}

Finder _archivedSegment() => find.descendant(
  of: find.byKey(const Key('asset-lifecycle-segments')),
  matching: find.text('Archived'),
);

const _unused = AssetDefinitionUsageResult(
  hasLinkedTransactions: false,
  linkedTransactionCount: 0,
  activeTransactionCount: 0,
  openQuantity: 0,
  hasOpenPosition: false,
  canArchive: true,
  canEditIdentity: true,
  blockingReason: null,
);

const _openUsage = AssetDefinitionUsageResult(
  hasLinkedTransactions: true,
  linkedTransactionCount: 1,
  activeTransactionCount: 1,
  openQuantity: 500,
  hasOpenPosition: true,
  canArchive: false,
  canEditIdentity: false,
  blockingReason: 'Open holding.',
);

AssetDefinition _definition({
  required String id,
  required String name,
  AssetKind kind = AssetKind.stock,
  String? symbol = 'TEST',
  String? providerSymbol,
  String? exchange = 'IDX',
  String unit = 'share',
  bool online = false,
}) {
  return AssetDefinition(
    id: id,
    displayName: name,
    kind: kind,
    symbol: symbol,
    providerCode: online ? 'alpha_vantage' : null,
    providerSymbol: providerSymbol,
    exchangeCode: exchange,
    currencyCode: 'IDR',
    unit: unit,
    lotSize: kind == AssetKind.stock ? 100 : 1,
    onlinePricingEnabled: online,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}
