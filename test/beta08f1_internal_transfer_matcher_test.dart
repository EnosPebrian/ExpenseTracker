import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/services/account_balance_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/internal_transfer_matcher.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/internal_transfer_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/internal_transfer_review_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/screens/internal_transfer_review_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('pure indexed matcher', () {
    const matcher = InternalTransferMatcher();

    test('same date exact pair is strong with explainable signals', () {
      final result = matcher.matchOne(
        source: _candidate(
          id: 'out',
          accountId: 'cash',
          accountName: 'BCA Enos',
          type: TransactionType.expense,
          description: 'TRANSFER TO BCA GRACE',
          reference: 'REF-42',
        ),
        counterparts: [
          _candidate(
            id: 'in',
            accountId: 'bank',
            accountName: 'BCA Grace',
            type: TransactionType.income,
            description: 'TRANSFER FROM ENOS',
            reference: 'REF-42',
          ),
        ],
      );
      expect(result.classification, InternalTransferMatchClassification.strong);
      expect(result.counterpart?.id, 'in');
      expect(
        result.reasons,
        containsAll([
          'Same amount',
          'Same currency',
          'Same date',
          'Matching reference',
        ]),
      );
      expect(
        result.reasons.any((item) => item.contains('other account')),
        isTrue,
      );
      expect(result.reasons, contains('Transfer wording detected'));
    });

    for (final offset in [-2, -1, 1, 2]) {
      test('$offset calendar-day match is possible', () {
        final result = matcher.matchOne(
          source: _candidate(id: 'out', type: TransactionType.expense),
          counterparts: [
            _candidate(
              id: 'in',
              accountId: 'bank',
              type: TransactionType.income,
              date: DateTime(2026, 8, 19 + offset),
            ),
          ],
        );
        expect(
          result.classification,
          InternalTransferMatchClassification.possible,
        );
        expect(
          result.reasons.any((item) => item.contains(offset.abs().toString())),
          isTrue,
        );
      });
    }

    test('more than two local calendar days is excluded', () {
      final result = matcher.matchOne(
        source: _candidate(id: 'out', type: TransactionType.expense),
        counterparts: [
          _candidate(
            id: 'in',
            accountId: 'bank',
            type: TransactionType.income,
            date: DateTime(2026, 8, 22),
          ),
        ],
      );
      expect(
        result.classification,
        InternalTransferMatchClassification.notEligible,
      );
    });

    test(
      'hard constraints reject amount, currency, account, and direction',
      () {
        final source = _candidate(id: 'out', type: TransactionType.expense);
        final invalid = [
          _candidate(
            id: 'amount',
            accountId: 'bank',
            type: TransactionType.income,
            amount: 99999,
          ),
          _candidate(
            id: 'currency',
            accountId: 'bank',
            type: TransactionType.income,
            currency: 'USD',
          ),
          _candidate(
            id: 'account',
            accountId: 'cash',
            type: TransactionType.income,
          ),
          _candidate(
            id: 'direction',
            accountId: 'bank',
            type: TransactionType.expense,
          ),
          _candidate(
            id: 'household',
            bookId: 'other',
            accountId: 'bank',
            type: TransactionType.income,
          ),
        ];
        for (final counterpart in invalid) {
          expect(
            matcher
                .matchOne(source: source, counterparts: [counterpart])
                .classification,
            InternalTransferMatchClassification.notEligible,
            reason: counterpart.id,
          );
        }
      },
    );

    test('keywords are supplementary rather than required', () {
      final result = matcher.matchOne(
        source: _candidate(
          id: 'out',
          type: TransactionType.expense,
          description: 'generic posting',
        ),
        counterparts: [
          _candidate(
            id: 'in',
            accountId: 'bank',
            type: TransactionType.income,
            description: 'generic credit',
          ),
        ],
      );
      expect(result.classification, InternalTransferMatchClassification.strong);
      expect(result.reasons, isNot(contains('Transfer wording detected')));
    });

    test(
      'equal-quality alternatives remain ambiguous despite stable ordering',
      () {
        final result = matcher.matchOne(
          source: _candidate(id: 'out', type: TransactionType.expense),
          counterparts: [
            _candidate(
              id: 'b',
              accountId: 'bank-b',
              type: TransactionType.income,
            ),
            _candidate(
              id: 'a',
              accountId: 'bank-a',
              type: TransactionType.income,
            ),
          ],
        );
        expect(
          result.classification,
          InternalTransferMatchClassification.ambiguous,
        );
        expect(result.counterpart, isNull);
        expect(result.options.map((item) => item.counterpart.id), ['a', 'b']);
      },
    );

    test(
      'reference and account hint produce a unique deterministic winner',
      () {
        final result = matcher.matchOne(
          source: _candidate(
            id: 'out',
            accountName: 'Cash',
            type: TransactionType.expense,
            description: 'Move to BCA Grace',
            reference: 'R-1',
          ),
          counterparts: [
            _candidate(
              id: 'weak',
              accountId: 'bank-a',
              accountName: 'Other Bank',
              type: TransactionType.income,
            ),
            _candidate(
              id: 'best',
              accountId: 'bank-b',
              accountName: 'BCA Grace',
              type: TransactionType.income,
              reference: 'R-1',
            ),
          ],
        );
        expect(result.counterpart?.id, 'best');
        expect(
          result.classification,
          InternalTransferMatchClassification.strong,
        );
      },
    );

    test('paired, deleted, and legacy/special candidates are excluded', () {
      final paired = matcher.matchOne(
        source: _candidate(
          id: 'paired',
          type: TransactionType.expense,
          paired: true,
        ),
        counterparts: const [],
      );
      expect(
        paired.classification,
        InternalTransferMatchClassification.alreadyTransfer,
      );
      for (final source in [
        _candidate(id: 'deleted', type: TransactionType.expense, deleted: true),
        _candidate(id: 'legacy', type: TransactionType.transfer),
        _candidate(id: 'asset', type: TransactionType.assetConversion),
      ]) {
        expect(
          matcher
              .matchOne(source: source, counterparts: const [])
              .classification,
          InternalTransferMatchClassification.notEligible,
        );
      }
    });

    test(
      '5,000 drafts use keyed candidate buckets and retain every result',
      () {
        final sources = List.generate(
          5000,
          (index) => _candidate(
            id: 'out-$index',
            type: TransactionType.expense,
            amount: 100000 + index,
          ),
        );
        final counterparts = List.generate(
          5000,
          (index) => _candidate(
            id: 'in-$index',
            accountId: 'bank',
            type: TransactionType.income,
            amount: 100000 + index,
          ),
        );
        final results = matcher.matchAll(
          sources: sources,
          counterparts: counterparts,
        );
        expect(results, hasLength(5000));
        expect(
          results.values.every(
            (item) =>
                item.classification ==
                InternalTransferMatchClassification.strong,
          ),
          isTrue,
        );
      },
    );
  });

  test(
    'draft to existing conversion is atomic and preserves both IDs',
    () async {
      final setup = await _Setup.create('draft-existing');
      addTearDown(setup.dispose);
      final existing = _transaction(
        id: 'existing-out',
        account: 'Cash',
        type: TransactionType.expense,
      );
      await setup.repository.save(existing);
      final beforeOutbox = (await setup.store.getEligibleSyncOperations(
        'book-1',
      )).length;
      final draft = _transaction(
        id: 'draft-in',
        account: 'Bank',
        type: TransactionType.income,
      );
      final converted = await setup.service.convertDraftExisting(
        draft: draft,
        existingTransactionId: existing.id,
        expectedExistingVersion: existing.version,
        draftAccountId: setup.bank.id,
        existingAccountId: setup.cash.id,
      );
      expect(converted.outgoing.id, 'existing-out');
      expect(converted.incoming.id, 'draft-in');
      expect((await setup.repository.getAll()).map((item) => item.id).toSet(), {
        'existing-out',
        'draft-in',
      });
      expect(await setup.repository.getTransferLinks(), hasLength(1));
      final afterOutbox = await setup.store.getEligibleSyncOperations('book-1');
      expect(afterOutbox.length, beforeOutbox + 2);
      expect(afterOutbox.skip(beforeOutbox).map((row) => row['entity_type']), [
        'transactions',
        'transfer_links',
      ]);

      final rows = await setup.repository.getAll();
      final summary = FinancialSummary.calculate(
        transactions: rows,
        transferLinks: [converted.link],
        referenceDate: DateTime(2026, 8, 19),
      );
      expect(summary.monthlyIncome, 0);
      expect(summary.monthlyExpenses, 0);
      expect(
        AccountBalanceCalculator.calculate(
          account: setup.cash,
          transactions: rows,
        ),
        -100000,
      );
      expect(
        AccountBalanceCalculator.calculate(
          account: setup.bank,
          transactions: rows,
        ),
        100000,
      );
    },
  );

  test(
    'reversed draft direction creates correct directional relation',
    () async {
      final setup = await _Setup.create('reversed');
      addTearDown(setup.dispose);
      final existing = _transaction(
        id: 'existing-in',
        account: 'Bank',
        type: TransactionType.income,
      );
      await setup.repository.save(existing);
      final converted = await setup.service.convertDraftExisting(
        draft: _transaction(
          id: 'draft-out',
          account: 'Cash',
          type: TransactionType.expense,
        ),
        existingTransactionId: existing.id,
        expectedExistingVersion: 1,
        draftAccountId: setup.cash.id,
        existingAccountId: setup.bank.id,
      );
      expect(converted.link.outgoingTransactionId, 'draft-out');
      expect(converted.link.incomingTransactionId, 'existing-in');
    },
  );

  test(
    'draft pair conversion is atomic and preserves deterministic IDs',
    () async {
      final setup = await _Setup.create('draft-pair');
      addTearDown(setup.dispose);
      final converted = await setup.service.convertDraftPair(
        first: _transaction(
          id: 'draft-out',
          account: 'Cash',
          type: TransactionType.expense,
        ),
        second: _transaction(
          id: 'draft-in',
          account: 'Bank',
          type: TransactionType.income,
        ),
        firstAccountId: setup.cash.id,
        secondAccountId: setup.bank.id,
      );
      expect(converted.link.outgoingTransactionId, 'draft-out');
      expect(converted.link.incomingTransactionId, 'draft-in');
      expect(await setup.repository.getAll(), hasLength(2));
      expect(await setup.repository.getTransferLinks(), hasLength(1));
    },
  );

  test('stale preview leaves draft, link, and outbox absent', () async {
    final setup = await _Setup.create('stale');
    addTearDown(setup.dispose);
    final existing = _transaction(
      id: 'existing',
      account: 'Cash',
      type: TransactionType.expense,
    );
    await setup.repository.save(existing);
    await setup.repository.save(
      existing.copyWith(version: 2, title: 'changed'),
    );
    final before = (await setup.store.getEligibleSyncOperations(
      'book-1',
    )).length;
    await expectLater(
      setup.service.convertDraftExisting(
        draft: _transaction(
          id: 'draft',
          account: 'Bank',
          type: TransactionType.income,
        ),
        existingTransactionId: existing.id,
        expectedExistingVersion: 1,
        draftAccountId: setup.bank.id,
        existingAccountId: setup.cash.id,
      ),
      throwsA(anything),
    );
    expect(
      (await setup.repository.getAll()).map((item) => item.id),
      isNot(contains('draft')),
    );
    expect(await setup.repository.getTransferLinks(), isEmpty);
    expect(
      (await setup.store.getEligibleSyncOperations('book-1')).length,
      before,
    );
  });

  test(
    'repeat conversion cannot create a duplicate transfer or outbox',
    () async {
      final setup = await _Setup.create('repeat');
      addTearDown(setup.dispose);
      final existing = _transaction(
        id: 'existing',
        account: 'Cash',
        type: TransactionType.expense,
      );
      final draft = _transaction(
        id: 'draft',
        account: 'Bank',
        type: TransactionType.income,
      );
      await setup.repository.save(existing);
      await setup.service.convertDraftExisting(
        draft: draft,
        existingTransactionId: existing.id,
        expectedExistingVersion: 1,
        draftAccountId: setup.bank.id,
        existingAccountId: setup.cash.id,
      );
      final before = (await setup.store.getEligibleSyncOperations(
        'book-1',
      )).length;
      await expectLater(
        setup.service.convertDraftExisting(
          draft: draft,
          existingTransactionId: existing.id,
          expectedExistingVersion: 1,
          draftAccountId: setup.bank.id,
          existingAccountId: setup.cash.id,
        ),
        throwsA(anything),
      );
      expect(await setup.repository.getAll(), hasLength(2));
      expect(await setup.repository.getTransferLinks(), hasLength(1));
      expect(
        (await setup.store.getEligibleSyncOperations('book-1')).length,
        before,
      );
    },
  );

  testWidgets('review screen exposes safety copy, filters, and confirmation', (
    tester,
  ) async {
    final cash = _account('cash', 'Cash');
    final bank = _account('bank', 'Bank');
    final outgoing = _transaction(
      id: 'out',
      account: 'Cash',
      type: TransactionType.expense,
    );
    final incoming = _transaction(
      id: 'in',
      account: 'Bank',
      type: TransactionType.income,
    );
    final controller = InternalTransferReviewController(
      transactions: [outgoing, incoming],
      accounts: [cash, bank],
      links: const [],
      service: InternalTransferService(
        _ReadOnlyTransferRepository(
          transactions: [outgoing, incoming],
          accounts: [cash, bank],
        ),
      ),
      now: DateTime(2026, 8, 19),
    );
    await controller.scan();
    await tester.pumpWidget(
      MaterialApp(home: InternalTransferReviewScreen(controller: controller)),
    );
    expect(find.text('Review possible transfers'), findsOneWidget);
    expect(
      find.textContaining('Nothing changes until you confirm'),
      findsOneWidget,
    );
    expect(find.text('Strong'), findsOneWidget);
    expect(find.text('Cash → Bank'), findsOneWidget);
    await tester.ensureVisible(find.text('Review'));
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Convert these entries into an internal transfer?'),
      findsOneWidget,
    );
    expect(
      find.textContaining('not counted as household income or expense'),
      findsOneWidget,
    );
    expect(find.text('Keep separate'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

InternalTransferCandidate _candidate({
  required String id,
  String bookId = 'book-1',
  String accountId = 'cash',
  String accountName = 'Cash',
  String currency = 'IDR',
  DateTime? date,
  required TransactionType type,
  int amount = 100000,
  String description = 'Posting',
  String reference = '',
  bool deleted = false,
  bool paired = false,
}) => InternalTransferCandidate(
  id: id,
  bookId: bookId,
  accountId: accountId,
  accountName: accountName,
  currencyCode: currency,
  date: date ?? DateTime(2026, 8, 19),
  type: type,
  amount: amount,
  description: description,
  reference: reference,
  source: InternalTransferCandidateSource.existing,
  deleted: deleted,
  alreadyPaired: paired,
);

Transaction _transaction({
  required String id,
  required String account,
  required TransactionType type,
}) => Transaction(
  id: id,
  bookId: 'book-1',
  title: 'TRANSFER',
  category: type == TransactionType.expense ? 'Expense' : 'Income',
  account: account,
  date: DateTime(2026, 8, 19),
  amount: 100000,
  type: type,
  createdAt: DateTime(2026, 8, 19),
  updatedAt: DateTime(2026, 8, 19),
  syncStatus: 'pending',
);

Account _account(String id, String name) => Account(
  id: id,
  bookId: 'book-1',
  name: name,
  accountType: AccountType.bank,
  currencyCode: 'IDR',
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
);

class _Setup {
  const _Setup(
    this.fixture,
    this.store,
    this.repository,
    this.service,
    this.cash,
    this.bank,
  );
  final _Fixture fixture;
  final LocalStore store;
  final LocalTransactionRepository repository;
  final InternalTransferService service;
  final Account cash;
  final Account bank;

  static Future<_Setup> create(String name) async {
    final fixture = await _Fixture.create(name);
    final store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    const timestamp = 1787184000000;
    await store.upsertFinancialBook({
      'id': 'book-1',
      'name': 'Matcher household',
      'base_currency_code': 'IDR',
      'created_at': timestamp,
      'updated_at': timestamp,
      'deleted_at': null,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': 'synced',
      'remote_linked_at': timestamp,
    }, enqueueSync: false);
    store.setActiveBookId('book-1');
    final cash = _account('cash', 'Cash');
    final bank = _account('bank', 'Bank');
    await store.upsertAccount(cash.toRecord(), enqueueSync: false);
    await store.upsertAccount(bank.toRecord(), enqueueSync: false);
    final repository = LocalTransactionRepository(store);
    return _Setup(
      fixture,
      store,
      repository,
      InternalTransferService(repository),
      cash,
      bank,
    );
  }

  Future<void> dispose() async {
    await store.close();
    await fixture.dispose();
  }
}

class _ReadOnlyTransferRepository implements InternalTransferRepository {
  const _ReadOnlyTransferRepository({
    required this.transactions,
    required this.accounts,
  });

  final List<Transaction> transactions;
  final List<Account> accounts;

  @override
  Future<List<Account>> getAllAccounts({bool includeDeleted = false}) async =>
      accounts;

  @override
  Future<List<Transaction>> getAllTransactions({
    bool includeDeleted = false,
  }) async => transactions;

  @override
  Future<List<InternalTransferLink>> getTransferLinks({
    bool includeDeleted = false,
  }) async => const [];

  @override
  Future<void> saveInternalTransferAtomic({
    required List<Transaction> transactions,
    required InternalTransferLink link,
    Map<String, int> expectedTransactionVersions = const {},
    Set<String> requireNewTransactionIds = const {},
  }) => throw UnsupportedError('The UI test does not confirm a transfer.');
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta08f1-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
