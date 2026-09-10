import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/budgets/domain/entities/monthly_category_budget.dart';
import 'package:pilgrim_tracker/features/budgets/domain/services/monthly_budget_calculator.dart';
import 'package:pilgrim_tracker/features/investments/domain/services/brokerage_activity_service.dart';
import 'package:pilgrim_tracker/features/investments/domain/services/brokerage_performance_calculator.dart';
import 'package:pilgrim_tracker/features/investments/presentation/controllers/brokerage_controller.dart';
import 'package:pilgrim_tracker/features/investments/presentation/screens/investments_screen.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/services/account_balance_calculator.dart';
import 'package:pilgrim_tracker/features/sync/data/initial_sync_store_native.dart';
import 'package:pilgrim_tracker/features/sync/domain/conflict_resolution_service.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_transport.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_brokerage_metadata.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/internal_transfer_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/beta06_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('brokerage metadata round-trips with stable transaction identity', () {
    final transaction = Transaction(
      id: 'trade-id',
      bookId: 'book',
      title: 'Buy Gold',
      category: 'Investment',
      account: 'Broker -> Gold',
      date: DateTime(2026, 9, 10),
      amount: 1000000,
      type: TransactionType.assetConversion,
      quantity: 1,
      unit: 'gram',
      unitPrice: 1000000,
      assetDefinitionId: 'asset',
      assetName: 'Gold',
      assetAction: AssetAction.buy,
      brokerageAccountId: 'broker',
      brokerageActivityType: BrokerageActivityType.buy,
    );
    final restored = Transaction.fromRecord(transaction.toRecord());
    expect(restored.id, 'trade-id');
    expect(restored.brokerageAccountId, 'broker');
    expect(restored.brokerageActivityType, BrokerageActivityType.buy);
    expect(restored.splitNumerator, isNull);
    expect(restored.splitDenominator, isNull);
  });

  test('SQLite v27 to v28 is additive and preserves existing rows', () async {
    final directory = await Directory.systemTemp.createTemp('beta08n0-v28-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/test.db';
    final store = native.LocalStore(databasePath: path);
    await store.initialize();
    await store.upsertTransaction(_ordinaryTransaction().toRecord());
    await store.db.execute('DROP INDEX idx_transactions_brokerage_account');
    await store.db.execute(
      'ALTER TABLE transactions DROP COLUMN split_denominator',
    );
    await store.db.execute(
      'ALTER TABLE transactions DROP COLUMN split_numerator',
    );
    await store.db.execute(
      'ALTER TABLE transactions DROP COLUMN brokerage_activity_type',
    );
    await store.db.execute(
      'ALTER TABLE transactions DROP COLUMN brokerage_account_id',
    );
    await store.db.execute('PRAGMA user_version = 27');
    await store.close();

    await store.initialize();
    addTearDown(store.close);
    expect(await store.getSchemaVersion(), native.LocalStore.schemaVersion);
    expect(native.LocalStore.schemaVersion, 28);
    final columns = (await store.db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((row) => row['name']).toSet();
    expect(
      columns,
      containsAll([
        'brokerage_account_id',
        'brokerage_activity_type',
        'split_numerator',
        'split_denominator',
      ]),
    );
    final row = (await store.getTransactions()).single;
    expect(row['id'], 'ordinary');
    expect(row['amount'], 125000);
    expect(row['brokerage_account_id'], isNull);
  });

  for (final platform in ['native', 'web']) {
    test(
      '$platform persists brokerage attribution and rejects cross-household account',
      () async {
        final fixture = await _Fixture.create(platform);
        addTearDown(fixture.dispose);
        final dynamic store = platform == 'native'
            ? fixture.store
            : web.LocalStore();
        if (platform == 'web') {
          await store.initialize();
          await store.activateHouseholdBackupSnapshot(
            HouseholdBackupIntegrity.prepareForRestore(
              _emptySnapshot('book-$platform'),
            ),
            replaceBookId: 'book-$platform',
          );
          store.setActiveBookId('book-$platform');
          await store.upsertAccount(
            _brokerage('book-$platform').toRecord(),
            enqueueSync: false,
          );
        }
        final bookId = 'book-$platform';
        final trade = _brokerageTrade(bookId: bookId);
        await store.upsertTransaction(trade.toRecord(), enqueueSync: false);
        final row = (await store.getTransactions()).single;
        expect(row['brokerage_account_id'], 'broker-$bookId');
        expect(row['brokerage_activity_type'], 'buy');
        expect(
          () => store.upsertTransaction(
            trade
                .copyWith(id: 'foreign', brokerageAccountId: 'missing-account')
                .toRecord(),
            enqueueSync: false,
          ),
          throwsA(isA<StateError>()),
        );
        if (platform == 'web') await store.close();
      },
    );
  }

  test(
    'manual activities reuse asset, cash, transfer, budget, and tithe authorities',
    () async {
      final fixture = await _Fixture.create('ledger');
      addTearDown(fixture.dispose);
      final service = fixture.service;
      final date = DateTime(2026, 9, 10);
      final funding = await service.recordFunding(
        bookId: fixture.bookId,
        enteredByMemberId: 'member-owner',
        brokerageAccount: fixture.brokerage,
        counterpartyAccount: fixture.cash,
        direction: BrokerageFundingDirection.deposit,
        date: date,
        amount: 2000000,
      );
      await service.recordTrade(
        bookId: fixture.bookId,
        enteredByMemberId: 'member-owner',
        brokerageAccount: fixture.brokerage,
        instrument: fixture.instrument,
        action: AssetAction.buy,
        date: date,
        grossAmount: 1000000,
        quantity: 1,
        unitPrice: 1000000,
        feeAmount: 10000,
      );
      final split = await service.recordSplit(
        bookId: fixture.bookId,
        enteredByMemberId: 'member-owner',
        brokerageAccount: fixture.brokerage,
        instrument: fixture.instrument,
        date: date.add(const Duration(days: 1)),
        numerator: 2,
        denominator: 1,
      );
      await service.recordTrade(
        bookId: fixture.bookId,
        enteredByMemberId: 'member-owner',
        brokerageAccount: fixture.brokerage,
        instrument: fixture.instrument,
        action: AssetAction.sell,
        date: date.add(const Duration(days: 2)),
        grossAmount: 700000,
        quantity: 1,
        unitPrice: 700000,
        feeAmount: 5000,
      );
      for (final entry in [
        (BrokerageActivityType.dividend, 50000),
        (BrokerageActivityType.fee, 10000),
        (BrokerageActivityType.tax, 5000),
      ]) {
        await service.recordCashActivity(
          bookId: fixture.bookId,
          enteredByMemberId: 'member-owner',
          brokerageAccount: fixture.brokerage,
          activityType: entry.$1,
          date: date.add(const Duration(days: 3)),
          amount: entry.$2,
          instrument: fixture.instrument,
        );
      }

      final transactions = await fixture.repository.getAll();
      final performance = BrokeragePerformanceCalculator.calculate(
        accounts: [fixture.cash, fixture.brokerage],
        transactions: transactions,
        assetDefinitions: [fixture.instrument],
        marketPrices: [
          AssetMarketPrice.manual(
            assetKey: fixture.instrument.marketPriceKey,
            symbol: fixture.instrument.symbol,
            price: 1200000,
            currencyCode: 'IDR',
            unit: 'gram',
          ),
        ],
      );
      final account = performance.accounts.single;
      expect(account.cashBalance, 1720000);
      expect(account.portfolio.holdings.single.quantity, 1);
      expect(account.portfolio.totalCostBasis, 505000);
      expect(account.portfolio.totalRealizedGain, 190000);
      expect(account.portfolio.totalMarketValue, 1200000);
      expect(account.dividendIncome, 50000);
      expect(account.investmentCosts, 15000);
      expect(account.realizedPerformance, 225000);
      expect(account.netWorth, 2920000);
      expect(performance.currencies.single.currencyCode, 'IDR');
      expect(split.amount, 0);
      expect(split.splitNumerator, 2);

      expect(
        AccountBalanceCalculator.calculate(
          account: fixture.cash,
          transactions: transactions,
        ),
        -2000000,
      );
      final summary = FinancialSummary.calculate(
        transactions: transactions,
        transferLinks: [funding.link],
        referenceDate: date,
      );
      expect(summary.monthlyIncome, 0);
      expect(summary.monthlyExpenses, 0);
      expect(summary.monthlyTithe, 0);
      final budget = MonthlyBudgetCalculator.calculate(
        month: date,
        budgets: [
          MonthlyCategoryBudget(
            id: 'budget',
            bookId: fixture.bookId,
            categoryId: 'category-expense',
            monthStart: DateTime(2026, 9),
            limitMinor: 1000000,
            currencyCode: 'IDR',
          ),
        ],
        transactions: transactions,
        categoryNamesById: const {'category-expense': 'Groceries'},
        pairedTransactionIds: funding.link.transactionIds,
      );
      expect(budget.totalSpendMinor, 0);
    },
  );

  test('sell cannot exceed post-split quantity', () async {
    final fixture = await _Fixture.create('oversell');
    addTearDown(fixture.dispose);
    await fixture.service.recordTrade(
      bookId: fixture.bookId,
      enteredByMemberId: null,
      brokerageAccount: fixture.brokerage,
      instrument: fixture.instrument,
      action: AssetAction.buy,
      date: DateTime(2026, 1, 1),
      grossAmount: 1000000,
      quantity: 1,
      unitPrice: 1000000,
    );
    await fixture.service.recordSplit(
      bookId: fixture.bookId,
      enteredByMemberId: null,
      brokerageAccount: fixture.brokerage,
      instrument: fixture.instrument,
      date: DateTime(2026, 1, 2),
      numerator: 2,
      denominator: 1,
    );
    await expectLater(
      fixture.service.recordTrade(
        bookId: fixture.bookId,
        enteredByMemberId: null,
        brokerageAccount: fixture.brokerage,
        instrument: fixture.instrument,
        action: AssetAction.sell,
        date: DateTime(2026, 1, 3),
        grossAmount: 3000000,
        quantity: 3,
        unitPrice: 1000000,
      ),
      throwsA(isA<TransactionValidationException>()),
    );
  });

  test('split rejects unsupported fractional stock quantity', () async {
    final fixture = await _Fixture.create(
      'fractional-split',
      instrument: _stockInstrument('book-fractional-split'),
    );
    addTearDown(fixture.dispose);
    await fixture.service.recordTrade(
      bookId: fixture.bookId,
      enteredByMemberId: null,
      brokerageAccount: fixture.brokerage,
      instrument: fixture.instrument,
      action: AssetAction.buy,
      date: DateTime(2026, 1, 1),
      grossAmount: 100000,
      quantity: 100,
      unitPrice: 1000,
    );
    await expectLater(
      fixture.service.recordSplit(
        bookId: fixture.bookId,
        enteredByMemberId: null,
        brokerageAccount: fixture.brokerage,
        instrument: fixture.instrument,
        date: DateTime(2026, 1, 2),
        numerator: 1,
        denominator: 3,
      ),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          contains('whole shares'),
        ),
      ),
    );
  });

  test(
    'performance keeps currencies separate and handles 5000 activities linearly',
    () {
      final idr = _brokerage('book', id: 'idr', currency: 'IDR');
      final usd = _brokerage('book', id: 'usd', currency: 'USD');
      final transactions = <Transaction>[
        for (var index = 0; index < 2500; index++)
          _investmentCash(
            id: 'idr-$index',
            account: idr,
            amount: 1,
            type: BrokerageActivityType.dividend,
          ),
        for (var index = 0; index < 2500; index++)
          _investmentCash(
            id: 'usd-$index',
            account: usd,
            amount: 2,
            type: BrokerageActivityType.dividend,
          ),
      ];
      final stopwatch = Stopwatch()..start();
      final result = BrokeragePerformanceCalculator.calculate(
        accounts: [idr, usd],
        transactions: transactions,
      );
      stopwatch.stop();
      expect(result.currencies, hasLength(2));
      expect(result.currencies.first.dividendIncome, 2500);
      expect(result.currencies.last.dividendIncome, 5000);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    },
  );

  test(
    'v7 backup preserves brokerage metadata and v6 remains compatible',
    () async {
      final snapshot = _emptySnapshot('book-backup');
      snapshot['accounts'] = [_brokerage('book-backup').toRecord()];
      snapshot['asset_definitions'] = [_instrument('book-backup').toRecord()];
      snapshot['transactions'] = [
        _brokerageTrade(bookId: 'book-backup').toRecord(),
      ];
      final codec = PortableBackupCodec(databaseSchemaVersion: 28);
      final v7 = await codec.encode(snapshot: snapshot, password: 'password');
      expect(v7.manifest.formatVersion, 7);
      final decoded = await codec.decode(v7.bytes, 'password');
      expect(
        decoded.snapshot['transactions']!.single['brokerage_account_id'],
        'broker-book-backup',
      );
      final clone = HouseholdBackupIntegrity.prepareForRestore(
        decoded.snapshot,
        remapAsCopy: true,
      );
      expect(
        clone['transactions']!.single['brokerage_account_id'],
        clone['accounts']!.firstWhere(
          (row) => row['account_type'] == 'brokerage',
        )['id'],
      );

      final v6 = await codec.encode(
        snapshot: snapshot,
        password: 'password',
        formatVersion: 6,
      );
      final decodedV6 = await codec.decode(v6.bytes, 'password');
      expect(
        decodedV6.snapshot['transactions']!.single['brokerage_account_id'],
        isNull,
      );
    },
  );

  test('backup rejects malformed brokerage activity without mutation', () {
    final snapshot = _emptySnapshot('book-invalid-backup');
    snapshot['accounts'] = [_brokerage('book-invalid-backup').toRecord()];
    snapshot['asset_definitions'] = [
      _instrument('book-invalid-backup').toRecord(),
    ];
    snapshot['transactions'] = [
      {
        ..._brokerageTrade(bookId: 'book-invalid-backup').toRecord(),
        'transaction_type': 'income',
      },
    ];
    final original = snapshot['transactions']!.single['transaction_type'];
    expect(
      () => HouseholdBackupIntegrity.validate(snapshot),
      throwsA(isA<BackupValidationException>()),
    );
    expect(snapshot['transactions']!.single['transaction_type'], original);
  });

  test(
    'offline write queues once and remote apply preserves metadata without echo',
    () async {
      final source = await _Fixture.create('sync-source');
      addTearDown(source.dispose);
      await source.store.db.update(
        'books',
        {'remote_linked_at': DateTime(2026, 9, 10).millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [source.bookId],
      );
      await source.store.setSyncInitializationState(source.bookId, 'ready');
      final dividend = await source.service.recordCashActivity(
        bookId: source.bookId,
        enteredByMemberId: 'member-owner',
        brokerageAccount: source.brokerage,
        activityType: BrokerageActivityType.dividend,
        date: DateTime(2026, 9, 10),
        amount: 50000,
      );
      expect(await source.store.getPendingSyncCount(source.bookId), 1);
      final operation = (await source.store.getEligibleSyncOperations(
        source.bookId,
      )).single;
      expect(operation['payload_json'], contains('brokerage_account_id'));

      final target = await _Fixture.create('sync-target');
      addTearDown(target.dispose);
      final remote = dividend.copyWith(
        bookId: target.bookId,
        brokerageAccountId: target.brokerage.id,
        syncStatus: 'synced',
      );
      await target.store.setSyncInitializationState(target.bookId, 'ready');
      await target.store.applyRemoteSyncBatch(
        target.bookId,
        changes: [
          {
            'entity_type': 'transactions',
            'entity_id': remote.id,
            'payload': remote.toRecord(),
          },
        ],
        finalSequence: 7,
      );
      expect(await target.store.getPendingSyncCount(target.bookId), 0);
      final stored = Transaction.fromRecord(
        (await target.store.getTransactions()).single,
      );
      expect(stored.brokerageAccountId, target.brokerage.id);
      expect(stored.brokerageActivityType, BrokerageActivityType.dividend);

      final oldClientPayload =
          stored.copyWith(title: 'Dividend updated').toRecord()
            ..remove('brokerage_account_id')
            ..remove('brokerage_activity_type')
            ..remove('split_numerator')
            ..remove('split_denominator');
      await target.store.applyRemoteSyncBatch(
        target.bookId,
        changes: [
          {
            'entity_type': 'transactions',
            'entity_id': stored.id,
            'payload': oldClientPayload,
          },
        ],
        finalSequence: 8,
      );
      final preserved = Transaction.fromRecord(
        (await target.store.getTransactions()).single,
      );
      expect(preserved.brokerageAccountId, target.brokerage.id);
      expect(preserved.brokerageActivityType, BrokerageActivityType.dividend);
      expect(await target.store.getPendingSyncCount(target.bookId), 0);
    },
  );

  test(
    'initial-sync bootstrap converges brokerage metadata without echo',
    () async {
      final source = await _Fixture.create('bootstrap');
      addTearDown(source.dispose);
      await source.store.db.update(
        'books',
        {'remote_linked_at': DateTime(2026, 9, 10).millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [source.bookId],
      );
      await source.service.recordTrade(
        bookId: source.bookId,
        enteredByMemberId: 'member-owner',
        brokerageAccount: source.brokerage,
        instrument: source.instrument,
        action: AssetAction.buy,
        date: DateTime(2026, 9, 10),
        grossAmount: 1000000,
        quantity: 1,
        unitPrice: 1000000,
      );
      final sourceAdapter = InitialSyncStoreAdapter(source.store);
      final manifest = await sourceAdapter.captureUploadSnapshot(source.bookId);

      final targetDirectory = await Directory.systemTemp.createTemp(
        'beta08n0-bootstrap-',
      );
      final targetStore = native.LocalStore(
        databasePath: '${targetDirectory.path}/target.db',
      );
      await targetStore.initialize();
      addTearDown(() async {
        await targetStore.close();
        await targetDirectory.delete(recursive: true);
      });
      final targetAdapter = InitialSyncStoreAdapter(targetStore);
      await targetAdapter.startInitialization(
        bookId: source.bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'bootstrap-session',
        manifest: manifest,
      );
      for (final entityType in initialSyncEntityOrder) {
        final rows = await sourceAdapter.readUploadRows(
          source.bookId,
          entityType,
        );
        await targetAdapter.stageDownloadBatch(
          source.bookId,
          InitialSyncBatch(
            entityType: entityType,
            rows: rows,
            nextCursor: rows.lastOrNull?['id'] as String?,
            complete: true,
          ),
        );
      }
      await targetAdapter.activateDownload(
        bookId: source.bookId,
        manifest: manifest,
        authUserId: 'auth-owner',
      );
      final transaction = Transaction.fromRecord(
        (await targetStore.getTransactions()).single,
      );
      expect(transaction.brokerageAccountId, source.brokerage.id);
      expect(transaction.brokerageActivityType, BrokerageActivityType.buy);
      expect(await targetStore.getPendingSyncCount(source.bookId), 0);
    },
  );

  testWidgets('responsive brokerage page exposes explicit activity review', (
    tester,
  ) async {
    final account = _brokerage('book-widget');
    final instrument = _instrument('book-widget');
    final controller = BrokerageController(
      service: BrokerageActivityService(
        createTransaction: CreateTransaction(_NoopRepository()),
        internalTransfers: InternalTransferService(_NoopRepository()),
      ),
      accounts: () => [account],
      instruments: () => [instrument],
      onRecorded: () async {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvestmentsScreen(
            bookId: 'book-widget',
            memberId: null,
            performance: BrokeragePerformanceCalculator.calculate(
              accounts: [account],
              transactions: const [],
            ),
            accounts: [account],
            instruments: [instrument],
            transactions: const [],
            controller: controller,
            onOpenAccounts: () {},
            onImportStatement: () {},
          ),
        ),
      ),
    );
    expect(find.text('Brokerage'), findsOneWidget);
    expect(find.text('No open positions.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-brokerage-activity')));
    await tester.pumpAndSettle();
    expect(find.text('Record investment activity'), findsOneWidget);
    expect(find.byKey(const Key('brokerage-activity-type')), findsOneWidget);
    expect(find.byKey(const Key('save-brokerage-activity')), findsOneWidget);
  });

  test(
    'conflict merge cannot mix brokerage account and activity identity',
    () async {
      final backend = _ConflictBackend();
      final service = ConflictResolutionService(
        repository: backend,
        transport: backend,
      );
      final conflict = SyncConflict(
        id: 'conflict',
        bookId: 'book',
        entityType: 'transactions',
        entityId: 'trade',
        operationId: 'operation',
        baseVersion: 1,
        serverVersion: 2,
        localPayload: const {
          'brokerage_account_id': 'broker-a',
          'brokerage_activity_type': 'buy',
          'split_numerator': null,
          'split_denominator': null,
        },
        serverPayload: const {
          'brokerage_account_id': 'broker-b',
          'brokerage_activity_type': 'sell',
          'split_numerator': null,
          'split_denominator': null,
        },
        createdAt: DateTime(2026, 9, 10),
      );
      await expectLater(
        service.resolve(
          conflict,
          ConflictResolutionType.manualMerge,
          mergedPayload: const {
            'brokerage_account_id': 'broker-a',
            'brokerage_activity_type': 'sell',
            'split_numerator': null,
            'split_denominator': null,
          },
        ),
        throwsStateError,
      );
      expect(backend.calls, 0);
      await service.resolve(
        conflict,
        ConflictResolutionType.manualMerge,
        mergedPayload: conflict.localPayload,
      );
      expect(backend.calls, 1);
    },
  );
}

class _Fixture {
  _Fixture({
    required this.directory,
    required this.store,
    required this.bookId,
    required this.cash,
    required this.brokerage,
    required this.instrument,
    required this.repository,
    required this.service,
  });

  final Directory directory;
  final native.LocalStore store;
  final String bookId;
  final Account cash;
  final Account brokerage;
  final AssetDefinition instrument;
  final LocalTransactionRepository repository;
  final BrokerageActivityService service;

  static Future<_Fixture> create(
    String suffix, {
    AssetDefinition? instrument,
  }) async {
    final bookId = 'book-$suffix';
    final directory = await Directory.systemTemp.createTemp('beta08n0-');
    final store = native.LocalStore(databasePath: '${directory.path}/test.db');
    await store.initialize();
    await store.activateHouseholdBackupSnapshot(
      HouseholdBackupIntegrity.prepareForRestore(_emptySnapshot(bookId)),
      replaceBookId: bookId,
    );
    store.setActiveBookId(bookId);
    final cash = Account(
      id: 'cash-$bookId',
      bookId: bookId,
      name: 'Cash',
      accountType: AccountType.bank,
      openingBalanceDate: DateTime(2026, 1, 1),
    );
    final brokerage = _brokerage(bookId);
    await store.upsertAccount(cash.toRecord(), enqueueSync: false);
    await store.upsertAccount(brokerage.toRecord(), enqueueSync: false);
    final effectiveInstrument = instrument ?? _instrument(bookId);
    await store.upsertAssetDefinition(
      effectiveInstrument.toRecord(),
      enqueueSync: false,
    );
    final repository = LocalTransactionRepository(store as dynamic);
    final create = CreateTransaction(
      repository,
      assetDefinitionResolver: (id) =>
          id == effectiveInstrument.id ? effectiveInstrument : null,
    );
    final transfer = InternalTransferService(repository);
    return _Fixture(
      directory: directory,
      store: store,
      bookId: bookId,
      cash: cash,
      brokerage: brokerage,
      instrument: effectiveInstrument,
      repository: repository,
      service: BrokerageActivityService(
        createTransaction: create,
        internalTransfers: transfer,
      ),
    );
  }

  Future<void> dispose() async {
    await store.close();
    await directory.delete(recursive: true);
  }
}

Map<String, List<Map<String, Object?>>> _emptySnapshot(String bookId) {
  final snapshot = beta06Snapshot(bookId: bookId);
  snapshot['transactions'] = [];
  snapshot['accounts'] = [];
  snapshot['asset_definitions'] = [];
  snapshot['manual_market_prices'] = [];
  return snapshot;
}

Account _brokerage(String bookId, {String? id, String currency = 'IDR'}) =>
    Account(
      id: id ?? 'broker-$bookId',
      bookId: bookId,
      name: 'Broker ${id ?? bookId}',
      accountType: AccountType.brokerage,
      currencyCode: currency,
      openingBalanceDate: DateTime(2026, 1, 1),
    );

AssetDefinition _instrument(String bookId) => AssetDefinition(
  id: 'asset-$bookId',
  bookId: bookId,
  displayName: 'Gold',
  kind: AssetKind.gold,
  symbol: 'XAU',
  providerCode: null,
  providerSymbol: null,
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: 'gram',
  lotSize: 1,
  onlinePricingEnabled: false,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  deletedAt: null,
  version: 1,
  deviceId: 'device',
  syncStatus: 'local_only',
);

AssetDefinition _stockInstrument(String bookId) => AssetDefinition(
  id: 'asset-$bookId',
  bookId: bookId,
  displayName: 'Pilgrim Stock',
  kind: AssetKind.stock,
  symbol: 'PLGR',
  providerCode: null,
  providerSymbol: null,
  exchangeCode: 'IDX',
  currencyCode: 'IDR',
  unit: 'share',
  lotSize: 100,
  onlinePricingEnabled: false,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  deletedAt: null,
  version: 1,
  deviceId: 'device',
  syncStatus: 'local_only',
);

Transaction _ordinaryTransaction() => Transaction(
  id: 'ordinary',
  title: 'Expense',
  category: 'Groceries',
  account: 'Cash',
  date: DateTime(2026, 9, 10),
  amount: 125000,
  type: TransactionType.expense,
);

Transaction _brokerageTrade({required String bookId}) => Transaction(
  id: 'trade-$bookId',
  bookId: bookId,
  title: 'Buy Gold',
  category: 'Investment',
  account: 'Broker $bookId -> Gold',
  date: DateTime(2026, 9, 10),
  amount: 1000000,
  type: TransactionType.assetConversion,
  quantity: 1,
  unit: 'gram',
  unitPrice: 1000000,
  assetDefinitionId: 'asset-$bookId',
  assetName: 'Gold',
  assetAction: AssetAction.buy,
  brokerageAccountId: 'broker-$bookId',
  brokerageActivityType: BrokerageActivityType.buy,
);

Transaction _investmentCash({
  required String id,
  required Account account,
  required int amount,
  required BrokerageActivityType type,
}) => Transaction(
  id: id,
  bookId: account.bookId,
  title: type.label,
  category: 'Investment',
  account: account.name,
  date: DateTime(2026, 9, 10),
  amount: amount,
  type: TransactionType.investment,
  brokerageAccountId: account.id,
  brokerageActivityType: type,
);

class _NoopRepository
    implements TransactionRepository, InternalTransferRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConflictBackend
    implements SyncConflictRepository, ConflictResolutionTransport {
  int calls = 0;

  @override
  Future<bool> beginResolution(String conflictId, String operationId) async =>
      true;

  @override
  Future<ConflictResolutionResult> resolveConflict({
    required SyncConflict conflict,
    required String resolutionOperationId,
    required ConflictResolutionType resolutionType,
    Map<String, Object?>? resolvedPayload,
  }) async {
    calls++;
    return ConflictResolutionResult(
      status: 'resolved',
      canonicalPayload: resolvedPayload,
    );
  }

  @override
  Future<void> completeResolution(
    String conflictId, {
    required String resolution,
    required Map<String, Object?> canonicalPayload,
    required int serverSequence,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
