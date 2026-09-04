import 'dart:io';

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
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_identity.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_import_rule_engine.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nullable identity and account binding round-trip', () {
    final draft = _unresolvedBundle().drafts.single;
    final restored = ImportReviewDraft.fromRecord(draft.toRecord());
    expect(restored.id, draft.id);
    expect(restored.sourceRowIdentity, 'row-fingerprint');
    expect(restored.sourceRowKey, 'source-row-1');
    expect(restored.deterministicTransactionId, isNull);
    expect(restored.deterministicTransactionAccountId, isNull);
  });

  test('unresolved session persists across close and reopen', () async {
    final fixture = await _Fixture.create('restart');
    addTearDown(fixture.dispose);
    final bundle = _unresolvedBundle();
    await LocalImportReviewRepository(fixture.store).save(bundle);
    await fixture.reopen();
    final loaded = await LocalImportReviewRepository(
      fixture.store,
    ).load(bundle.session.id);
    expect(loaded!.session.destinationAccountId, isNull);
    expect(loaded.drafts.single.id, 'draft-unresolved');
    expect(loaded.drafts.single.sourceRowKey, 'source-row-1');
    expect(loaded.drafts.single.deterministicTransactionId, isNull);
    expect(loaded.drafts.single.deterministicTransactionAccountId, isNull);
  });

  test(
    'unresolved remote apply preserves null identity without echo',
    () async {
      final fixture = await _Fixture.create('remote', linked: true);
      addTearDown(fixture.dispose);
      final bundle = _unresolvedBundle();
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
      final loaded = await LocalImportReviewRepository(
        fixture.store,
      ).load(bundle.session.id);
      expect(loaded!.session.destinationAccountId, isNull);
      expect(loaded.drafts.single.deterministicTransactionId, isNull);
      expect(await fixture.store.getTransactions(), isEmpty);
      expect(await fixture.store.getEligibleSyncOperations('book-1'), isEmpty);
    },
  );

  test(
    'later account selection produces the existing canonical UUID',
    () async {
      final fixture = await _Fixture.create('golden');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final source = _source();
      final knownFirst = await const TransactionImportPlanner().build(
        source: source,
        mapping: canonicalMappingFor(source.headers)!,
        account: _accountA(),
        activeBookId: 'book-1',
        existingTransactions: const [],
        expenseCategories: const ['Travel'],
        incomeCategories: const ['Salary'],
      );
      final planned = knownFirst.drafts.single;
      final unresolved = _unresolvedBundle(
        sourceFingerprint: source.fileFingerprint,
        sourceRowKey: planned.sourceRowIdentity!,
        rowFingerprint: planned.sourceRowFingerprint,
      );
      await repository.save(unresolved);
      final controller = _controller(repository);
      await controller.loadSavedReview(unresolved);
      expect(controller.preview, isNull);
      controller.selectAccount(_accountA());
      await controller.analyze();
      expect(
        controller.preview!.drafts.single.transactionId,
        planned.transactionId,
      );
      final stableDraftId = unresolved.drafts.single.id;
      final stableSource = unresolved.drafts.single.sourceRowIdentity;
      await controller.saveForLater();
      final saved = (await repository.load(unresolved.session.id))!;
      expect(saved.drafts.single.id, stableDraftId);
      expect(saved.drafts.single.sourceRowIdentity, stableSource);
      expect(
        saved.drafts.single.deterministicTransactionId,
        planned.transactionId,
      );
      expect(
        saved.drafts.single.deterministicTransactionAccountId,
        'account-a',
      );
      controller.dispose();
    },
  );

  test(
    'account change rederives identity without changing draft or source',
    () async {
      final fixture = await _Fixture.create('account-change');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _unresolvedBundle();
      await repository.save(bundle);
      final controller = _controller(repository);
      await controller.loadSavedReview(bundle);
      controller.selectAccount(_accountA());
      await controller.analyze();
      final accountAId = controller.preview!.drafts.single.transactionId;
      await controller.saveForLater();
      controller.selectAccount(_accountB());
      expect(controller.preview, isNull);
      await controller.analyze();
      final accountBId = controller.preview!.drafts.single.transactionId;
      expect(accountBId, isNot(accountAId));
      expect(
        accountBId,
        TransactionImportIdentity.derive(
          bookId: 'book-1',
          accountId: 'account-b',
          sourceFingerprint: 'source-fingerprint',
          sourceRowIdentity: 'source-row-1',
          sourceRowFingerprint: 'row-fingerprint',
        ),
      );
      await controller.saveForLater();
      final saved = (await repository.load(bundle.session.id))!;
      expect(saved.drafts.single.id, 'draft-unresolved');
      expect(saved.drafts.single.sourceRowIdentity, 'row-fingerprint');
      expect(
        saved.drafts.single.deterministicTransactionAccountId,
        'account-b',
      );
      expect(await fixture.store.getTransactions(), isEmpty);
      controller.dispose();
    },
  );

  test(
    'unresolved commit is blocked without transaction or financial outbox',
    () async {
      final fixture = await _Fixture.create('blocked', linked: true);
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _unresolvedBundle();
      await repository.save(bundle);
      for (final operation in await fixture.store.getEligibleSyncOperations(
        'book-1',
      )) {
        await fixture.store.completeSyncOperation(
          operation['operation_id']! as String,
        );
      }
      final controller = _controller(repository);
      await controller.loadSavedReview(bundle);
      await controller.commit();
      expect(controller.error, 'Select destination account before importing.');
      expect(await fixture.store.getTransactions(), isEmpty);
      expect(
        (await fixture.store.getEligibleSyncOperations(
          'book-1',
        )).where((row) => row['entity_type'] == 'transactions'),
        isEmpty,
      );
      expect(
        (await repository.load(bundle.session.id))!.session.state,
        ImportReviewSessionState.pendingReview,
      );
      controller.dispose();
    },
  );

  test('resolved deferred draft commits through normal import path', () async {
    final fixture = await _Fixture.create('commit');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final bundle = _unresolvedBundle();
    await repository.save(bundle);
    final controller = _controller(repository);
    await controller.loadSavedReview(bundle);
    controller.selectAccount(_accountA());
    await controller.analyze();
    await controller.commit();
    expect(controller.error, isNull);
    final transactions = await fixture.store.getTransactions();
    expect(transactions, hasLength(1));
    final saved = (await repository.load(bundle.session.id))!;
    expect(saved.session.state, ImportReviewSessionState.completed);
    expect(
      saved.drafts.single.deterministicTransactionId,
      transactions.single['id'],
    );
    expect(saved.drafts.single.deterministicTransactionAccountId, 'account-a');
    controller.dispose();
  });

  test(
    'excluded unresolved draft completes without fabricated identity',
    () async {
      final fixture = await _Fixture.create('excluded');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _unresolvedBundle(included: false);
      await repository.save(bundle);
      final controller = _controller(repository);
      await controller.loadSavedReview(bundle);
      controller.selectAccount(_accountA());
      await controller.analyze();
      await controller.commit();
      final saved = (await repository.load(bundle.session.id))!;
      expect(saved.session.state, ImportReviewSessionState.completed);
      expect(saved.drafts.single.deterministicTransactionId, isNull);
      expect(saved.drafts.single.deterministicTransactionAccountId, isNull);
      expect(await fixture.store.getTransactions(), isEmpty);
      controller.dispose();
    },
  );

  test('account-scoped rules wait for account then reanalyze', () async {
    final fixture = await _Fixture.create('rules');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final bundle = _unresolvedBundle(category: '');
    await repository.save(bundle);
    final rule = TransactionImportRule(
      id: 'account-a-taxi',
      bookId: 'book-1',
      name: 'Account A taxi',
      priority: 10,
      transactionType: TransactionImportRuleType.expense,
      matchField: TransactionImportRuleMatchField.description,
      operator: TransactionImportRuleOperator.contains,
      pattern: 'taxi',
      categoryId: 'category-travel',
      accountId: 'account-a',
    );
    final controller = _controller(repository, rules: [rule]);
    await controller.loadSavedReview(bundle);
    expect(controller.preview, isNull);
    controller.selectAccount(_accountA());
    await controller.analyze();
    expect(controller.preview!.drafts.single.category, 'Travel');
    expect(
      controller.preview!.drafts.single.categorySource,
      TransactionImportCategorySource.rule,
    );
    controller.dispose();
  });

  test('deferred crash reconciliation recognizes the finalized ID', () async {
    final fixture = await _Fixture.create('reconcile');
    addTearDown(fixture.dispose);
    final repository = LocalImportReviewRepository(fixture.store);
    final bundle = _unresolvedBundle();
    await repository.save(bundle);
    final first = _controller(repository);
    await first.loadSavedReview(bundle);
    first.selectAccount(_accountA());
    await first.analyze();
    await first.saveForLater();
    final finalized = (await repository.load(bundle.session.id))!;
    final id = finalized.drafts.single.deterministicTransactionId!;
    await fixture.store.upsertTransaction(
      Transaction(
        id: id,
        bookId: 'book-1',
        title: 'Taxi',
        category: 'Travel',
        account: 'Bank A',
        date: DateTime(2026, 8, 2),
        amount: 50000,
        type: TransactionType.expense,
      ).toRecord(),
      enqueueSync: false,
    );
    first.dispose();
    final reopened = _controller(repository);
    await reopened.loadSavedReview(finalized);
    expect(reopened.error, isNull);
    expect(
      (await repository.load(bundle.session.id))!.session.state,
      ImportReviewSessionState.completed,
    );
    expect(await fixture.store.getTransactions(), hasLength(1));
    reopened.dispose();
  });

  test(
    'concurrent account choices cannot silently commit two identities',
    () async {
      final fixture = await _Fixture.create('concurrent');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final bundle = _unresolvedBundle();
      await repository.save(bundle);
      final deviceA = _controller(repository);
      final deviceB = _controller(repository);
      await deviceA.loadSavedReview(bundle);
      await deviceB.loadSavedReview(bundle);
      deviceA.selectAccount(_accountA());
      await deviceA.analyze();
      await deviceA.saveForLater();
      deviceB.selectAccount(_accountB());
      await deviceB.analyze();
      await deviceB.commit();
      expect(deviceB.error, contains('changed on another device'));
      expect(await fixture.store.getTransactions(), isEmpty);
      final saved = (await repository.load(bundle.session.id))!;
      expect(saved.session.destinationAccountId, 'account-a');
      expect(
        saved.drafts.single.deterministicTransactionAccountId,
        'account-a',
      );
      deviceA.dispose();
      deviceB.dispose();
    },
  );

  test(
    'v24 to v25 preserves ID and backfills proven account binding',
    () async {
      final fixture = await _Fixture.create('migration');
      addTearDown(fixture.dispose);
      final repository = LocalImportReviewRepository(fixture.store);
      final resolved = _resolvedBundle();
      await repository.save(resolved);
      await fixture.store.db.execute('DROP TABLE import_review_drafts');
      await fixture.store.db.execute('''
      CREATE TABLE import_review_drafts (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL, book_id TEXT NOT NULL,
        source_row_identity TEXT NOT NULL,
        deterministic_transaction_id TEXT NOT NULL, source_index INTEGER NOT NULL,
        transaction_date INTEGER NOT NULL, description TEXT NOT NULL,
        amount_minor INTEGER NOT NULL, currency_code TEXT NOT NULL,
        transaction_type TEXT NOT NULL, category_name TEXT NOT NULL DEFAULT '',
        category_id TEXT, category_provenance TEXT NOT NULL,
        reference_text TEXT NOT NULL DEFAULT '', note_text TEXT NOT NULL DEFAULT '',
        merchant_hint TEXT NOT NULL DEFAULT '', included INTEGER NOT NULL DEFAULT 1,
        user_edited_fields_json TEXT NOT NULL DEFAULT '[]',
        warnings_json TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL, deleted_at INTEGER, version INTEGER NOT NULL,
        device_id TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'local_only'
      )
    ''');
      final oldRecord =
          Map<String, Object?>.of(resolved.drafts.single.toRecord())
            ..remove('source_row_key')
            ..remove('deterministic_transaction_account_id');
      await fixture.store.db.insert('import_review_drafts', oldRecord);
      await fixture.store.db.execute('PRAGMA user_version = 24');
      await fixture.reopen();
      expect(await fixture.store.db.getVersion(), 25);
      final migrated = (await LocalImportReviewRepository(
        fixture.store,
      ).load(resolved.session.id))!.drafts.single;
      expect(migrated.deterministicTransactionId, 'existing-final-id');
      expect(migrated.deterministicTransactionAccountId, 'account-a');
      expect(migrated.sourceRowKey, '1');
    },
  );
}

ImportReviewBundle _unresolvedBundle({
  bool included = true,
  String category = 'Travel',
  String sourceFingerprint = 'source-fingerprint',
  String sourceRowKey = 'source-row-1',
  String rowFingerprint = 'row-fingerprint',
}) {
  final session = ImportReviewSession(
    id: 'session-unresolved',
    bookId: 'book-1',
    sourceType: ImportReviewSourceType.csv,
    title: 'Deferred review',
    sourceFingerprint: sourceFingerprint,
    summary: const {'row_count': 1},
  );
  return ImportReviewBundle(
    session: session,
    drafts: [
      ImportReviewDraft(
        id: 'draft-unresolved',
        sessionId: session.id,
        bookId: session.bookId,
        sourceRowIdentity: rowFingerprint,
        sourceRowKey: sourceRowKey,
        sourceIndex: 1,
        transactionDate: DateTime(2026, 8, 2),
        description: 'Taxi',
        amountMinor: 50000,
        currencyCode: 'IDR',
        transactionType: TransactionType.expense,
        categoryName: category,
        categoryId: category.isEmpty ? null : 'category-travel',
        categoryProvenance: category.isEmpty
            ? TransactionImportCategorySource.unresolved
            : TransactionImportCategorySource.manual,
        included: included,
      ),
    ],
  );
}

ImportReviewBundle _resolvedBundle() {
  final unresolved = _unresolvedBundle();
  return ImportReviewBundle(
    session: unresolved.session.copyWith(destinationAccountId: 'account-a'),
    drafts: [
      ImportReviewDraft(
        id: unresolved.drafts.single.id,
        sessionId: unresolved.session.id,
        bookId: 'book-1',
        sourceRowIdentity: 'row-fingerprint',
        sourceRowKey: 'source-row-1',
        deterministicTransactionId: 'existing-final-id',
        deterministicTransactionAccountId: 'account-a',
        sourceIndex: 1,
        transactionDate: DateTime(2026, 8, 2),
        description: 'Taxi',
        amountMinor: 50000,
        currencyCode: 'IDR',
        transactionType: TransactionType.expense,
      ),
    ],
  );
}

CsvParsedSource _source() => const CsvParsedSource(
  fileName: 'deferred.csv',
  fileFingerprint: 'source-fingerprint',
  delimiter: ',',
  headers: [
    'Date',
    'Description',
    'Amount',
    'Type',
    'Category',
    'Reference',
    'Note',
  ],
  rows: [
    CsvSourceRow(
      rowNumber: 1,
      identityKey: 'source-row-1',
      values: ['2026-08-02', 'Taxi', '50000', 'expense', 'Travel', '', ''],
    ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

TransactionImportController _controller(
  LocalImportReviewRepository repository, {
  List<TransactionImportRule> rules = const [],
}) => TransactionImportController(
  pickFile: () async => null,
  importBatch: ImportTransactionsBatch(
    LocalTransactionRepository(repository.store),
  ),
  existingTransactions: () async => List<Map<String, Object?>>.from(
    await repository.store.getTransactions(includeDeleted: true),
  ).map(Transaction.fromRecord).toList(),
  accounts: [_accountA(), _accountB()],
  expenseCategories: const ['Travel'],
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
  },
);

Account _accountA() => Account(
  id: 'account-a',
  bookId: 'book-1',
  name: 'Bank A',
  accountType: AccountType.bank,
  currencyCode: 'IDR',
);

Account _accountB() => Account(
  id: 'account-b',
  bookId: 'book-1',
  name: 'Bank B',
  accountType: AccountType.bank,
  currencyCode: 'IDR',
);

class _Fixture {
  _Fixture(this.directory, this.path, this.store);
  final Directory directory;
  final String path;
  LocalStore store;

  static Future<_Fixture> create(String name, {bool linked = false}) async {
    final directory = await Directory.systemTemp.createTemp('beta08g1-$name-');
    final path = p.join(directory.path, 'pilgrim.db');
    final store = LocalStore(databasePath: path);
    await store.initialize();
    final now = DateTime(2026, 8, 30).millisecondsSinceEpoch;
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
    await store.db.insert('accounts', _accountA().toRecord());
    await store.db.insert('accounts', _accountB().toRecord());
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
