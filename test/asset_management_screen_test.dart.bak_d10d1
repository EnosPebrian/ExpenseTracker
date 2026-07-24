import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/repositories/asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/presentation/screens/asset_management_screen.dart';

void main() {
  testWidgets('shows the existing asset definitions', (tester) async {
    final repository = _FakeAssetDefinitionRepository();

    await repository.upsert(_goldDefinition());

    final controller = AssetDefinitionController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 22),
    );

    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    expect(find.text('Manage assets'), findsWidgets);
    expect(find.text('Gold Holdings'), findsOneWidget);
    expect(find.textContaining('Gold'), findsWidgets);
    expect(find.byKey(const Key('add-asset-button')), findsOneWidget);
  });

  testWidgets('creates a concrete stock definition', (tester) async {
    final repository = _FakeAssetDefinitionRepository();

    final controller = AssetDefinitionController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 22, 12),
    );

    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-asset-button')));

    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('asset-name-field')),
      'Bank Central Asia',
    );

    await tester.enterText(find.byKey(const Key('asset-symbol-field')), 'BBCA');

    await tester.enterText(
      find.byKey(const Key('asset-exchange-field')),
      'IDX',
    );

    final onlinePricingSwitch = find.byKey(
      const Key('asset-online-pricing-switch'),
    );

    await tester.ensureVisible(onlinePricingSwitch);
    await tester.pumpAndSettle();

    await tester.tap(onlinePricingSwitch);
    await tester.pumpAndSettle();

    final providerSymbolField = find.byKey(
      const Key('asset-provider-symbol-field'),
    );

    await tester.ensureVisible(providerSymbolField);
    await tester.pumpAndSettle();

    await tester.enterText(providerSymbolField, 'BBCA.JK');

    final saveButton = find.byKey(const Key('save-asset-button'));

    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(controller.definitions, hasLength(1));

    final definition = controller.definitions.single;

    expect(definition.displayName, 'Bank Central Asia');
    expect(definition.kind, AssetKind.stock);
    expect(definition.symbol, 'BBCA');
    expect(definition.providerCode, 'ALPHA_VANTAGE');
    expect(definition.providerSymbol, 'BBCA.JK');
    expect(definition.exchangeCode, 'IDX');
    expect(definition.currencyCode, 'IDR');
    expect(definition.unit, 'share');
    expect(definition.lotSize, 100);
    expect(definition.onlinePricingEnabled, isTrue);

    expect(find.text('Bank Central Asia'), findsOneWidget);
  });

  testWidgets('requires a stock symbol before saving', (tester) async {
    final repository = _FakeAssetDefinitionRepository();

    final controller = AssetDefinitionController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 22),
    );

    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-asset-button')));

    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('asset-name-field')),
      'Unnamed stock',
    );

    await tester.tap(find.byKey(const Key('save-asset-button')));

    await tester.pump();

    expect(find.text('A stock symbol is required.'), findsOneWidget);

    expect(controller.definitions, isEmpty);
  });
}

AssetDefinition _goldDefinition() {
  return AssetDefinition(
    id: 'asset-gold',
    displayName: 'Gold Holdings',
    kind: AssetKind.gold,
    symbol: null,
    providerCode: 'alpha_vantage',
    providerSymbol: 'XAU',
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: 'gram',
    lotSize: 1,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21),
    updatedAt: DateTime.utc(2026, 7, 21),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

class _FakeAssetDefinitionRepository implements AssetDefinitionRepository {
  final Map<String, AssetDefinition> definitions = {};

  @override
  Future<List<AssetDefinition>> getAll({bool includeDeleted = false}) async {
    return definitions.values
        .where((definition) => includeDeleted || definition.deletedAt == null)
        .toList();
  }

  @override
  Future<AssetDefinition?> getById(String id) async {
    return definitions[id];
  }

  @override
  Future<void> upsert(AssetDefinition definition) async {
    definitions[definition.id] = definition;
  }

  @override
  Future<void> softDelete(String id, {required DateTime deletedAt}) async {
    final definition = definitions[id];

    if (definition == null) {
      return;
    }

    definitions[id] = definition.copyWith(
      deletedAt: deletedAt,
      updatedAt: deletedAt,
      version: definition.version + 1,
      syncStatus: 'pending',
    );
  }

  @override
  Future<void> ensureSeeds(Iterable<AssetDefinition> values) async {
    for (final definition in values) {
      definitions.putIfAbsent(definition.id, () => definition);
    }
  }
}
