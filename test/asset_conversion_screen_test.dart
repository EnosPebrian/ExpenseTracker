import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_conversion_controller.dart';
import 'package:pilgrim_tracker/features/assets/presentation/screens/asset_conversion_screen.dart';
import 'package:pilgrim_tracker/features/assets/presentation/widgets/asset_fee_fields.dart';
import 'package:pilgrim_tracker/features/assets/presentation/widgets/asset_sale_availability.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';

void main() {
  testWidgets('asset conversion waits for persistence before showing success', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final completer = Completer<void>();
    Transaction? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos', 'BNI Enos'],
            assets: [_goldDefinition()],
            onSave: (transaction) {
              submitted = transaction;
              return completer.future;
            },
          ),
        ),
      ),
    );

    final saveButton = find.widgetWithText(FilledButton, 'Record conversion');

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(submitted, isNotNull);
    expect(submitted!.type, TransactionType.assetConversion);
    expect(submitted!.assetName, 'Gold Holdings');
    expect(submitted!.assetDefinitionId, 'asset-gold');
    expect(submitted!.assetAction, AssetAction.buy);

    expect(find.text('Saving...'), findsOneWidget);

    expect(find.text('Asset conversion saved locally'), findsNothing);

    completer.complete();

    await tester.pumpAndSettle();

    expect(find.text('Asset conversion saved locally'), findsOneWidget);

    expect(find.text('Record conversion'), findsOneWidget);
  });

  testWidgets(
    'asset conversion keeps form values and displays persistence failure',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var saveCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssetConversionScreen(
              accounts: const ['Cash Enos', 'BNI Enos'],
              assets: [_goldDefinition()],
              onSave: (transaction) async {
                saveCount++;

                throw StateError('database unavailable');
              },
            ),
          ),
        ),
      );

      final saveButton = find.widgetWithText(FilledButton, 'Record conversion');

      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(saveCount, 1);

      expect(find.textContaining('database unavailable'), findsOneWidget);

      expect(find.text('Asset conversion saved locally'), findsNothing);

      final cashField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Trade amount',
        ),
      );

      final quantityField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Quantity received',
        ),
      );

      expect(cashField.controller?.text, '50.000.000');

      expect(quantityField.controller?.text, '20');

      final enabledButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record conversion'),
      );

      expect(enabledButton.onPressed, isNotNull);
    },
  );

  testWidgets('foreign currency conversion uses currency-specific fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            onSave: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Trade amount'), findsOneWidget);
    expect(find.text('USD received'), findsAtLeastNWidgets(1));
    expect(
      find.text('Calculated rate: Rp 2.500.000 per USD'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('shares / lot'), findsNothing);

    final controller = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'USD received',
      ),
    );

    expect(controller.decoration?.suffixText, 'usd');
  });

  testWidgets('sell shows availability and does not submit an oversell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var saveCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            existingTransactionsProvider: () => [_usdPurchase(1000)],
            onSave: (_) async {
              saveCount++;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sell asset'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'USD sold',
      ),
      '1500',
    );
    await tester.pump();

    expect(find.text('Available: USD 1,000'), findsOneWidget);
    expect(find.textContaining('Requested: USD 1500'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Record conversion'),
    );
    expect(button.onPressed, isNull);
    expect(saveCount, 0);
  });

  testWidgets('exact available quantity can be sold', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var saveCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            existingTransactionsProvider: () => [_usdPurchase(1000)],
            onSave: (_) async {
              saveCount++;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sell asset'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'USD sold',
      ),
      '1000',
    );
    await tester.pump();

    expect(find.text('Available: USD 1,000'), findsOneWidget);
    expect(find.textContaining('You can sell up to'), findsNothing);

    final saveButton = find.widgetWithText(FilledButton, 'Record conversion');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(saveCount, 1);
  });

  testWidgets('sell availability does not overflow a narrow layout', (
    tester,
  ) async {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
      existingTransactionsProvider: () => [_usdPurchase(1000)],
    );
    addTearDown(controller.dispose);
    controller.setSellAsset(true);
    controller.quantityController.text = '1500';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: AssetSaleAvailability(controller: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Available: USD 1,000'), findsOneWidget);
    expect(find.textContaining('Requested: USD 1500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buy fee options and total-paid summary are displayed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            onSave: (_) async {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Transaction fee',
      ),
      '50000',
    );
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<AssetFeeTreatment>));
    await tester.pumpAndSettle();
    expect(find.text('No fee'), findsOneWidget);
    expect(find.text('Add fee to cost basis'), findsAtLeastNWidgets(1));
    expect(find.text('Total paid'), findsOneWidget);
    expect(find.text('Rp 50.050.000'), findsAtLeastNWidgets(1));
  });

  testWidgets('sell fee options and net-received summary are displayed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            existingTransactionsProvider: () => [_usdPurchase(1000)],
            onSave: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sell asset'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Transaction fee',
      ),
      '40000',
    );
    await tester.pump();

    expect(find.text('Deduct fee from proceeds'), findsAtLeastNWidgets(1));
    expect(find.text('Net received'), findsOneWidget);
    expect(find.text('Rp 49.960.000'), findsAtLeastNWidgets(1));
  });

  testWidgets('invalid fee is shown and action switch resets handling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            existingTransactionsProvider: () => [_usdPurchase(1000)],
            onSave: (_) async {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Transaction fee',
      ),
      '40000',
    );
    await tester.pump();
    await tester.tap(find.text('Sell asset'));
    await tester.pump();

    expect(find.text('No fee'), findsAtLeastNWidgets(1));
    expect(
      find.text('Choose how to handle the transaction fee.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Gross proceeds',
      ),
      '40000',
    );
    await tester.tap(find.byType(DropdownButton<AssetFeeTreatment>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deduct fee from proceeds').last);
    await tester.pumpAndSettle();

    expect(
      find.text('The transaction fee must be less than the gross sale amount.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Record conversion'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('fee fields do not overflow a narrow layout', (tester) async {
    final controller = AssetConversionController(
      accounts: const ['Cash Enos'],
      assets: [_usdDefinition()],
    );
    addTearDown(controller.dispose);
    controller.feeController.text = '50000';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: AssetFeeFields(controller: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Add fee to cost basis'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('separate fee summaries distinguish accounting and cash effect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            existingTransactionsProvider: () => [_usdPurchase(1000)],
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Transaction fee',
      ),
      '100000',
    );
    await tester.pump();
    final feeTreatment = find.byType(DropdownButton<AssetFeeTreatment>);
    await tester.ensureVisible(feeTreatment);
    await tester.pumpAndSettle();
    await tester.tap(feeTreatment);
    await tester.pumpAndSettle();
    expect(find.text('Record fee as expense'), findsOneWidget);
    await tester.tap(find.text('Record fee as expense'));
    await tester.pumpAndSettle();

    expect(find.text('Fee expense'), findsOneWidget);
    expect(find.text('Total cash outflow'), findsOneWidget);
    expect(find.text('Cost basis added'), findsOneWidget);
    expect(find.text('Rp 50.000.000'), findsAtLeastNWidgets(1));
    expect(find.text('Rp 50.100.000'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Sell asset'));
    await tester.pumpAndSettle();
    expect(find.text('Separate fee expense'), findsOneWidget);
    expect(find.text('Net cash effect'), findsOneWidget);
    expect(find.text('Gross proceeds'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid currency precision renders without narrow overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_usdDefinition()],
            onSave: (_) async {},
          ),
        ),
      ),
    );
    final quantityField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'USD received',
    );
    await tester.enterText(quantityField, '1000.257');
    await tester.pump();

    expect(find.text('USD supports up to 2 decimal places.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Record conversion'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock form shows lot hint, derived lots, and validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_stockDefinition()],
            onSave: (_) async {},
          ),
        ),
      ),
    );
    final quantityField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Quantity received',
    );
    await tester.enterText(quantityField, '150');
    await tester.pump();

    expect(find.text('1 lot = 100 shares'), findsOneWidget);
    expect(find.text('150 shares · 1.5 lots'), findsAtLeastNWidgets(1));
    expect(find.textContaining('100, 200, 300'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('odd-lot cleanup sale explains residue and remainder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_stockDefinition()],
            existingTransactionsProvider: () => [
              _stockTrade(250, AssetAction.buy),
            ],
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sell asset'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Quantity sold',
      ),
      '50',
    );
    await tester.pump();

    expect(find.text('Available: 250 shares · 2.5 lots'), findsOneWidget);
    expect(
      find.text('This position contains 50 odd-lot shares.'),
      findsOneWidget,
    );
    expect(find.text('Odd-lot cleanup: 50 shares'), findsOneWidget);
    expect(find.text('Remaining: 200 shares · 2 lots'), findsOneWidget);
  });

  testWidgets('non-stock and lot-size-one forms omit lot UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_goldDefinition()],
            onSave: (_) async {},
          ),
        ),
      ),
    );
    expect(find.textContaining('1 lot ='), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetConversionScreen(
            accounts: const ['Cash Enos'],
            assets: [_stockDefinition(symbol: 'AAPL', lotSize: 1)],
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('1 lot ='), findsNothing);
  });
}

Transaction _stockTrade(double quantity, AssetAction action) {
  final date = DateTime(2026, 7, 1);
  return Transaction(
    id: 'stock-${action.name}',
    title: 'BBCA trade',
    category: 'Asset conversion',
    account: action == AssetAction.buy
        ? 'Cash Enos -> Bank Central Asia'
        : 'Bank Central Asia -> Cash Enos',
    date: date,
    amount: (quantity * 10000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: 'share',
    unitPrice: 10000,
    assetDefinitionId: 'asset-bbca',
    assetName: 'Bank Central Asia',
    assetSymbol: 'BBCA',
    assetAction: action,
    createdAt: date,
    updatedAt: date,
  );
}

AssetDefinition _stockDefinition({String symbol = 'BBCA', int lotSize = 100}) {
  return AssetDefinition(
    id: symbol == 'BBCA' ? 'asset-bbca' : 'asset-${symbol.toLowerCase()}',
    displayName: symbol == 'BBCA' ? 'Bank Central Asia' : 'Apple',
    kind: AssetKind.stock,
    symbol: symbol,
    providerCode: null,
    providerSymbol: null,
    exchangeCode: symbol == 'BBCA' ? 'IDX' : 'NASDAQ',
    currencyCode: 'IDR',
    unit: 'share',
    lotSize: lotSize,
    onlinePricingEnabled: false,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deletedAt: null,
    version: 1,
    deviceId: 'test',
    syncStatus: 'local_only',
  );
}

Transaction _usdPurchase(double quantity) {
  final date = DateTime(2026, 7, 1);
  return Transaction(
    id: 'usd-buy',
    title: 'USD acquisition',
    category: 'Asset conversion',
    account: 'Cash Enos -> US Dollar Cash',
    date: date,
    amount: (quantity * 16200).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: 'usd',
    unitPrice: 16200,
    assetDefinitionId: 'asset-usd',
    assetName: 'US Dollar Cash',
    assetSymbol: 'USD',
    assetAction: AssetAction.buy,
    createdAt: date,
    updatedAt: date,
  );
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

AssetDefinition _usdDefinition() {
  return AssetDefinition(
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
    createdAt: DateTime.utc(2026, 7, 23),
    updatedAt: DateTime.utc(2026, 7, 23),
    deletedAt: null,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}
