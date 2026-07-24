import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_price_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_portfolio.dart';
import 'package:pilgrim_tracker/features/assets/presentation/screens/assets_dashboard_screen.dart';

void main() {
  testWidgets('Manage assets button triggers the supplied action', (
    tester,
  ) async {
    final priceController = AssetPriceController(store: LocalStore());

    addTearDown(priceController.dispose);

    var manageAssetsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetsDashboardScreen(
            portfolio: const AssetPortfolio(
              holdings: [],
              totalCostBasis: 0,
              totalMarketValue: 0,
              totalUnrealizedGain: 0,
              totalRealizedGain: 0,
            ),
            priceController: priceController,
            onManageAssets: () {
              manageAssetsOpened = true;
            },
          ),
        ),
      ),
    );

    final button = find.byKey(const Key('manage-assets-button'));

    expect(button, findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(manageAssetsOpened, isTrue);
  });
  testWidgets('displays foreign currency quantity and IDR valuation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final priceController = AssetPriceController(store: LocalStore());

    addTearDown(priceController.dispose);

    final holding = AssetHolding(
      assetDefinitionId: 'asset-usd',
      providerCode: 'ALPHA_VANTAGE',
      providerSymbol: 'USD/IDR',
      currencyCode: 'IDR',
      onlinePricingEnabled: true,
      assetKey: 'USD',
      name: 'US Dollar Cash',
      symbol: 'USD',
      kind: AssetKind.foreignCurrency,
      unit: 'usd',
      quantity: 1000,
      lotSize: 1,
      costBasis: 16000000,
      averageCost: 16000,
      currentPrice: 16500,
      marketValue: 16500000,
      realizedGain: 0,
      priceSource: 'Alpha Vantage FX',
      priceQuotedAt: DateTime.utc(2026, 7, 23),
      isPriceDelayed: false,
      isManualPrice: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetsDashboardScreen(
            portfolio: AssetPortfolio(
              holdings: [holding],
              totalCostBasis: 16000000,
              totalMarketValue: 16500000,
              totalUnrealizedGain: 500000,
              totalRealizedGain: 0,
            ),
            priceController: priceController,
            onManageAssets: () {},
          ),
        ),
      ),
    );

    expect(find.text('US Dollar Cash'), findsOneWidget);
    expect(find.text('USD 1,000'), findsOneWidget);
    expect(find.text('Rp 16.000 / USD'), findsOneWidget);
    expect(find.text('Rp 16.500 / USD'), findsOneWidget);
    expect(find.text('Rp 16.500.000'), findsWidgets);
    expect(find.text('+Rp 500.000'), findsWidgets);
    expect(find.textContaining('Alpha Vantage FX'), findsOneWidget);
  });
}
