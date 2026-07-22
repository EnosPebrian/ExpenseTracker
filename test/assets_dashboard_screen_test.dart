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
}
