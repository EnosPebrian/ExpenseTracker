import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_commit_service.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_models.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_planner.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_posting.dart';
import 'package:pilgrim_tracker/features/investments/presentation/controllers/brokerage_import_controller.dart';
import 'package:pilgrim_tracker/features/investments/presentation/screens/brokerage_import_screen.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_brokerage_metadata.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/beta06_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const planner = BrokerageImportPlanner();
  final broker = Account(
    id: 'broker',
    bookId: 'book',
    name: 'Brokerage USD',
    accountType: AccountType.brokerage,
    currencyCode: 'USD',
  );
  final cash = Account(
    id: 'cash',
    bookId: 'book',
    name: 'Cash USD',
    accountType: AccountType.bank,
    currencyCode: 'USD',
  );
  final instrument = _instrument();

  test('canonical statement maps every supported brokerage activity', () async {
    final source = _source([
      _row(
        2,
        '2026-01-01',
        'BUY',
        symbol: 'AAPL',
        quantity: '10',
        price: '100',
        gross: '1000',
        fee: '1',
      ),
      _row(
        3,
        '2026-01-02',
        'SELL',
        symbol: 'AAPL',
        quantity: '2',
        price: '150',
        gross: '300',
        tax: '2',
      ),
      _row(4, '2026-01-03', 'DIVIDEND', symbol: 'AAPL', gross: '20'),
      _row(5, '2026-01-04', 'FEE', gross: '5'),
      _row(6, '2026-01-05', 'TAX', gross: '3'),
      _row(7, '2026-01-06', 'DEPOSIT', gross: '500'),
      _row(8, '2026-01-07', 'WITHDRAWAL', gross: '50'),
      _row(
        9,
        '2026-01-08',
        'SPLIT',
        symbol: 'AAPL',
        numerator: '2',
        denominator: '1',
      ),
    ]);
    final preview = await planner.build(
      source: source,
      mapping: canonicalBrokerageMappingFor(source.headers)!,
      brokerageAccount: broker,
      activeBookId: 'book',
      instruments: [instrument],
      existingTransactions: const [],
      existingTransferLinks: const [],
      counterpartyAccount: cash,
    );

    expect(
      preview.drafts.map((draft) => draft.activityType).toSet(),
      BrokerageActivityType.values.toSet(),
    );
    expect(
      preview.drafts,
      everyElement(
        predicate<BrokerageImportDraft>((draft) => !draft.hasBlockingIssue),
      ),
    );
    expect(preview.readyCount, 8);
    expect(preview.drafts[1].brokerRealizedPnl, isNull);
    expect(preview.drafts[1].issues, isEmpty);
  });

  test(
    'external headers require explicit mapping and preserve source fields',
    () async {
      const source = CsvParsedSource(
        fileName: 'external.csv',
        fileFingerprint: 'external-file',
        delimiter: ';',
        headers: ['When', 'Action', 'Ticker', 'Cash', 'Memo'],
        rows: [
          CsvSourceRow(
            rowNumber: 2,
            identityKey: 'broker-42',
            values: ['2026-03-04', 'DIVIDEND', 'AAPL', '12.34', 'Quarterly'],
          ),
        ],
        headerMode: CsvHeaderMode.firstRowHeaders,
      );
      expect(canonicalBrokerageMappingFor(source.headers), isNull);
      final preview = await planner.build(
        source: source,
        mapping: const BrokerageStatementMapping(
          dateColumn: 0,
          activityColumn: 1,
          instrumentColumn: 2,
          grossAmountColumn: 3,
          noteColumn: 4,
          decimalSeparator: CsvSeparator.period,
        ),
        brokerageAccount: broker,
        activeBookId: 'book',
        instruments: [instrument],
        existingTransactions: const [],
        existingTransferLinks: const [],
      );
      expect(preview.drafts.single.note, 'Quarterly');
      expect(preview.drafts.single.sourceRowIdentity, 'broker-42');
      expect(preview.drafts.single.grossAmount, 1234);
    },
  );

  test(
    'unknown activity blocks until explicit resolution without changing identity',
    () async {
      final source = _source([
        _row(2, '2026-01-01', 'REINVEST', symbol: 'AAPL', gross: '10'),
      ]);
      final preview = await _plan(planner, source, broker, cash, [instrument]);
      final unresolved = preview.drafts.single;
      expect(unresolved.activityType, isNull);
      expect(unresolved.hasBlockingIssue, isTrue);
      final resolved = planner.resolveActivity(
        draft: unresolved,
        activityType: BrokerageActivityType.dividend,
        activeBookId: 'book',
        brokerageAccount: broker,
        existingTransactions: const [],
        existingTransferLinks: const [],
        instruments: [instrument],
      );
      expect(resolved.eventId, unresolved.eventId);
      expect(resolved.sourceRowFingerprint, unresolved.sourceRowFingerprint);
      expect(resolved.canCommit, isTrue);
    },
  );

  test(
    'unknown instruments are never created silently and support map or create',
    () async {
      final source = _source([
        _row(
          2,
          '2026-01-01',
          'BUY',
          symbol: 'MSFT',
          quantity: '1',
          price: '100',
          gross: '100',
        ),
      ]);
      final unresolved = (await _plan(planner, source, broker, cash, [
        instrument,
      ])).drafts.single;
      expect(unresolved.needsInstrumentResolution, isTrue);
      expect(unresolved.plannedInstrument, isNull);
      final mapped = planner.mapInstrument(
        draft: unresolved,
        instrument: instrument,
        activeBookId: 'book',
        brokerageAccount: broker,
        existingTransactions: const [],
        existingTransferLinks: const [],
        instruments: [instrument],
      );
      expect(mapped.eventId, unresolved.eventId);
      expect(mapped.instrumentId, instrument.id);
      final created = planner.createInstrument(
        draft: unresolved,
        activeBookId: 'book',
        brokerageAccount: broker,
        existingTransactions: const [],
        existingTransferLinks: const [],
        instruments: [instrument],
      );
      expect(created.eventId, unresolved.eventId);
      expect(
        created.instrumentResolution,
        BrokerageInstrumentResolution.create,
      );
      expect(created.plannedInstrument!.normalizedSymbol, 'MSFT');
    },
  );

  test(
    'exact re-import creates no effects and stable identity ignores review resolution',
    () async {
      final source = _source([
        _row(2, '2026-01-01', 'DIVIDEND', symbol: 'AAPL', gross: '20'),
      ]);
      final first = await _plan(planner, source, broker, cash, [instrument]);
      final posting = BrokerageImportPosting.materialize(
        draft: first.drafts.single,
        bookId: 'book',
        memberId: null,
        brokerageAccount: broker,
        counterpartyAccount: cash,
        instrument: instrument,
      );
      final repeated = await planner.build(
        source: source,
        mapping: canonicalBrokerageMappingFor(source.headers)!,
        brokerageAccount: broker,
        activeBookId: 'book',
        instruments: [instrument],
        existingTransactions: posting.transactions,
        existingTransferLinks: const [],
        counterpartyAccount: cash,
      );
      expect(repeated.drafts.single.eventId, first.drafts.single.eventId);
      expect(
        repeated.drafts.single.classification,
        BrokerageImportClassification.alreadyImported,
      );
      expect(repeated.readyCount, 0);
      expect(repeated.canCommit, isFalse);
    },
  );

  test('funding uses deterministic canonical legs and transfer link', () async {
    final source = _source([_row(2, '2026-01-01', 'DEPOSIT', gross: '500')]);
    final draft = (await _plan(planner, source, broker, cash, [
      instrument,
    ])).drafts.single;
    final first = BrokerageImportPosting.materialize(
      draft: draft,
      bookId: 'book',
      memberId: null,
      brokerageAccount: broker,
      counterpartyAccount: cash,
      instrument: null,
    );
    final second = BrokerageImportPosting.materialize(
      draft: draft,
      bookId: 'book',
      memberId: null,
      brokerageAccount: broker,
      counterpartyAccount: cash,
      instrument: null,
    );
    expect(
      first.transactions.map((item) => item.id),
      second.transactions.map((item) => item.id),
    );
    expect(first.transactions.map((item) => item.type).toSet(), {
      TransactionType.expense,
      TransactionType.income,
    });
    expect(first.transferLink, isNotNull);
    expect(first.transferLink!.id, second.transferLink!.id);
    expect(first.transferLink!.sourceAccountId, cash.id);
    expect(first.transferLink!.destinationAccountId, broker.id);
  });

  test(
    'broker P&L mismatch warns while Pilgrim remains authoritative',
    () async {
      final source = _source([
        _row(
          2,
          '2026-01-01',
          'BUY',
          symbol: 'AAPL',
          quantity: '10',
          price: '100',
          gross: '1000',
        ),
        _row(
          3,
          '2026-01-02',
          'SELL',
          symbol: 'AAPL',
          quantity: '2',
          price: '150',
          gross: '300',
          pnl: '999',
        ),
      ]);
      final preview = await _plan(planner, source, broker, cash, [instrument]);
      final sell = preview.drafts.last;
      expect(sell.hasBlockingIssue, isFalse);
      expect(
        sell.issues.map((issue) => issue.message),
        contains(contains('differs from Pilgrim weighted-average P&L')),
      );
    },
  );

  test('currency mismatch and missing funding account block commit', () async {
    final mismatch = _source([
      _row(
        2,
        '2026-01-01',
        'DIVIDEND',
        symbol: 'AAPL',
        gross: '20',
        currency: 'IDR',
      ),
    ]);
    expect(
      (await _plan(planner, mismatch, broker, cash, [
        instrument,
      ])).drafts.single.hasBlockingIssue,
      isTrue,
    );
    final funding = _source([_row(2, '2026-01-01', 'DEPOSIT', gross: '500')]);
    final preview = await planner.build(
      source: funding,
      mapping: canonicalBrokerageMappingFor(funding.headers)!,
      brokerageAccount: broker,
      activeBookId: 'book',
      instruments: [instrument],
      existingTransactions: const [],
      existingTransferLinks: const [],
    );
    expect(preview.drafts.single.hasBlockingIssue, isTrue);
  });

  testWidgets('review UI exposes unresolved choices and blocks commit', (
    tester,
  ) async {
    final source = _source([
      _row(2, '2026-01-01', 'REINVEST', symbol: 'MSFT', gross: '20'),
    ]);
    final controller =
        BrokerageImportController(
            pickFile: () async => null,
            commitService: BrokerageImportCommitService(
              repository: _RecordingRepository(),
            ),
            accounts: () => [broker, cash],
            instruments: () => [instrument],
            transactions: () => const [],
            transferLinks: () => const [],
            onImported: () async {},
          )
          ..source = source
          ..mapping = canonicalBrokerageMappingFor(source.headers)
          ..brokerageAccountId = broker.id
          ..counterpartyAccountId = cash.id;
    addTearDown(controller.dispose);
    await controller.analyze(bookId: 'book');
    await tester.pumpWidget(
      MaterialApp(
        home: BrokerageImportScreen(
          bookId: 'book',
          memberId: null,
          accounts: [broker, cash],
          instruments: [instrument],
          controller: controller,
          remoteFreshnessVerified: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final activity = find.byKey(const Key('brokerage-row-2-activity'));
    await tester.scrollUntilVisible(activity, 300);
    expect(activity, findsOneWidget);
    expect(find.text('Unknown instrument: MSFT'), findsOneWidget);
    expect(find.text('Map to existing'), findsOneWidget);
    expect(find.text('Create MSFT'), findsOneWidget);
    final commitFinder = find.byKey(const Key('commit-brokerage-import'));
    await tester.scrollUntilVisible(commitFinder, 300);
    final commit = tester.widget<FilledButton>(commitFinder);
    expect(commit.onPressed, isNull);
  });

  test(
    'commit is one atomic repository call and rejects stale duplicate state',
    () async {
      final source = _source([
        _row(2, '2026-01-01', 'DIVIDEND', symbol: 'AAPL', gross: '20'),
      ]);
      final preview = await _plan(planner, source, broker, cash, [instrument]);
      final repository = _RecordingRepository();
      final service = BrokerageImportCommitService(repository: repository);
      final result = await service.commit(
        preview: preview,
        bookId: 'book',
        memberId: 'member',
        brokerageAccount: broker,
        counterpartyAccount: cash,
        existingInstruments: [instrument],
        existingTransactions: const [],
      );
      expect(repository.calls, 1);
      expect(result.transactionsCreated, 1);
      await expectLater(
        service.commit(
          preview: preview,
          bookId: 'book',
          memberId: 'member',
          brokerageAccount: broker.copyWith(id: 'different-broker'),
          counterpartyAccount: cash,
          existingInstruments: [instrument],
          existingTransactions: const [],
        ),
        throwsA(isA<StateError>()),
      );
      final stale = repository.transactions.single.copyWith(id: 'other');
      await expectLater(
        service.commit(
          preview: preview,
          bookId: 'book',
          memberId: 'member',
          brokerageAccount: broker,
          counterpartyAccount: cash,
          existingInstruments: [instrument],
          existingTransactions: [stale],
        ),
        throwsA(isA<StateError>()),
      );
      expect(repository.calls, 1);
    },
  );

  for (final platform in ['native', 'web']) {
    test(
      '$platform atomic persistence rolls back rows and outbox together',
      () async {
        final bookId = 'book-n1-$platform';
        final directory = await Directory.systemTemp.createTemp('beta08n1-');
        final dynamic store = platform == 'native'
            ? native.LocalStore(databasePath: '${directory.path}/test.db')
            : web.LocalStore();
        await store.initialize();
        addTearDown(() async {
          await store.close();
          await directory.delete(recursive: true);
        });
        final snapshot = beta06Snapshot(bookId: bookId)
          ..['transactions'] = []
          ..['accounts'] = []
          ..['asset_definitions'] = [];
        await store.activateHouseholdBackupSnapshot(
          HouseholdBackupIntegrity.prepareForRestore(snapshot),
          replaceBookId: bookId,
        );
        store.setActiveBookId(bookId);
        final definition = _instrument().copyWith(
          id: 'new-$platform',
          bookId: bookId,
        );
        final transaction = Transaction(
          id: 'duplicate-$platform',
          bookId: bookId,
          title: 'Investment income',
          category: 'Investment',
          account: 'Broker',
          date: DateTime(2026, 1, 1),
          amount: 100,
          type: TransactionType.investment,
        ).toRecord();
        await expectLater(
          store.insertInvestmentImportAtomic(
            transactions: [transaction, transaction],
            assetDefinitions: [definition.toRecord()],
            transferLinks: <Map<String, Object?>>[],
          ),
          throwsA(anything),
        );
        expect(await store.getTransactions(bookId: bookId), isEmpty);
        expect(
          await store.getAssetDefinitions(bookId: bookId),
          isNot(
            contains(
              predicate<Map<String, Object?>>(
                (row) => row['id'] == definition.id,
              ),
            ),
          ),
        );
        expect(await store.getPendingSyncCount(bookId), 0);
      },
    );
  }

  test(
    'offline native commit queues canonical funding once and reimport is inert',
    () async {
      const bookId = 'book-n1-offline';
      final directory = await Directory.systemTemp.createTemp('beta08n1-');
      final store = native.LocalStore(
        databasePath: '${directory.path}/test.db',
      );
      await store.initialize();
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final snapshot = beta06Snapshot(bookId: bookId)
        ..['transactions'] = []
        ..['accounts'] = []
        ..['asset_definitions'] = [];
      await store.activateHouseholdBackupSnapshot(
        HouseholdBackupIntegrity.prepareForRestore(snapshot),
        replaceBookId: bookId,
      );
      store.setActiveBookId(bookId);
      await store.db.update(
        'books',
        {'remote_linked_at': DateTime(2026, 1, 1).millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [bookId],
      );
      await store.setSyncInitializationState(bookId, 'ready');
      final localBroker = broker.copyWith(bookId: bookId);
      final localCash = cash.copyWith(bookId: bookId);
      await store.upsertAccount(localBroker.toRecord(), enqueueSync: false);
      await store.upsertAccount(localCash.toRecord(), enqueueSync: false);
      final source = _source([_row(2, '2026-01-01', 'DEPOSIT', gross: '500')]);
      final preview = await planner.build(
        source: source,
        mapping: canonicalBrokerageMappingFor(source.headers)!,
        brokerageAccount: localBroker,
        activeBookId: bookId,
        instruments: const [],
        existingTransactions: const [],
        existingTransferLinks: const [],
        counterpartyAccount: localCash,
      );
      final service = BrokerageImportCommitService(
        repository: LocalTransactionRepository(store as dynamic),
      );
      final result = await service.commit(
        preview: preview,
        bookId: bookId,
        memberId: null,
        brokerageAccount: localBroker,
        counterpartyAccount: localCash,
        existingInstruments: const [],
        existingTransactions: const [],
      );
      expect(result.transactionsCreated, 2);
      expect(await store.getPendingSyncCount(bookId), 3);
      final storedTransactions = (await store.getTransactions(
        bookId: bookId,
      )).map(Transaction.fromRecord).toList();
      final storedLinks = (await store.getTransferLinks(
        bookId: bookId,
      )).map(InternalTransferLink.fromRecord).toList();
      final repeated = await planner.build(
        source: source,
        mapping: canonicalBrokerageMappingFor(source.headers)!,
        brokerageAccount: localBroker,
        activeBookId: bookId,
        instruments: const [],
        existingTransactions: storedTransactions,
        existingTransferLinks: storedLinks,
        counterpartyAccount: localCash,
      );
      expect(
        repeated.drafts.single.classification,
        BrokerageImportClassification.alreadyImported,
      );
      expect(repeated.canCommit, isFalse);
      expect(await store.getPendingSyncCount(bookId), 3);
    },
  );

  test(
    '5000-row statement planning remains bounded',
    () async {
      final rows = List.generate(
        5000,
        (index) =>
            _row(index + 2, '2026-01-01', 'DIVIDEND', gross: '${index + 1}'),
      );
      final stopwatch = Stopwatch()..start();
      final preview = await _plan(planner, _source(rows), broker, cash, [
        instrument,
      ]);
      stopwatch.stop();
      expect(preview.drafts, hasLength(5000));
      expect(preview.readyCount, 5000);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<BrokerageImportPreview> _plan(
  BrokerageImportPlanner planner,
  CsvParsedSource source,
  Account broker,
  Account cash,
  List<AssetDefinition> instruments,
) => planner.build(
  source: source,
  mapping: canonicalBrokerageMappingFor(source.headers)!,
  brokerageAccount: broker,
  activeBookId: 'book',
  instruments: instruments,
  existingTransactions: const [],
  existingTransferLinks: const [],
  counterpartyAccount: cash,
);

const _headers = [
  'date',
  'activity',
  'symbol',
  'quantity',
  'execution_price',
  'gross_amount',
  'fee',
  'tax',
  'currency',
  'reference',
  'note',
  'realized_pnl',
  'split_numerator',
  'split_denominator',
];

CsvParsedSource _source(List<CsvSourceRow> rows) => CsvParsedSource(
  fileName: 'statement.csv',
  fileFingerprint: 'statement-fingerprint',
  delimiter: ',',
  headers: _headers,
  rows: rows,
  headerMode: CsvHeaderMode.firstRowHeaders,
);

CsvSourceRow _row(
  int row,
  String date,
  String activity, {
  String symbol = '',
  String quantity = '',
  String price = '',
  String gross = '',
  String fee = '',
  String tax = '',
  String currency = 'USD',
  String reference = '',
  String note = '',
  String pnl = '',
  String numerator = '',
  String denominator = '',
}) => CsvSourceRow(
  rowNumber: row,
  identityKey: 'row-$row',
  values: [
    date,
    activity,
    symbol,
    quantity,
    price,
    gross,
    fee,
    tax,
    currency,
    reference,
    note,
    pnl,
    numerator,
    denominator,
  ],
);

AssetDefinition _instrument() => AssetDefinition(
  id: 'aapl',
  bookId: 'book',
  displayName: 'Apple',
  kind: AssetKind.stock,
  symbol: 'AAPL',
  providerCode: null,
  providerSymbol: null,
  exchangeCode: 'NASDAQ',
  currencyCode: 'USD',
  unit: 'share',
  lotSize: 1,
  onlinePricingEnabled: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'device',
  syncStatus: 'synced',
);

class _RecordingRepository implements InvestmentImportAtomicRepository {
  int calls = 0;
  List<Transaction> transactions = const [];
  List<AssetDefinition> definitions = const [];
  List<InternalTransferLink> links = const [];

  @override
  Future<void> saveInvestmentImportAtomic({
    required List<Transaction> transactions,
    required List<AssetDefinition> assetDefinitionCreations,
    required List<InternalTransferLink> transferLinks,
  }) async {
    calls += 1;
    this.transactions = List.unmodifiable(transactions);
    definitions = List.unmodifiable(assetDefinitionCreations);
    links = List.unmodifiable(transferLinks);
  }
}
