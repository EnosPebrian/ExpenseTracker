import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/data/local_import_review_repository.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/import_review_draft.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/import_review_session.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_import_rule.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_import_rule_engine.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/import/import_review_inbox_screen.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/sync/data/initial_sync_store_native.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('SQLite 23 to current migration is additive', () async {
    final fixture = await _Fixture.create('migration');
    addTearDown(fixture.dispose);
    var store = fixture.store;
    await store.db.execute('DROP TABLE import_review_drafts');
    await store.db.execute('DROP TABLE import_review_sessions');
    await store.db.execute('PRAGMA user_version = 23');
    await store.close();
    store = LocalStore(databasePath: fixture.path);
    await store.initialize();
    fixture.store = store;
    expect(await store.db.getVersion(), 25);
    expect(
      (await store.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'import_review_%'",
      )).map((row) => row['name']).toSet(),
      {'import_review_sessions', 'import_review_drafts'},
    );
  });

  test('fresh database is created at SQLite version 25', () async {
    final fixture = await _Fixture.create('fresh-v24');
    addTearDown(fixture.dispose);
    expect(await fixture.store.db.getVersion(), 25);
  });

  test('session and normalized drafts survive close and reopen', () async {
    final fixture = await _Fixture.create('restart');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final original = _bundle();
    await repository.save(original);
    await fixture.reopen();
    final loaded = await LocalImportReviewRepository(
      fixture.store,
    ).load(original.session.id);
    expect(loaded, isNotNull);
    expect(loaded!.session.sourceFingerprint, 'fingerprint-1');
    expect(loaded.session.summary['safe'], 'metadata');
    expect(loaded.drafts.single.deterministicTransactionId, 'transaction-1');
    expect(loaded.drafts.single.userEditedFields, {'description', 'category'});
    expect(loaded.drafts.single.categoryProvenance.name, 'manual');
  });

  test('local-only inbox creates no cloud outbox operations', () async {
    final fixture = await _Fixture.create('local-only');
    addTearDown(fixture.dispose);
    await LocalImportReviewRepository(fixture.store).save(_bundle());
    expect(await fixture.store.getEligibleSyncOperations('book-1'), isEmpty);
  });

  test('linked inbox uses normal session and draft outbox entities', () async {
    final fixture = await _Fixture.create('linked', linked: true);
    addTearDown(fixture.dispose);
    await LocalImportReviewRepository(fixture.store).save(_bundle());
    final operations = await fixture.store.getEligibleSyncOperations('book-1');
    expect(operations.map((row) => row['entity_type']), [
      'import_review_sessions',
      'import_review_drafts',
    ]);
  });

  test('foreign household category is rejected atomically', () async {
    final fixture = await _Fixture.create('foreign-category');
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 8, 29).millisecondsSinceEpoch;
    await fixture.store.db.insert('books', {
      'id': 'book-2',
      'name': 'Other household',
      'base_currency_code': 'IDR',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-2',
      'sync_status': 'local_only',
    });
    await fixture.store.db.insert('categories', {
      'id': 'foreign-category',
      'book_id': 'book-2',
      'name': 'Foreign',
      'category_type': 'expense',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-2',
      'sync_status': 'local_only',
    });
    final session = _bundle().session;
    final foreignDraft = ImportReviewDraft(
      id: 'foreign-draft',
      sessionId: session.id,
      bookId: session.bookId,
      sourceRowIdentity: 'foreign-row',
      sourceRowKey: '1',
      deterministicTransactionId: 'foreign-transaction',
      deterministicTransactionAccountId: 'account-1',
      sourceIndex: 1,
      transactionDate: DateTime(2026, 8, 2),
      description: 'Foreign category',
      amountMinor: 100,
      currencyCode: 'IDR',
      transactionType: TransactionType.expense,
      categoryName: 'Foreign',
      categoryId: 'foreign-category',
      categoryProvenance: TransactionImportCategorySource.manual,
    );
    await expectLater(
      LocalImportReviewRepository(
        fixture.store,
      ).save(ImportReviewBundle(session: session, drafts: [foreignDraft])),
      throwsStateError,
    );
    expect(await fixture.store.getImportReviewSessions(), isEmpty);
    expect(
      await fixture.store.getImportReviewDrafts(sessionId: session.id),
      isEmpty,
    );
  });

  test(
    'discard tombstones workflow only and creates no transaction mutation',
    () async {
      final fixture = await _Fixture.create('discard', linked: true);
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _bundle();
      await repository.save(bundle);
      await repository.discard(bundle.session.id);
      final loaded = await repository.load(bundle.session.id);
      expect(loaded!.session.state, ImportReviewSessionState.discarded);
      expect(loaded.session.deletedAt, isNotNull);
      expect(loaded.drafts.single.deletedAt, isNotNull);
      expect(await fixture.store.getTransactions(), isEmpty);
      final operations = await fixture.store.getEligibleSyncOperations(
        'book-1',
      );
      expect(
        operations.where((row) => row['entity_type'] == 'transactions'),
        isEmpty,
      );
    },
  );

  test('state machine rejects terminal reopen', () {
    final session = _bundle().session;
    expect(
      session
          .transition(ImportReviewSessionState.readyToCommit)
          .transition(ImportReviewSessionState.completed)
          .state,
      ImportReviewSessionState.completed,
    );
    expect(
      () => session.transition(ImportReviewSessionState.completed),
      throwsStateError,
    );
    expect(
      () => session
          .transition(ImportReviewSessionState.readyToCommit)
          .transition(ImportReviewSessionState.pendingReview),
      throwsStateError,
    );
    expect(
      () => session
          .transition(ImportReviewSessionState.discarded)
          .transition(ImportReviewSessionState.pendingReview),
      throwsStateError,
    );
  });

  test('remote apply stores inbox records without echo outbox', () async {
    final fixture = await _Fixture.create('remote', linked: true);
    addTearDown(fixture.dispose);
    final bundle = _bundle();
    await fixture.store.applyRemoteSyncBatch(
      'book-1',
      changes: [
        {
          'entity_type': 'import_review_sessions',
          'entity_id': bundle.session.id,
          'payload': bundle.session.toRecord(),
        },
        {
          'entity_type': 'import_review_drafts',
          'entity_id': bundle.drafts.single.id,
          'payload': bundle.drafts.single.toRecord(),
        },
      ],
      finalSequence: 2,
    );
    expect((await fixture.store.getImportReviewSessions()).length, 1);
    expect(
      await fixture.store.getImportReviewDrafts(sessionId: bundle.session.id),
      hasLength(1),
    );
    expect(await fixture.store.getEligibleSyncOperations('book-1'), isEmpty);
  });

  test('initial upload snapshot contains pending session and drafts', () async {
    final fixture = await _Fixture.create('initial-upload', linked: true);
    addTearDown(fixture.dispose);
    await LocalImportReviewRepository(fixture.store).save(_bundle());
    final adapter = InitialSyncStoreAdapter(fixture.store);
    final manifest = await adapter.captureUploadSnapshot('book-1');
    expect(manifest.counts['import_review_sessions'], 1);
    expect(manifest.counts['import_review_drafts'], 1);
    expect(
      await adapter.readUploadRows('book-1', 'import_review_sessions'),
      hasLength(1),
    );
    expect(
      await adapter.readUploadRows('book-1', 'import_review_drafts'),
      hasLength(1),
    );
  });

  test(
    'controller save and reopen preserves IDs and manual category',
    () async {
      final fixture = await _Fixture.create('controller');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final controller = _controller(repository);
      controller.loadPreparedSource(_source());
      controller.selectAccount(_account());
      await controller.analyze();
      final transactionId = controller.preview!.drafts.single.transactionId;
      controller.editDraft(transactionId, category: 'Travel');
      controller.toggleIncluded(transactionId, false);
      final session = await controller.saveForLater();
      expect(session, isNotNull);
      controller.dispose();

      final reopened = _controller(repository);
      await reopened.loadSavedReview((await repository.load(session!.id))!);
      final draft = reopened.preview!.drafts.single;
      expect(draft.transactionId, transactionId);
      expect(draft.category, 'Travel');
      expect(draft.categorySource, TransactionImportCategorySource.manual);
      expect(draft.included, isFalse);
      expect(reopened.transferMatches, isEmpty);
      reopened.dispose();
    },
  );

  test(
    'stable ID with different financial content blocks resumed commit',
    () async {
      final fixture = await _Fixture.create('identity-conflict');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _bundle();
      await repository.save(bundle);
      await fixture.store.upsertTransaction(
        Transaction(
          id: 'transaction-1',
          bookId: 'book-1',
          title: 'Different',
          category: 'Travel',
          account: 'Bank',
          date: DateTime(2026, 8, 3),
          amount: 999,
          type: TransactionType.expense,
        ).toRecord(),
        enqueueSync: false,
      );
      final controller = _controller(repository);
      await controller.loadSavedReview(bundle);
      final draft = controller.preview!.drafts.single;
      expect(draft.classification, TransactionImportClassification.invalid);
      expect(draft.issues.single.blocking, isTrue);
      expect(controller.preview!.readyCount, 0);
      controller.dispose();
    },
  );

  test('reopen recalculates duplicates against current transactions', () async {
    final fixture = await _Fixture.create('duplicate-reanalysis');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final bundle = _bundle();
    await repository.save(bundle);
    await fixture.store.upsertTransaction(
      Transaction(
        id: 'independently-created',
        bookId: 'book-1',
        title: 'Taxi',
        category: 'Travel',
        account: 'Bank',
        date: DateTime(2026, 8, 2),
        amount: 50000,
        type: TransactionType.expense,
      ).toRecord(),
      enqueueSync: false,
    );
    final controller = _controller(repository);
    await controller.loadSavedReview(bundle);
    expect(
      controller.preview!.drafts.single.classification,
      TransactionImportClassification.semanticDuplicate,
    );
    expect(controller.preview!.drafts.single.included, isFalse);
    controller.dispose();
  });

  test(
    'reopen applies a current rule only to an unresolved category',
    () async {
      final fixture = await _Fixture.create('rule-reanalysis');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final original = _controller(repository);
      original.loadPreparedSource(_source());
      original.selectAccount(_account());
      await original.analyze();
      final session = await original.saveForLater();
      original.dispose();

      final rule = TransactionImportRule(
        id: 'taxi-rule',
        bookId: 'book-1',
        name: 'Taxi to fuel',
        priority: 10,
        transactionType: TransactionImportRuleType.expense,
        matchField: TransactionImportRuleMatchField.description,
        operator: TransactionImportRuleOperator.contains,
        pattern: 'taxi',
        categoryId: 'category-fuel',
      );
      final reopened = _controller(repository, rules: [rule]);
      await reopened.loadSavedReview((await repository.load(session!.id))!);
      expect(reopened.preview!.drafts.single.category, 'Fuel');
      expect(
        reopened.preview!.drafts.single.categorySource,
        TransactionImportCategorySource.rule,
      );
      reopened.dispose();
    },
  );

  test('reopen discovers a new current transfer counterpart', () async {
    final fixture = await _Fixture.create('transfer-reanalysis');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final bundle = _bundle();
    await repository.save(bundle);
    await fixture.store.upsertTransaction(
      Transaction(
        id: 'cash-counterpart',
        bookId: 'book-1',
        title: 'Transfer from Bank',
        category: 'Transfer',
        account: 'Cash',
        date: DateTime(2026, 8, 2),
        amount: 50000,
        type: TransactionType.income,
      ).toRecord(),
      enqueueSync: false,
    );
    final controller = _controller(
      repository,
      accounts: [_account(), _cashAccount()],
    );
    await controller.loadSavedReview(bundle);
    expect(controller.transferMatches['transaction-1'], isNotNull);
    expect(
      controller.transferMatches['transaction-1']!.counterpart!.id,
      'cash-counterpart',
    );
    controller.dispose();
  });

  test(
    'stale second controller cannot commit the same session twice',
    () async {
      final fixture = await _Fixture.create('concurrent-commit');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _bundle();
      await repository.save(bundle);
      final first = _controller(repository);
      final second = _controller(repository);
      await first.loadSavedReview(bundle);
      await second.loadSavedReview(bundle);
      await first.commit();
      await second.commit();
      expect(await fixture.store.getTransactions(), hasLength(1));
      expect(second.error, contains('changed on another device'));
      first.dispose();
      second.dispose();
    },
  );

  test(
    'receipt and statement normalized drafts can be saved for later',
    () async {
      final fixture = await _Fixture.create('document-sources');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);

      final receipt = _controller(repository);
      receipt.loadPreparedSource(_source());
      receipt.selectAccount(_account());
      await receipt.analyze();
      final receiptSession = await receipt.saveForLater(
        sourceType: ImportReviewSourceType.receipt,
        title: 'IKEA receipt',
        summary: const {'merchant': 'IKEA'},
      );
      receipt.dispose();

      final statement = _controller(repository);
      statement.loadPreparedSource(_source());
      statement.selectAccount(_account());
      await statement.analyze();
      final statementSession = await statement.saveForLater(
        sourceType: ImportReviewSourceType.bankStatement,
        title: 'BCA August 2026',
        summary: const {'institution': 'BCA', 'period': '2026-08'},
      );
      statement.dispose();

      expect(
        (await repository.load(receiptSession!.id))!.session.sourceType,
        ImportReviewSourceType.receipt,
      );
      expect(
        (await repository.load(statementSession!.id))!.session.sourceType,
        ImportReviewSourceType.bankStatement,
      );
    },
  );

  test('persistent review commits once and becomes completed', () async {
    final fixture = await _Fixture.create('commit');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final controller = _controller(repository);
    controller.loadPreparedSource(_source());
    controller.selectAccount(_account());
    await controller.analyze();
    controller.editDraft(
      controller.preview!.drafts.single.transactionId,
      category: 'Travel',
    );
    final session = await controller.saveForLater();
    await controller.commit();
    expect(controller.error, isNull);
    expect(await fixture.store.getTransactions(), hasLength(1));
    expect(
      (await repository.load(session!.id))!.session.state,
      ImportReviewSessionState.completed,
    );
    controller.dispose();
  });

  test('crash reconciliation recognizes exact committed stable IDs', () async {
    final fixture = await _Fixture.create('reconcile');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final bundle = _bundle();
    await repository.save(bundle);
    await fixture.store.upsertTransaction(
      Transaction(
        id: 'transaction-1',
        bookId: 'book-1',
        title: 'Taxi',
        category: 'Travel',
        account: 'Bank',
        date: DateTime(2026, 8, 2),
        amount: 50000,
        type: TransactionType.expense,
      ).toRecord(),
      enqueueSync: false,
    );
    final controller = _controller(repository);
    await controller.loadSavedReview(bundle);
    expect(controller.error, isNull);
    expect(
      (await repository.load(bundle.session.id))!.session.state,
      ImportReviewSessionState.completed,
    );
    expect(await fixture.store.getTransactions(), hasLength(1));
    controller.dispose();
  });

  test('five sessions including a 5000-row statement reopen', () async {
    final fixture = await _Fixture.create('performance');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    for (var sessionIndex = 0; sessionIndex < 5; sessionIndex++) {
      final session = ImportReviewSession(
        id: 'session-$sessionIndex',
        bookId: 'book-1',
        sourceType: ImportReviewSourceType.bankStatement,
        title: 'Statement $sessionIndex',
        sourceFingerprint: 'fingerprint-$sessionIndex',
        destinationAccountId: 'account-1',
      );
      final count = sessionIndex == 4 ? 5000 : 1;
      await repository.save(
        ImportReviewBundle(
          session: session,
          drafts: List.generate(
            count,
            (index) => ImportReviewDraft(
              id: 'draft-$sessionIndex-$index',
              sessionId: session.id,
              bookId: 'book-1',
              sourceRowIdentity: 'row-$index',
              sourceRowKey: '$index',
              deterministicTransactionId: 'tx-$sessionIndex-$index',
              deterministicTransactionAccountId: 'account-1',
              sourceIndex: index,
              transactionDate: DateTime(2026, 8, 1),
              description: 'Statement row $index',
              amountMinor: index + 1,
              currencyCode: 'IDR',
              transactionType: TransactionType.expense,
            ),
          ),
        ),
      );
    }
    expect(await repository.sessions(bookId: 'book-1'), hasLength(5));
    expect((await repository.load('session-4'))!.drafts, hasLength(5000));
  });

  testWidgets('inbox renders the pending empty state', (tester) async {
    final repository = LocalImportReviewRepository(
      LocalStore(databasePath: 'unused-widget-test.db'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImportReviewInboxScreen(
          repository: repository,
          bookId: 'book-1',
          onReview: (_) async {},
          initialSessions: const [],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Import Inbox'), findsOneWidget);
    expect(find.textContaining('No pending imports.'), findsOneWidget);
    expect(find.text('Pending (0)'), findsOneWidget);
  });

  testWidgets('inbox shows saved CSV review actions and counts', (
    tester,
  ) async {
    final repository = LocalImportReviewRepository(
      LocalStore(databasePath: 'unused-widget-test.db'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImportReviewInboxScreen(
          repository: repository,
          bookId: 'book-1',
          onReview: (_) async {},
          initialSessions: [_bundle().session],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('August CSV'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Pending (1)'), findsOneWidget);
    expect(find.textContaining('1 drafts'), findsOneWidget);
  });
}

ImportReviewBundle _bundle() {
  final session = ImportReviewSession(
    id: 'session-1',
    bookId: 'book-1',
    sourceType: ImportReviewSourceType.csv,
    title: 'August CSV',
    sourceFingerprint: 'fingerprint-1',
    destinationAccountId: 'account-1',
    summary: const {'safe': 'metadata', 'row_count': 1},
    createdAt: DateTime(2026, 8, 29),
    updatedAt: DateTime(2026, 8, 29),
  );
  return ImportReviewBundle(
    session: session,
    drafts: [
      ImportReviewDraft(
        id: 'draft-1',
        sessionId: session.id,
        bookId: session.bookId,
        sourceRowIdentity: 'row-1',
        sourceRowKey: '1',
        deterministicTransactionId: 'transaction-1',
        deterministicTransactionAccountId: 'account-1',
        sourceIndex: 1,
        transactionDate: DateTime(2026, 8, 2),
        description: 'Taxi',
        amountMinor: 50000,
        currencyCode: 'IDR',
        transactionType: TransactionType.expense,
        categoryName: 'Travel',
        categoryId: 'category-travel',
        categoryProvenance: TransactionImportCategorySource.manual,
        userEditedFields: const {'description', 'category'},
        createdAt: DateTime(2026, 8, 29),
        updatedAt: DateTime(2026, 8, 29),
      ),
    ],
  );
}

TransactionImportController _controller(
  LocalImportReviewRepository repository, {
  List<TransactionImportRule> rules = const [],
  List<Account>? accounts,
}) => TransactionImportController(
  pickFile: () async => null,
  importBatch: ImportTransactionsBatch(
    LocalTransactionRepository(repository.store),
  ),
  existingTransactions: () async {
    final rows = List<Map<String, Object?>>.from(
      await repository.store.getTransactions(includeDeleted: true),
    );
    return rows.map(Transaction.fromRecord).toList();
  },
  accounts: accounts ?? [_account()],
  expenseCategories: const ['Travel', 'Fuel'],
  incomeCategories: const ['Salary'],
  activeBookId: 'book-1',
  activeMemberId: null,
  importReviewRepository: repository,
  importRules: () async => rules,
  ruleCategories: () async => const {
    'category-travel': ImportRuleCategory(
      id: 'category-travel',
      bookId: 'book-1',
      name: 'Travel',
      type: TransactionType.expense,
    ),
    'category-fuel': ImportRuleCategory(
      id: 'category-fuel',
      bookId: 'book-1',
      name: 'Fuel',
      type: TransactionType.expense,
    ),
  },
);

Account _account() => Account(
  id: 'account-1',
  bookId: 'book-1',
  name: 'Bank',
  accountType: AccountType.bank,
  currencyCode: 'IDR',
  openingBalanceDate: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Account _cashAccount() => Account(
  id: 'account-cash',
  bookId: 'book-1',
  name: 'Cash',
  accountType: AccountType.cash,
  currencyCode: 'IDR',
  openingBalanceDate: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

CsvParsedSource _source() => CsvParsedSource(
  fileName: 'august.csv',
  fileFingerprint: 'controller-fingerprint',
  delimiter: ',',
  headers: const [
    'Date',
    'Description',
    'Amount',
    'Type',
    'Category',
    'Reference',
    'Note',
  ],
  rows: const [
    CsvSourceRow(
      rowNumber: 1,
      identityKey: 'row-controller-1',
      values: ['2026-08-02', 'Taxi', '50000', 'expense', '', '', ''],
    ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

class _Fixture {
  _Fixture(this.directory, this.path, this.store);

  final Directory directory;
  final String path;
  LocalStore store;

  static Future<_Fixture> create(String name, {bool linked = false}) async {
    final directory = await Directory.systemTemp.createTemp('beta08g-$name-');
    final path = p.join(directory.path, 'pilgrim.db');
    final store = LocalStore(databasePath: path);
    await store.initialize();
    final now = DateTime(2026, 8, 29).millisecondsSinceEpoch;
    await store.db.insert('books', {
      'id': 'book-1',
      'name': 'Household',
      'base_currency_code': 'IDR',
      'remote_linked_at': linked ? now : null,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': linked ? 'synced' : 'local_only',
    });
    await store.db.insert('accounts', _account().toRecord());
    await store.db.insert('categories', {
      'id': 'category-travel',
      'book_id': 'book-1',
      'name': 'Travel',
      'category_type': 'expense',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': linked ? 'synced' : 'local_only',
    });
    await store.db.insert('categories', {
      'id': 'category-fuel',
      'book_id': 'book-1',
      'name': 'Fuel',
      'category_type': 'expense',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': linked ? 'synced' : 'local_only',
    });
    store.setActiveBookId('book-1');
    return _Fixture(directory, path, store);
  }

  Future<void> reopen() async {
    await store.close();
    store = LocalStore(databasePath: path);
    await store.initialize();
    store.setActiveBookId('book-1');
  }

  Future<void> dispose() async {
    await store.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
