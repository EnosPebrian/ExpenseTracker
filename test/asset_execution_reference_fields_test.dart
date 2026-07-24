import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_conversion_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/assets/presentation/widgets/asset_execution_reference_fields.dart';

void main() {
  testWidgets('starts compact with no reference price', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('No reference price'), findsOneWidget);
    expect(find.byKey(const Key('market_reference_price_field')), findsNothing);
  });

  testWidgets('manual reference shows unfavorable buy wording', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const Key('manual_market_reference_button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('market_reference_price_field')),
      '16250',
    );
    await tester.pump();

    expect(find.text('Paid above reference'), findsOneWidget);
    expect(find.textContaining('Manual snapshot'), findsOneWidget);
    expect(find.text('Execution price'), findsOneWidget);
  });

  testWidgets(
    'explicit cached reference shows source, time, and neutral wording',
    (tester) async {
      final quotedAt = DateTime.utc(2026, 7, 24, 8, 30);
      final controller = _controller(
        executionPrice: 16300,
        prices: [
          AssetMarketPrice.manual(
            assetKey: 'USD',
            symbol: 'USD',
            price: 16300,
            unit: 'usd',
            quotedAt: quotedAt,
          ),
        ],
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller, size: const Size(340, 700));

      await tester.tap(find.byKey(const Key('cached_market_reference_button')));
      await tester.pump();

      expect(find.text('Matched reference price'), findsOneWidget);
      expect(find.textContaining('Saved price snapshot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sell below reference uses direction-aware wording', (
    tester,
  ) async {
    final controller = _controller(executionPrice: 9900);
    controller.setSellAsset(true);
    controller.cashController.text = '9.900';
    controller.quantityController.text = '1';
    controller.useManualMarketReference();
    controller.referencePriceController.text = '10.000';
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    expect(find.text('Sold below reference'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AssetConversionController controller, {
  Size size = const Size(600, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) =>
                AssetExecutionReferenceFields(controller: controller),
          ),
        ),
      ),
    ),
  );
}

AssetConversionController _controller({
  int executionPrice = 16300,
  List<AssetMarketPrice> prices = const [],
}) {
  final controller = AssetConversionController(
    accounts: const ['Cash'],
    assets: [_usd],
    marketPrices: prices,
  );
  controller.cashController.text = '${executionPrice * 1000}';
  controller.quantityController.text = '1000';
  return controller;
}

final _usd = AssetDefinition(
  id: 'asset-usd',
  displayName: 'US Dollar Cash',
  kind: AssetKind.foreignCurrency,
  symbol: 'USD',
  providerCode: 'alpha_vantage',
  providerSymbol: 'USD/IDR',
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: 'usd',
  lotSize: 1,
  onlinePricingEnabled: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);
