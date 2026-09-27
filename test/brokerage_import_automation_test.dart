import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pilgrim_tracker/features/investments/presentation/controllers/brokerage_import_controller.dart';
import 'package:pilgrim_tracker/features/investments/presentation/screens/brokerage_import_screen.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_date_detection.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_models.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_planner.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_posting.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_idr_rounding.dart';
import 'package:pilgrim_tracker/features/investments/domain/entities/brokerage_settlement.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_brokerage_metadata.dart';
import 'package:pilgrim_tracker/features/investments/domain/import/brokerage_import_commit_service.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/csv_value_parsers.dart';

final broker = Account(
  id: 'broker',
  bookId: 'book',
  name: 'Broker',
  accountType: AccountType.brokerage,
  currencyCode: 'IDR',
);
final cash = Account(
  id: 'cash',
  bookId: 'book',
  name: 'Cash',
  accountType: AccountType.bank,
  currencyCode: 'IDR',
);
const planner = BrokerageImportPlanner();
const rejectingGenericMoneyPlanner = BrokerageImportPlanner(
  moneyParser: _RejectingGenericMoneyParser(),
);
const mapping = BrokerageStatementMapping(
  dateColumn: 0,
  activityColumn: 1,
  instrumentColumn: 2,
  grossAmountColumn: 3,
  decimalSeparator: CsvSeparator.period,
  trustedIdx: true,
);
CsvParsedSource source(List<List<String>> rows) => CsvParsedSource(
  fileName: 'synthetic.csv',
  fileFingerprint: 'synthetic-source',
  delimiter: ',',
  headers: const ['date', 'activity', 'symbol', 'amount'],
  rows: [
    for (var i = 0; i < rows.length; i++)
      CsvSourceRow(rowNumber: i + 2, identityKey: 'row-$i', values: rows[i]),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

const ownerRdnMapping = BrokerageStatementMapping(
  dateColumn: 0,
  activityColumn: 1,
  instrumentColumn: 2,
  grossAmountColumn: 3,
  quantityColumn: 4,
  executionPriceColumn: 5,
  feeColumn: 6,
  taxColumn: 7,
  currencyColumn: 8,
  referenceColumn: 9,
  noteColumn: 10,
  realizedPnlColumn: 11,
  splitNumeratorColumn: 12,
  splitDenominatorColumn: 13,
  decimalSeparator: CsvSeparator.period,
  thousandsSeparator: CsvSeparator.none,
  trustedIdx: true,
);

const reviewRdnMapping = BrokerageStatementMapping(
  dateColumn: 0,
  activityColumn: 1,
  instrumentColumn: 2,
  grossAmountColumn: 3,
  quantityColumn: 4,
  executionPriceColumn: 5,
  feeColumn: 6,
  taxColumn: 7,
  currencyColumn: 8,
  referenceColumn: 9,
  noteColumn: 10,
  realizedPnlColumn: 11,
  splitNumeratorColumn: 12,
  splitDenominatorColumn: 13,
  decimalSeparator: CsvSeparator.period,
  thousandsSeparator: CsvSeparator.none,
);

List<String> rdnRow(
  String date,
  String activity, {
  String symbol = '',
  String gross = '',
  String quantity = '',
  String price = '',
  String currency = 'IDR',
  String splitNumerator = '',
  String splitDenominator = '',
}) => [
  date,
  activity,
  symbol,
  gross,
  quantity,
  price,
  '',
  '',
  currency,
  '$activity-$date',
  '',
  '',
  splitNumerator,
  splitDenominator,
];

CsvParsedSource ownerRdnSource(List<List<String>> rows) => CsvParsedSource(
  fileName: 'synthetic-stockbit-rdn.csv',
  fileFingerprint: 'synthetic-stockbit-rdn-source',
  delimiter: ',',
  headers: const [
    'Date',
    'Activity',
    'Symbol / instrument',
    'Gross amount',
    'Quantity',
    'Execution price',
    'Fee',
    'Tax',
    'Currency',
    'Reference',
    'Note',
    'Broker realized P&L',
    'Split numerator',
    'Split denominator',
  ],
  rows: [
    for (var i = 0; i < rows.length; i++)
      CsvSourceRow(
        rowNumber: i + 2,
        identityKey: 'rdn-row-$i',
        values: rows[i],
      ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);
Future<BrokerageImportPreview> analyze(
  List<List<String>> rows, {
  Iterable<AssetDefinition> instruments = const [],
  Iterable<Transaction> transactions = const [],
  BrokerageStatementMapping selectedMapping = mapping,
}) => planner.build(
  source: source(rows),
  mapping: selectedMapping,
  brokerageAccount: broker,
  activeBookId: 'book',
  instruments: instruments,
  existingTransactions: transactions,
  existingTransferLinks: const [],
  counterpartyAccount: cash,
);

void main() {
  test('fractional IDR uses exact symmetric HALF_UP rounding', () {
    BrokerageIdrParseResult parse(String value) =>
        BrokerageIdrRoundingParser.parse(
          value,
          field: 'gross_amount',
          decimalSeparator: CsvSeparator.period,
          thousandsSeparator: CsvSeparator.none,
          stripCurrencySymbols: false,
        );

    expect(parse('42563.49').value, 42563);
    expect(parse('42563.50').value, 42564);
    expect(parse('-42563.49').value, -42563);
    expect(parse('-42563.50').value, -42564);
    expect(parse('639000.00').rounding, isNull);
    expect(
      () => const CsvMoneyParser().parse(
        '10.50',
        currencyCode: 'IDR',
        decimalSeparator: CsvSeparator.period,
        thousandsSeparator: CsvSeparator.none,
        stripCurrencySymbols: false,
      ),
      throwsA(isA<TransactionImportException>()),
    );
  });

  test(
    'real RDN row shape reaches HALF_UP review before generic IDR rejection',
    () async {
      final preview = await rejectingGenericMoneyPlanner.build(
        source: ownerRdnSource([
          [
            '10/20/2023',
            'BUY_SETTLEMENT',
            '',
            '42563.75',
            '',
            '',
            '',
            '',
            'IDR',
            'BCA-RDN-20231020-01',
            'Synthetic settlement evidence',
            '',
            '',
            '',
          ],
        ]),
        mapping: ownerRdnMapping,
        brokerageAccount: broker,
        activeBookId: 'book',
        instruments: const [],
        existingTransactions: const [],
        existingTransferLinks: const [],
        counterpartyAccount: cash,
      );

      final draft = preview.drafts.single;
      expect(draft.isSettlement, isTrue);
      expect(draft.settlementType, BrokerageSettlementType.buySettlement);
      expect(draft.activityType, isNull);
      expect(draft.grossAmount, 42564);
      expect(draft.idrRoundings.single.sourceValue, '42563.75');
      expect(draft.idrRoundings.single.roundedValue, 42564);
      expect(draft.hasBlockingIssue, isFalse);
      expect(
        draft.issues.map((issue) => issue.message),
        isNot(contains('CSV: The monetary value has too many decimal places.')),
      );
      expect(
        draft.issues.map((issue) => issue.message),
        isNot(contains('A positive gross amount is required.')),
      );
      expect(preview.requiresFractionalIdrApproval, isTrue);
      expect(preview.fractionalIdrRoundingApproved, isFalse);
      expect(preview.canCommit, isFalse);

      final approved = BrokerageImportPreview(
        source: preview.source,
        drafts: preview.drafts,
        remoteFreshnessVerified: true,
        detectedDateFormat: preview.detectedDateFormat,
        fractionalIdrRoundingApproved: true,
      );
      final repo = RecordingRepository();
      await BrokerageImportCommitService(repository: repo).commit(
        preview: approved,
        bookId: 'book',
        memberId: null,
        brokerageAccount: broker,
        counterpartyAccount: cash,
        existingInstruments: const [],
        existingTransactions: const [],
      );
      expect(repo.settlements.single['amount'], 42564);
      expect(repo.settlements.single['note'], contains('42563.75'));
      expect(repo.transactions, isEmpty);
    },
  );

  test(
    'fractional IDR rows require one approval and preserve provenance',
    () async {
      final preview = await analyze([
        ['2026-01-01', 'BUY_SETTLEMENT', '', '42563.75'],
        ['2026-01-02', 'INTEREST', '', '10.49'],
        ['2026-01-03', 'TAX', '', '10.50'],
      ]);
      expect(preview.fractionalIdrRowCount, 3);
      expect(preview.fractionalIdrValueCount, 3);
      expect(preview.drafts.map((draft) => draft.grossAmount), [42564, 10, 11]);
      expect(preview.drafts.every((draft) => !draft.hasBlockingIssue), isTrue);
      expect(preview.canCommit, isFalse);

      final repo = RecordingRepository();
      final service = BrokerageImportCommitService(repository: repo);
      await expectLater(
        service.commit(
          preview: preview,
          bookId: 'book',
          memberId: null,
          brokerageAccount: broker,
          counterpartyAccount: cash,
          existingInstruments: const [],
          existingTransactions: const [],
        ),
        throwsStateError,
      );
      expect(repo.calls, 0);

      final approved = BrokerageImportPreview(
        source: preview.source,
        drafts: preview.drafts,
        remoteFreshnessVerified: true,
        detectedDateFormat: preview.detectedDateFormat,
        fractionalIdrRoundingApproved: true,
      );
      await service.commit(
        preview: approved,
        bookId: 'book',
        memberId: null,
        brokerageAccount: broker,
        counterpartyAccount: cash,
        existingInstruments: const [],
        existingTransactions: const [],
      );
      expect(repo.settlements.single['amount'], 42564);
      expect(repo.settlements.single['note'], contains('"source":"42563.75"'));
      expect(repo.transactions.map((transaction) => transaction.amount), [
        10,
        11,
      ]);
      expect(repo.transactions.first.note, contains('"rounding":"HALF_UP"'));
    },
  );

  test(
    'fractional re-import keeps rounded value and stable identity',
    () async {
      final first = await analyze([
        ['2026-01-02', 'INTEREST', '', '10.50'],
      ]);
      final approved = BrokerageImportPreview(
        source: first.source,
        drafts: first.drafts,
        remoteFreshnessVerified: true,
        detectedDateFormat: first.detectedDateFormat,
        fractionalIdrRoundingApproved: true,
      );
      final repo = RecordingRepository();
      await BrokerageImportCommitService(repository: repo).commit(
        preview: approved,
        bookId: 'book',
        memberId: null,
        brokerageAccount: broker,
        counterpartyAccount: cash,
        existingInstruments: const [],
        existingTransactions: const [],
      );
      final repeated = await analyze([
        ['2026-01-02', 'INTEREST', '', '10.50'],
      ], transactions: repo.transactions);
      expect(repeated.drafts.single.grossAmount, 11);
      expect(repeated.drafts.single.eventId, first.drafts.single.eventId);
      expect(repeated.count(BrokerageImportClassification.alreadyImported), 1);
      expect(repeated.requiresFractionalIdrApproval, isFalse);
    },
  );

  testWidgets('review requires explicit session rounding approval', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = RecordingRepository();
    final controller =
        BrokerageImportController(
            pickFile: () async => null,
            commitService: BrokerageImportCommitService(repository: repository),
            accounts: () => [broker, cash],
            instruments: () => const [],
            transactions: () => const [],
            transferLinks: () => const [],
            onImported: () async {},
          )
          ..source = source([
            ['2026-01-01', 'INTEREST', '', '10.50'],
          ])
          ..mapping = mapping
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
          instruments: const [],
          controller: controller,
          remoteFreshnessVerified: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Approve HALF_UP rounding for 1 fractional IDR rows'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('commit-brokerage-import')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('approve-brokerage-idr-rounding')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('commit-brokerage-import')),
          )
          .onPressed,
      isNotNull,
    );
  });

  test('canonical mapping opts into period decimal parsing', () {
    final selected = canonicalBrokerageMappingFor(const [
      'Date',
      'Activity',
      'Symbol / instrument',
      'Gross amount',
    ]);
    expect(selected, isNotNull);
    expect(selected!.decimalSeparator, CsvSeparator.period);
    expect(selected.thousandsSeparator, CsvSeparator.none);
  });

  testWidgets(
    'trusted review shows staged summary without per-row create or writes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = RecordingRepository();
      final controller =
          BrokerageImportController(
              pickFile: () async => null,
              commitService: BrokerageImportCommitService(
                repository: repository,
              ),
              accounts: () => [broker, cash],
              instruments: () => const [],
              transactions: () => const [],
              transferLinks: () => const [],
              onImported: () async {},
            )
            ..source = source([
              ['23/02/2026', 'DIVIDEND', 'DMAS', '100'],
              ['24/02/2026', 'DIVIDEND', 'DMAS', '200'],
            ])
            ..mapping = mapping
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
            instruments: const [],
            controller: controller,
            remoteFreshnessVerified: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 instruments will be created'), findsOneWidget);
      expect(find.text('Ready · New instrument'), findsNWidgets(2));
      expect(find.text('Create DMAS'), findsNothing);
      expect(repository.calls, 0);
      await tester.tap(find.byKey(const Key('commit-brokerage-import')));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(repository.definitions, hasLength(1));
    },
  );
  test('DD/MM detected using all rows, including a later decisive day', () {
    expect(
      BrokerageDateDetection.detect(['01/02/2026', '', '23/02/2026']),
      CsvDateFormat.ddMmYyyySlash,
    );
  });
  test('ISO is preferred and month-first is detected', () {
    expect(
      BrokerageDateDetection.detect(['2026-01-02', '2026-02-03']),
      CsvDateFormat.yyyyMmDd,
    );
    expect(
      BrokerageDateDetection.detect(['01/23/2026', '02/03/2026']),
      CsvDateFormat.mmDdYyyySlash,
    );
  });
  test('ambiguous column requests explicit format', () async {
    final preview = await analyze([
      ['01/02/2026', 'FEE', '', '100'],
    ]);
    expect(preview.detectedDateFormat, isNull);
    expect(preview.drafts.single.date, isNull);
    expect(preview.canCommit, isFalse);
    final explicit = await analyze(
      [
        ['01/02/2026', 'FEE', '', '100'],
      ],
      selectedMapping: const BrokerageStatementMapping(
        dateColumn: 0,
        activityColumn: 1,
        instrumentColumn: 2,
        grossAmountColumn: 3,
        dateFormat: CsvDateFormat.ddMmYyyySlash,
      ),
    );
    expect(explicit.drafts.single.date, DateTime(2026, 2, 1));
    expect(explicit.canCommit, isTrue);
  });
  test(
    'invalid date is retained unresolved and commit cannot write epoch',
    () async {
      final preview = await analyze([
        ['2026-02-30', 'FEE', '', '100'],
      ]);
      expect(preview.drafts.single.date, isNull);
      expect(preview.drafts.single.rawDate, '2026-02-30');
      expect(preview.detectedDateFormat, CsvDateFormat.yyyyMmDd);
      final repo = RecordingRepository();
      await expectLater(
        BrokerageImportCommitService(repository: repo).commit(
          preview: preview,
          bookId: 'book',
          memberId: null,
          brokerageAccount: broker,
          counterpartyAccount: cash,
          existingInstruments: const [],
          existingTransactions: const [],
        ),
        throwsStateError,
      );
      expect(repo.calls, 0);
    },
  );
  test(
    'trusted unknown dividends share one staged IDX instrument and commit once',
    () async {
      final rows = [
        ['23/02/2026', 'DIVIDEND', 'dmas', '100'],
        ['24/02/2026', 'DIVIDEND', ' DMAS ', '200'],
      ];
      final preview = await analyze(rows);
      expect(preview.readyCount, 2);
      expect(preview.instrumentsToCreate, 1);
      final definition = preview.drafts.first.plannedInstrument!;
      expect(
        identical(definition, preview.drafts.last.plannedInstrument),
        isTrue,
      );
      expect(definition.symbol, 'DMAS');
      expect(definition.displayName, 'DMAS');
      expect(definition.exchangeCode, 'IDX');
      expect(definition.lotSize, 100);
      expect(definition.currencyCode, 'IDR');
      final repo = RecordingRepository();
      final result = await BrokerageImportCommitService(repository: repo)
          .commit(
            preview: preview,
            bookId: 'book',
            memberId: null,
            brokerageAccount: broker,
            counterpartyAccount: cash,
            existingInstruments: const [],
            existingTransactions: const [],
          );
      expect(result.instrumentsCreated, 1);
      expect(repo.calls, 1);
      expect(repo.transactions.map((t) => t.assetDefinitionId).toSet(), {
        definition.id,
      });
      final repeated = await analyze(
        rows,
        instruments: repo.definitions,
        transactions: repo.transactions,
      );
      expect(repeated.readyCount, 0);
      expect(repeated.instrumentsToCreate, 0);
      expect(repeated.count(BrokerageImportClassification.alreadyImported), 2);
    },
  );
  test(
    'existing exact symbol auto-matches and preserves canonical casing',
    () async {
      final first = await analyze([
        ['2026-02-01', 'DIVIDEND', 'DMAS', '100'],
      ]);
      final definition = first.drafts.single.plannedInstrument!;
      final preview = await analyze(
        [
          ['2026-02-01', 'DIVIDEND', ' dmas ', '100'],
        ],
        instruments: [definition],
      );
      expect(preview.readyCount, 1);
      expect(preview.instrumentsToCreate, 0);
      expect(preview.drafts.single.instrumentId, definition.id);
      expect(preview.drafts.single.plannedInstrument!.symbol, 'DMAS');
    },
  );
  test('untrusted ticker and blank dividend require review', () async {
    final untrusted = await analyze(
      [
        ['2026-01-01', 'DIVIDEND', 'DMAS', '100'],
      ],
      selectedMapping: const BrokerageStatementMapping(
        dateColumn: 0,
        activityColumn: 1,
        instrumentColumn: 2,
        grossAmountColumn: 3,
      ),
    );
    expect(untrusted.canCommit, isFalse);
    expect(untrusted.instrumentsToCreate, 0);
    final blank = await analyze([
      ['2026-01-01', 'DIVIDEND', '', '100'],
    ]);
    expect(blank.canCommit, isFalse);
    expect(blank.drafts.single.needsInstrumentResolution, isTrue);
  });
  test(
    'deposit fee and tax need no instrument even with source memo symbol',
    () async {
      final preview = await analyze([
        ['2026-01-01', 'DEPOSIT', '', '100'],
        ['2026-01-02', 'FEE', 'Cash', '10'],
        ['2026-01-03', 'TAX', '', '10'],
      ]);
      expect(preview.readyCount, 3);
      expect(preview.instrumentsToCreate, 0);
    },
  );
  test('settlement cannot become a trade or modify holdings', () async {
    final preview = await analyze([
      ['2026-01-01', 'BUY_SETTLEMENT', '', '100'],
      ['2026-01-02', 'SELL_SETTLEMENT', '', '100'],
    ]);
    expect(preview.instrumentsToCreate, 0);
    expect(preview.drafts.every((d) => !d.requiresInstrument), isTrue);
    expect(preview.canCommit, isTrue);
    final repo = RecordingRepository();
    expect(
      () => BrokerageImportPosting.materialize(
        draft: preview.drafts.first.copyWith(
          activityType: BrokerageActivityType.buy,
        ),
        bookId: 'book',
        memberId: null,
        brokerageAccount: broker,
        counterpartyAccount: cash,
        instrument: null,
      ),
      throwsStateError,
    );
    await BrokerageImportCommitService(repository: repo).commit(
      preview: preview,
      bookId: 'book',
      memberId: null,
      brokerageAccount: broker,
      counterpartyAccount: cash,
      existingInstruments: const [],
      existingTransactions: const [],
    );
    expect(repo.calls, 1);
    expect(repo.transactions, isEmpty);
    expect(
      AssetPortfolioCalculator.calculate(
        transactions: repo.transactions,
      ).totalRealizedGain,
      0,
    );
  });

  test(
    'one create decision replans all nine activities as one chronological session',
    () async {
      final repository = RecordingRepository();
      final controller =
          BrokerageImportController(
              pickFile: () async => null,
              commitService: BrokerageImportCommitService(
                repository: repository,
              ),
              accounts: () => [broker, cash],
              instruments: () => repository.definitions,
              transactions: () => repository.transactions,
              transferLinks: () => const [],
              onImported: () async {},
            )
            ..source = ownerRdnSource([
              rdnRow('2026-09-01', 'DEPOSIT', gross: '200000'),
              rdnRow(
                '2026-09-02',
                'BUY',
                symbol: 'PTST',
                gross: '100000',
                quantity: '100',
                price: '1000',
              ),
              rdnRow('2026-09-03', 'DIVIDEND', symbol: 'PTST', gross: '1000'),
              rdnRow('2026-09-04', 'INTEREST', gross: '500'),
              rdnRow('2026-09-05', 'FEE', gross: '100'),
              rdnRow('2026-09-06', 'TAX', gross: '50'),
              rdnRow(
                '2026-09-07',
                'SELL',
                symbol: 'PTST',
                gross: '48000',
                quantity: '40',
                price: '1200',
              ),
              rdnRow(
                '2026-09-08',
                'SPLIT',
                symbol: 'PTST',
                splitNumerator: '2',
                splitDenominator: '1',
              ),
              rdnRow('2026-09-09', 'WITHDRAWAL', gross: '500'),
            ])
            ..mapping = reviewRdnMapping
            ..brokerageAccountId = broker.id
            ..counterpartyAccountId = cash.id;
      addTearDown(controller.dispose);

      await controller.analyze(bookId: 'book');
      expect(controller.preview!.unresolvedCount, 4);

      controller.createInstrument(3, bookId: 'book');
      final preview = controller.preview!;
      final instrumentDrafts = preview.drafts
          .where((draft) => draft.requiresInstrument)
          .toList();
      expect(instrumentDrafts, hasLength(4));
      expect(
        instrumentDrafts.map((draft) => draft.instrumentId).toSet(),
        hasLength(1),
      );
      expect(
        instrumentDrafts.map((draft) => draft.instrumentResolution).toSet(),
        {BrokerageInstrumentResolution.create},
      );
      expect(
        instrumentDrafts.every((draft) => !draft.hasBlockingIssue),
        isTrue,
      );
      expect(preview.unresolvedCount, 0);
      expect(preview.instrumentsToCreate, 1);
      expect(preview.readyCount, 9);

      await controller.commit(bookId: 'book', memberId: null);
      expect(controller.error, isNull);
      expect(repository.calls, 1);
      expect(repository.definitions, hasLength(1));
      final definition = repository.definitions.single;
      expect(definition.symbol, 'PTST');
      expect(
        repository.transactions
            .where((transaction) => transaction.assetDefinitionId != null)
            .map((transaction) => transaction.assetDefinitionId)
            .toSet(),
        {definition.id},
      );
      final holding = AssetPortfolioCalculator.calculate(
        transactions: repository.transactions,
        assetDefinitions: repository.definitions,
        brokerageAccountId: broker.id,
      ).holdings.single;
      expect(holding.quantity, 120);
      expect(holding.costBasis, 60000);

      final repeated = await planner.build(
        source: controller.source!,
        mapping: reviewRdnMapping,
        brokerageAccount: broker,
        activeBookId: 'book',
        instruments: repository.definitions,
        existingTransactions: repository.transactions,
        existingTransferLinks: repository.transferLinks,
        counterpartyAccount: cash,
      );
      expect(repeated.readyCount, 0);
      expect(repeated.instrumentsToCreate, 0);
      expect(
        repeated.drafts
            .where((draft) => !draft.isSettlement)
            .every(
              (draft) =>
                  draft.classification ==
                  BrokerageImportClassification.alreadyImported,
            ),
        isTrue,
      );
    },
  );

  test(
    'excluding or changing the earlier buy immediately invalidates later sell and split',
    () async {
      final controller =
          BrokerageImportController(
              pickFile: () async => null,
              commitService: BrokerageImportCommitService(
                repository: RecordingRepository(),
              ),
              accounts: () => [broker, cash],
              instruments: () => const [],
              transactions: () => const [],
              transferLinks: () => const [],
              onImported: () async {},
            )
            ..source = ownerRdnSource([
              rdnRow(
                '2026-09-01',
                'BUY',
                symbol: 'PTST',
                gross: '100000',
                quantity: '100',
                price: '1000',
              ),
              rdnRow(
                '2026-09-02',
                'SELL',
                symbol: 'PTST',
                gross: '48000',
                quantity: '40',
                price: '1200',
              ),
              rdnRow(
                '2026-09-03',
                'SPLIT',
                symbol: 'PTST',
                splitNumerator: '2',
                splitDenominator: '1',
              ),
            ])
            ..mapping = reviewRdnMapping
            ..brokerageAccountId = broker.id
            ..counterpartyAccountId = cash.id;
      addTearDown(controller.dispose);
      await controller.analyze(bookId: 'book');
      controller.createInstrument(2, bookId: 'book');
      expect(
        controller.preview!.drafts.every((draft) => draft.canCommit),
        isTrue,
      );

      controller.setIncluded(2, false, bookId: 'book');
      expect(controller.preview!.drafts[1].hasBlockingIssue, isTrue);
      expect(controller.preview!.drafts[2].hasBlockingIssue, isTrue);

      controller.setIncluded(2, true, bookId: 'book');
      expect(
        controller.preview!.drafts.every((draft) => draft.canCommit),
        isTrue,
      );
      controller.resolveActivity(2, BrokerageActivityType.fee, bookId: 'book');
      expect(controller.preview!.drafts[1].hasBlockingIssue, isTrue);
      expect(controller.preview!.drafts[2].hasBlockingIssue, isTrue);
    },
  );

  test(
    'chronological replanning ignores source row order and blocks oversells',
    () async {
      Future<BrokerageImportController> buildController(
        List<List<String>> rows,
      ) async {
        final controller =
            BrokerageImportController(
                pickFile: () async => null,
                commitService: BrokerageImportCommitService(
                  repository: RecordingRepository(),
                ),
                accounts: () => [broker, cash],
                instruments: () => const [],
                transactions: () => const [],
                transferLinks: () => const [],
                onImported: () async {},
              )
              ..source = ownerRdnSource(rows)
              ..mapping = reviewRdnMapping
              ..brokerageAccountId = broker.id
              ..counterpartyAccountId = cash.id;
        await controller.analyze(bookId: 'book');
        return controller;
      }

      final outOfOrder = await buildController([
        rdnRow(
          '2026-09-07',
          'SELL',
          symbol: 'PTST',
          gross: '48000',
          quantity: '40',
          price: '1200',
        ),
        rdnRow(
          '2026-09-02',
          'BUY',
          symbol: 'PTST',
          gross: '100000',
          quantity: '100',
          price: '1000',
        ),
      ]);
      addTearDown(outOfOrder.dispose);
      outOfOrder.createInstrument(3, bookId: 'book');
      expect(
        outOfOrder.preview!.drafts.every((draft) => draft.canCommit),
        isTrue,
      );

      final oversell = await buildController([
        rdnRow(
          '2026-09-02',
          'BUY',
          symbol: 'PTST',
          gross: '100000',
          quantity: '100',
          price: '1000',
        ),
        rdnRow(
          '2026-09-07',
          'SELL',
          symbol: 'PTST',
          gross: '168000',
          quantity: '140',
          price: '1200',
        ),
      ]);
      addTearDown(oversell.dispose);
      oversell.createInstrument(2, bookId: 'book');
      expect(oversell.preview!.drafts.first.canCommit, isTrue);
      expect(oversell.preview!.drafts.last.hasBlockingIssue, isTrue);
    },
  );

  test('instrument decisions propagate by symbol and currency only', () async {
    final mappedDefinition = AssetDefinition(
      id: 'mapped',
      bookId: 'book',
      displayName: 'Mapped equity',
      kind: AssetKind.stock,
      symbol: 'OTHER',
      providerCode: null,
      providerSymbol: null,
      exchangeCode: 'IDX',
      currencyCode: 'IDR',
      unit: 'share',
      lotSize: 100,
      onlinePricingEnabled: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deletedAt: null,
      version: 1,
      deviceId: 'test',
      syncStatus: 'synced',
    );
    final controller =
        BrokerageImportController(
            pickFile: () async => null,
            commitService: BrokerageImportCommitService(
              repository: RecordingRepository(),
            ),
            accounts: () => [broker, cash],
            instruments: () => [mappedDefinition],
            transactions: () => const [],
            transferLinks: () => const [],
            onImported: () async {},
          )
          ..source = ownerRdnSource([
            rdnRow(
              '2026-09-01',
              'BUY',
              symbol: 'PTST',
              gross: '100000',
              quantity: '100',
              price: '1000',
            ),
            rdnRow('2026-09-02', 'DIVIDEND', symbol: 'PTST', gross: '1000'),
            rdnRow(
              '2026-09-03',
              'DIVIDEND',
              symbol: 'PTST',
              gross: '10',
              currency: 'USD',
            ),
          ])
          ..mapping = reviewRdnMapping
          ..brokerageAccountId = broker.id
          ..counterpartyAccountId = cash.id;
    addTearDown(controller.dispose);
    await controller.analyze(bookId: 'book');
    controller.mapInstrument(2, mappedDefinition, bookId: 'book');
    expect(controller.preview!.drafts[0].instrumentId, mappedDefinition.id);
    expect(controller.preview!.drafts[1].instrumentId, mappedDefinition.id);
    expect(controller.preview!.drafts[2].instrumentId, isNull);
  });
}

class _RejectingGenericMoneyParser extends CsvMoneyParser {
  const _RejectingGenericMoneyParser();

  @override
  int parse(
    String source, {
    required String currencyCode,
    required CsvSeparator decimalSeparator,
    required CsvSeparator thousandsSeparator,
    required bool stripCurrencySymbols,
    bool allowZero = false,
  }) => throw StateError(
    'The generic money parser must not parse brokerage IDR source values.',
  );
}

class RecordingRepository implements InvestmentImportAtomicRepository {
  int calls = 0;
  List<Transaction> transactions = [];
  List<AssetDefinition> definitions = [];
  List<InternalTransferLink> transferLinks = [];
  List<Map<String, Object?>> settlements = [];
  @override
  Future<void> saveInvestmentImportAtomic({
    required List<Transaction> transactions,
    required List<AssetDefinition> assetDefinitionCreations,
    required List<InternalTransferLink> transferLinks,
    List<Map<String, Object?>> settlements = const [],
  }) async {
    calls++;
    this.transactions = transactions;
    definitions = assetDefinitionCreations;
    this.transferLinks = transferLinks;
    this.settlements = settlements;
  }
}
