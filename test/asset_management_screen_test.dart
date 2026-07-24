import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/repositories/asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/presentation/screens/asset_management_screen.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

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
    expect(definition.lotSize, 1);
    expect(definition.onlinePricingEnabled, isTrue);

    expect(find.text('Bank Central Asia'), findsOneWidget);
  });
  testWidgets('creates a custom foreign currency with explicit suggestions', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();

    final controller = AssetDefinitionController(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 23, 12),
    );

    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-asset-button')));

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('asset-kind-field')));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Foreign currency').last);

    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('asset-name-field')),
      'Euro Cash',
    );

    await tester.enterText(find.byKey(const Key('asset-symbol-field')), 'EUR');

    await tester.pumpAndSettle();

    final unitField = tester.widget<TextFormField>(
      find.byKey(const Key('asset-unit-field')),
    );

    expect(unitField.controller?.text, isEmpty);

    final symbolUnitPreset = find.widgetWithText(ActionChip, 'Use EUR as unit');
    await tester.ensureVisible(symbolUnitPreset);
    await tester.pumpAndSettle();
    await tester.tap(symbolUnitPreset);
    await tester.pumpAndSettle();
    final providerPairPreset = find.widgetWithText(
      ActionChip,
      'Use EUR/IDR pair',
    );
    await tester.ensureVisible(providerPairPreset);
    await tester.pumpAndSettle();
    await tester.tap(providerPairPreset);
    await tester.pumpAndSettle();

    final onlinePricingSwitch = find.byKey(
      const Key('asset-online-pricing-switch'),
    );
    await tester.ensureVisible(onlinePricingSwitch);
    await tester.tap(onlinePricingSwitch);
    await tester.pumpAndSettle();

    final providerPairField = tester.widget<TextFormField>(
      find.byKey(const Key('asset-provider-symbol-field')),
    );

    expect(providerPairField.controller?.text, 'EUR/IDR');

    final saveButton = find.byKey(const Key('save-asset-button'));

    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(controller.definitions, hasLength(1));

    final definition = controller.definitions.single;

    expect(definition.displayName, 'Euro Cash');
    expect(definition.kind, AssetKind.foreignCurrency);
    expect(definition.normalizedSymbol, 'EUR');
    expect(definition.normalizedUnit, 'eur');
    expect(definition.normalizedCurrencyCode, 'IDR');
    expect(definition.normalizedProviderCode, 'ALPHA_VANTAGE');
    expect(definition.normalizedProviderSymbol, 'EUR/IDR');
    expect(definition.lotSize, 1);
    expect(definition.onlinePricingEnabled, isTrue);
    expect(definition.validate(), isEmpty);
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

  testWidgets('keeps form values on duplicate symbol and saves correction', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();
    await repository.upsert(_stockDefinition());
    final controller = AssetDefinitionController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await _openStockEditor(
      tester,
      name: 'Duplicate BCA',
      symbol: ' bbca ',
      exchange: ' idx ',
    );
    await tester.tap(find.byKey(const Key('save-asset-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('already exists'), findsWidgets);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('asset-name-field')))
          .controller
          ?.text,
      'Duplicate BCA',
    );
    expect(repository.definitions, hasLength(1));

    await tester.enterText(find.byKey(const Key('asset-symbol-field')), 'BBRI');
    await tester.tap(find.byKey(const Key('save-asset-button')));
    await tester.pumpAndSettle();

    expect(controller.definitions, hasLength(2));
    expect(
      controller.definitions.map((definition) => definition.normalizedSymbol),
      contains('BBRI'),
    );
  });

  testWidgets('shows duplicate provider-symbol error separately', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();
    await repository.upsert(_stockDefinition());
    final controller = AssetDefinitionController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await _openStockEditor(
      tester,
      name: 'Bank Rakyat Indonesia',
      symbol: 'BBRI',
      exchange: 'IDX',
      providerSymbol: ' bbca.jk ',
    );
    await tester.tap(find.byKey(const Key('save-asset-button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('already used by Bank Central Asia'),
      findsWidgets,
    );
    expect(repository.definitions, hasLength(1));
  });

  testWidgets('explains archived conflict without closing the form', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();
    await repository.upsert(
      _stockDefinition().copyWith(deletedAt: DateTime.utc(2026, 7, 23)),
    );
    final controller = AssetDefinitionController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await _openStockEditor(
      tester,
      name: 'New BBCA',
      symbol: 'BBCA',
      exchange: 'IDX',
      enableOnlinePricing: false,
    );
    await tester.tap(find.byKey(const Key('save-asset-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('archived'), findsWidgets);
    expect(find.textContaining('Restore or edit'), findsWidgets);
    expect(find.byKey(const Key('asset-name-field')), findsOneWidget);
  });

  testWidgets('validates provider configuration and foreign currency pair', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();
    final controller = AssetDefinitionController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await _openStockEditor(
      tester,
      name: 'Bank Rakyat Indonesia',
      symbol: 'BBRI',
      exchange: 'IDX',
      providerSymbol: '',
    );
    await tester.tap(find.byKey(const Key('save-asset-button')));
    await tester.pump();
    expect(find.text('A provider symbol is required.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-asset-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset-kind-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foreign currency').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('asset-name-field')),
      'US Dollar',
    );
    await tester.enterText(find.byKey(const Key('asset-symbol-field')), 'USD');
    await tester.ensureVisible(find.byKey(const Key('asset-use-symbol-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset-use-symbol-unit')));
    await tester.ensureVisible(
      find.byKey(const Key('asset-online-pricing-switch')),
    );
    await tester.tap(find.byKey(const Key('asset-online-pricing-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('asset-provider-symbol-field')),
      'SGD/IDR',
    );
    await tester.ensureVisible(find.byKey(const Key('save-asset-button')));
    await tester.tap(find.byKey(const Key('save-asset-button')));
    await tester.pump();

    expect(find.text('Provider pair must be USD/IDR.'), findsOneWidget);
  });

  testWidgets('switches between active and archived definitions', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();
    await repository.upsert(_stockDefinition());
    await repository.upsert(
      _stockDefinition().copyWith(
        id: 'asset-bbri',
        displayName: 'Bank Rakyat Indonesia',
        symbol: 'BBRI',
        providerSymbol: 'BBRI.JK',
        deletedAt: DateTime.utc(2026, 7, 23),
      ),
    );
    final controller = AssetDefinitionController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    expect(find.text('Bank Central Asia'), findsOneWidget);
    expect(find.text('Bank Rakyat Indonesia'), findsNothing);

    await tester.tap(_archivedSegment());
    await tester.pumpAndSettle();

    expect(find.text('Bank Central Asia'), findsNothing);
    expect(find.text('Bank Rakyat Indonesia'), findsOneWidget);
    expect(find.byKey(const Key('archived-status')), findsOneWidget);
  });

  testWidgets('confirms archive and explains an open position', (tester) async {
    final repository = _FakeAssetDefinitionRepository();
    final definition = _stockDefinition();
    await repository.upsert(definition);
    final transactions = <Transaction>[
      _assetTransaction(definition: definition, quantity: 500),
    ];
    final controller = AssetDefinitionController(
      repository: repository,
      transactionsProvider: () async => transactions,
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await _openAssetActions(tester, 'asset-bbca');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot archive asset'), findsOneWidget);
    expect(find.textContaining('500 shares'), findsWidgets);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    transactions
      ..clear()
      ..addAll([
        _assetTransaction(definition: definition, quantity: 500),
        _assetTransaction(
          id: 'sell',
          definition: definition,
          quantity: 500,
          action: AssetAction.sell,
        ),
      ]);
    await controller.reload();
    await tester.pumpAndSettle();
    await _openAssetActions(tester, 'asset-bbca');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Archive Bank Central Asia?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(controller.archivedDefinitions, hasLength(1));
  });

  testWidgets('restores an archived definition and reports restore conflicts', (
    tester,
  ) async {
    final repository = _FakeAssetDefinitionRepository();
    final archived = _stockDefinition().copyWith(
      deletedAt: DateTime.utc(2026, 7, 23),
    );
    await repository.upsert(archived);
    final controller = AssetDefinitionController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await tester.tap(_archivedSegment());
    await tester.pumpAndSettle();
    await _openAssetActions(tester, 'asset-bbca');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(controller.definitions.single.id, archived.id);

    await controller.archive(controller.definitions.single);
    await repository.upsert(
      _stockDefinition().copyWith(id: 'asset-active-conflict'),
    );
    await controller.reload();
    await tester.pumpAndSettle();
    await tester.tap(_archivedSegment());
    await tester.pumpAndSettle();
    await _openAssetActions(tester, 'asset-bbca');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot restore'), findsWidgets);
    expect(controller.archivedDefinitions.single.id, archived.id);
  });

  testWidgets(
    'linked edit locks identity fields but keeps safe fields editable',
    (tester) async {
      final repository = _FakeAssetDefinitionRepository();
      final definition = _stockDefinition();
      await repository.upsert(definition);
      final controller = AssetDefinitionController(
        repository: repository,
        transactionsProvider: () async => [
          _assetTransaction(definition: definition),
        ],
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(home: AssetManagementScreen(controller: controller)),
      );

      await _openAssetActions(tester, 'asset-bbca');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('linked-edit-explanation')), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<AssetKind>>(
              find.byKey(const Key('asset-kind-field')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('asset-symbol-field')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('asset-name-field')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isFalse,
      );

      await tester.enterText(
        find.byKey(const Key('asset-name-field')),
        'BCA Tbk',
      );
      await tester.ensureVisible(find.byKey(const Key('save-asset-button')));
      await tester.tap(find.byKey(const Key('save-asset-button')));
      await tester.pumpAndSettle();

      expect(controller.definitions.single.displayName, 'BCA Tbk');
    },
  );

  testWidgets('asset editor has no narrow-layout overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AssetDefinitionController(
      repository: _FakeAssetDefinitionRepository(),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-asset-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-name-field')), findsOneWidget);
  });

  testWidgets('groups form fields and presets preserve explicit values', (
    tester,
  ) async {
    final controller = AssetDefinitionController(
      repository: _FakeAssetDefinitionRepository(),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: AssetManagementScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-asset-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-section-identity')), findsOneWidget);
    expect(find.byKey(const Key('asset-section-trading')), findsOneWidget);
    expect(find.byKey(const Key('asset-section-pricing')), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('asset-online-pricing-switch')),
          )
          .value,
      isFalse,
    );

    await tester.enterText(find.byKey(const Key('asset-lot-size-field')), '25');
    final idxPreset = find.byKey(const Key('asset-use-idx-defaults'));
    await tester.ensureVisible(idxPreset);
    await tester.tap(idxPreset);
    await tester.pumpAndSettle();

    final lotSizeField = tester.widget<TextFormField>(
      find.byKey(const Key('asset-lot-size-field')),
    );
    expect(lotSizeField.controller?.text, '25');
  });
}

Future<void> _openStockEditor(
  WidgetTester tester, {
  required String name,
  required String symbol,
  required String exchange,
  String providerSymbol = 'BBRI.JK',
  bool enableOnlinePricing = true,
}) async {
  await tester.tap(find.byKey(const Key('add-asset-button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('asset-name-field')), name);
  await tester.enterText(find.byKey(const Key('asset-symbol-field')), symbol);
  await tester.enterText(
    find.byKey(const Key('asset-exchange-field')),
    exchange,
  );
  if (enableOnlinePricing) {
    final pricingSwitch = find.byKey(const Key('asset-online-pricing-switch'));
    await tester.ensureVisible(pricingSwitch);
    await tester.tap(pricingSwitch);
    await tester.pumpAndSettle();
    final providerField = find.byKey(const Key('asset-provider-symbol-field'));
    await tester.ensureVisible(providerField);
    await tester.enterText(providerField, providerSymbol);
  }
  await tester.ensureVisible(find.byKey(const Key('save-asset-button')));
  await tester.pumpAndSettle();
}

Finder _archivedSegment() {
  return find.descendant(
    of: find.byKey(const Key('asset-lifecycle-segments')),
    matching: find.text('Archived'),
  );
}

Future<void> _openAssetActions(WidgetTester tester, String id) async {
  final finder = find.byKey(Key('asset-actions-$id'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
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

AssetDefinition _stockDefinition() {
  return AssetDefinition(
    id: 'asset-bbca',
    displayName: 'Bank Central Asia',
    kind: AssetKind.stock,
    symbol: 'BBCA',
    providerCode: 'alpha_vantage',
    providerSymbol: 'BBCA.JK',
    exchangeCode: 'IDX',
    currencyCode: 'IDR',
    unit: 'share',
    lotSize: 100,
    onlinePricingEnabled: true,
    createdAt: DateTime.utc(2026, 7, 21),
    updatedAt: DateTime.utc(2026, 7, 21),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

Transaction _assetTransaction({
  String id = 'buy',
  required AssetDefinition definition,
  double quantity = 100,
  AssetAction action = AssetAction.buy,
}) {
  return Transaction(
    id: id,
    title: '${action.name} ${definition.displayName}',
    category: 'Asset conversion',
    account: 'Cash -> ${definition.displayName}',
    date: DateTime.utc(2026, 7, 24),
    amount: (quantity * 1000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: definition.unit,
    unitPrice: 1000,
    assetDefinitionId: definition.id,
    assetName: definition.displayName,
    assetSymbol: definition.symbol,
    assetAction: action,
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
