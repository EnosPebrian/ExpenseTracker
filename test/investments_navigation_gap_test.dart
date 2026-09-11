import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/presentation/navigation/app_destination.dart';
import 'package:pilgrim_tracker/app/presentation/widgets/app_navigation_scaffold.dart';
import 'package:pilgrim_tracker/app/presentation/widgets/side_nav.dart';
import 'package:pilgrim_tracker/app/router.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_portfolio.dart';
import 'package:pilgrim_tracker/features/investments/domain/entities/brokerage_performance.dart';
import 'package:pilgrim_tracker/features/investments/domain/services/brokerage_activity_service.dart';
import 'package:pilgrim_tracker/features/investments/presentation/controllers/brokerage_controller.dart';
import 'package:pilgrim_tracker/features/investments/presentation/screens/investments_screen.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/widgets/account_editor_dialog.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_brokerage_metadata.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/internal_transfer_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Investments is the canonical destination between Assets and Transactions',
    () {
      expect(appDestinations[AppDestinationIndex.assets].label, 'Assets');
      expect(
        appDestinations[AppDestinationIndex.investments].label,
        'Investments',
      );
      expect(
        appDestinations[AppDestinationIndex.transactions].label,
        'Transactions',
      );
      expect(
        AppRouter.destinations,
        appDestinations.map((destination) => destination.label),
      );
    },
  );

  testWidgets(
    'desktop sidebar marks Investments active and retains navigation',
    (tester) async {
      int? selected;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AppNavigationScaffold(
            selected: AppDestinationIndex.investments,
            onSelect: (value) => selected = value,
            onQuickAdd: () {},
            child: const Text('Investment route content'),
          ),
        ),
      );

      final investmentLabel = find.descendant(
        of: find.byType(SideNav),
        matching: find.text('Investments'),
      );
      expect(investmentLabel, findsOneWidget);
      expect(tester.widget<Text>(investmentLabel).style?.color, Colors.white);
      await tester.tap(
        find.descendant(
          of: find.byType(SideNav),
          matching: find.text('Transactions'),
        ),
      );
      expect(selected, AppDestinationIndex.transactions);
    },
  );

  testWidgets(
    'mobile navigation keeps Investments and Transactions discoverable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AppNavigationScaffold(
            selected: AppDestinationIndex.investments,
            onSelect: (_) {},
            onQuickAdd: () {},
            child: const SizedBox(),
          ),
        ),
      );

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navigation.destinations, hasLength(5));
      expect(find.text('Investments'), findsWidgets);
      expect(find.text('Transactions'), findsOneWidget);
      expect(navigation.selectedIndex, AppDestinationIndex.investments);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('zero-data Investments page exposes all tabs and account action', (
    tester,
  ) async {
    var addRequested = false;
    final controller = _controller(accounts: const []);
    addTearDown(controller.dispose);
    await _pumpInvestments(
      tester,
      controller: controller,
      performance: const BrokeragePerformance(accounts: [], currencies: []),
      accounts: const [],
      onAdd: () => addRequested = true,
    );

    for (final label in const [
      'Overview',
      'Brokerage Accounts',
      'Holdings',
      'Trades',
      'Statements',
      'Performance',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('No brokerage accounts yet'), findsOneWidget);
    expect(
      find.text(
        'Add a brokerage account to track investments, holdings, trades, and portfolio performance.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('add-brokerage-account')));
    expect(addRequested, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing brokerage data is organized across functional tabs', (
    tester,
  ) async {
    final fixture = _InvestmentFixture.create();
    var importRequested = false;
    final controller = _controller(accounts: [fixture.account]);
    addTearDown(controller.dispose);
    await _pumpInvestments(
      tester,
      controller: controller,
      performance: fixture.performance,
      accounts: [fixture.account],
      transactions: [fixture.trade],
      onImport: () => importRequested = true,
    );

    expect(find.text('Portfolio value: IDR 1.200.000'), findsOneWidget);
    expect(find.text('Recent investment activity'), findsOneWidget);

    await _selectTab(tester, 'brokerageAccounts');
    expect(find.text('Alpha Broker'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Cash balance: IDR 300.000'), findsOneWidget);

    await _selectTab(tester, 'holdings');
    expect(find.text('ACME · Acme Corp'), findsOneWidget);
    expect(find.text('Market value: IDR 1.200.000'), findsOneWidget);

    await _selectTab(tester, 'trades');
    expect(find.text('Buy · ACME'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('investment-trade-trade-1')),
      findsOneWidget,
    );

    await _selectTab(tester, 'statements');
    expect(find.text('Import brokerage statements'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-brokerage-statement')));
    expect(importRequested, isTrue);

    await _selectTab(tester, 'performance');
    expect(find.textContaining('Currencies remain separate'), findsOneWidget);
    expect(find.text('Invested cost: IDR 1.000.000'), findsOneWidget);
    expect(find.text('Realized performance: IDR 70.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'brokerage account action reuses account editor preselected safely',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => AccountEditorDialog.show(
                context,
                initialAccountType: AccountType.brokerage,
                defaultCurrencyCode: 'IDR',
                transactions: const [],
                onSave: (_) async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final typeField = tester.widget<FormField<AccountType>>(
        find.byKey(const Key('account-type-field')),
      );
      expect(typeField.initialValue, AccountType.brokerage);
    },
  );
}

Future<void> _pumpInvestments(
  WidgetTester tester, {
  required BrokerageController controller,
  required BrokeragePerformance performance,
  required List<Account> accounts,
  List<Transaction> transactions = const [],
  VoidCallback? onAdd,
  VoidCallback? onImport,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InvestmentsScreen(
          bookId: 'book',
          memberId: 'member',
          performance: performance,
          accounts: accounts,
          instruments: const [],
          transactions: transactions,
          controller: controller,
          onAddBrokerageAccount: onAdd ?? () {},
          onImportStatement: onImport ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, String name) async {
  final tab = find.byKey(ValueKey('investment-tab-$name'));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

BrokerageController _controller({required List<Account> accounts}) =>
    BrokerageController(
      service: BrokerageActivityService(
        createTransaction: CreateTransaction(_NoopRepository()),
        internalTransfers: InternalTransferService(_NoopRepository()),
      ),
      accounts: () => accounts,
      instruments: () => const [],
      onRecorded: () async {},
    );

class _InvestmentFixture {
  const _InvestmentFixture({
    required this.account,
    required this.performance,
    required this.trade,
  });

  final Account account;
  final BrokeragePerformance performance;
  final Transaction trade;

  static _InvestmentFixture create() {
    final account = Account(
      id: 'broker-1',
      bookId: 'book',
      name: 'Alpha Broker',
      accountType: AccountType.brokerage,
      currencyCode: 'IDR',
      updatedAt: DateTime(2026, 9, 11),
    );
    const holding = AssetHolding(
      assetDefinitionId: 'asset-1',
      assetKey: 'ACME',
      name: 'Acme Corp',
      symbol: 'ACME',
      kind: AssetKind.stock,
      unit: 'share',
      quantity: 100,
      lotSize: 100,
      costBasis: 1000000,
      averageCost: 10000,
      currentPrice: 12000,
      marketValue: 1200000,
      realizedGain: 50000,
      priceSource: 'manual',
      priceQuotedAt: null,
      isPriceDelayed: false,
      isManualPrice: true,
    );
    const portfolio = AssetPortfolio(
      holdings: [holding],
      totalCostBasis: 1000000,
      totalMarketValue: 1200000,
      totalUnrealizedGain: 200000,
      totalRealizedGain: 50000,
    );
    final accountPerformance = BrokerageAccountPerformance(
      account: account,
      cashBalance: 300000,
      portfolio: portfolio,
      dividendIncome: 25000,
      investmentCosts: 5000,
    );
    const currency = BrokerageCurrencyPerformance(
      currencyCode: 'IDR',
      cashBalance: 300000,
      positionMarketValue: 1200000,
      positionCostBasis: 1000000,
      realizedGain: 50000,
      unrealizedGain: 200000,
      dividendIncome: 25000,
      investmentCosts: 5000,
    );
    final trade = Transaction(
      id: 'trade-1',
      bookId: 'book',
      title: 'Buy Acme',
      category: 'Investment',
      account: 'Alpha Broker -> Acme Corp',
      date: DateTime(2026, 9, 10),
      amount: 1000000,
      type: TransactionType.assetConversion,
      quantity: 100,
      unit: 'share',
      unitPrice: 10000,
      assetDefinitionId: 'asset-1',
      assetName: 'Acme Corp',
      assetSymbol: 'ACME',
      assetAction: AssetAction.buy,
      brokerageAccountId: account.id,
      brokerageActivityType: BrokerageActivityType.buy,
    );
    return _InvestmentFixture(
      account: account,
      performance: BrokeragePerformance(
        accounts: [accountPerformance],
        currencies: const [currency],
      ),
      trade: trade,
    );
  }
}

class _NoopRepository
    implements TransactionRepository, InternalTransferRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
