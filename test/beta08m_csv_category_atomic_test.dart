import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:pilgrim_tracker/features/backup/data/local_household_backup_store.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/sync/data/initial_sync_store_native.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_models.dart';
import 'package:pilgrim_tracker/features/transactions/data/local_import_review_repository.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/import_review_draft.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/import_review_session.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_category_review.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_import_rule_engine.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/internal_transfer_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    expect(LocalStore.schemaVersion, native.LocalStore.schemaVersion);
  });

  test(
    'create intent survives restart and discard without creating a category',
    () async {
      final fixture = await _Fixture.create('deferred');
      addTearDown(fixture.dispose);
      var controller = await fixture.controller(_source(['Transport']));
      final transactionId = controller.preview!.drafts.single.transactionId;

      expect(
        await controller.createCategoryForDraft(transactionId, 'Transport'),
        isTrue,
      );
      controller.reset();
      expect(await fixture.namedCategories('Transport'), isEmpty);
      controller.dispose();

      controller = await fixture.controller(_source(['Transport']));
      expect(
        await controller.createCategoryForDraft(
          controller.preview!.drafts.single.transactionId,
          'Transport',
        ),
        isTrue,
      );
      final plannedId = controller.preview!.drafts.single.plannedCategoryId;
      expect(await fixture.namedCategories('Transport'), isEmpty);

      final session = await controller.saveForLater();
      expect(session, isNotNull);
      expect(await fixture.namedCategories('Transport'), isEmpty);
      controller.dispose();
      await fixture.reopen();

      final repository = LocalImportReviewRepository(fixture.store);
      final saved = await repository.load(session!.id);
      controller = await fixture.controller(null, analyze: false);
      addTearDown(controller.dispose);
      await controller.loadSavedReview(saved!);
      final restored = controller.preview!.drafts.single;
      expect(
        restored.categoryResolution,
        TransactionImportCategoryResolution.createCategory,
      );
      expect(restored.sourceCategory, 'Transport');
      expect(restored.plannedCategoryId, plannedId);
      expect(await fixture.namedCategories('Transport'), isEmpty);

      await controller.discardSavedReview();
      expect(await fixture.namedCategories('Transport'), isEmpty);
      expect(await fixture.store.getTransactions(), isEmpty);
    },
  );

  test('all four review resolutions survive database restart', () async {
    final fixture = await _Fixture.create('review-states');
    addTearDown(fixture.dispose);
    var controller = await fixture.controller(
      _source(['Map me', 'Create me', 'Ignore me', 'Pending']),
    );
    final bySource = {
      for (final draft in controller.preview!.drafts)
        draft.sourceCategory: draft.transactionId,
    };
    controller.mapCategory(bySource['Map me']!, 'Travel');
    await controller.createCategoryForDraft(
      bySource['Create me']!,
      'Created Category',
    );
    controller.ignoreCategory(bySource['Ignore me']!);
    final session = await controller.saveForLater();
    controller.dispose();
    await fixture.reopen();

    final bundle = await LocalImportReviewRepository(
      fixture.store,
    ).load(session!.id);
    controller = await fixture.controller(null, analyze: false);
    addTearDown(controller.dispose);
    await controller.loadSavedReview(bundle!);
    final restored = {
      for (final draft in controller.preview!.drafts)
        draft.sourceCategory: draft,
    };
    expect(
      restored['Map me']!.categoryResolution,
      TransactionImportCategoryResolution.mapToExisting,
    );
    expect(restored['Map me']!.category, 'Travel');
    expect(
      restored['Create me']!.categoryResolution,
      TransactionImportCategoryResolution.createCategory,
    );
    expect(restored['Create me']!.plannedCategoryId, isNotNull);
    expect(
      restored['Ignore me']!.categoryResolution,
      TransactionImportCategoryResolution.ignore,
    );
    expect(
      restored['Pending']!.categoryResolution,
      TransactionImportCategoryResolution.unresolved,
    );
    expect(await fixture.namedCategories('Created Category'), isEmpty);
  });

  test(
    'final commit creates one category and repeated transactions atomically',
    () async {
      final fixture = await _Fixture.create('commit', linked: true);
      addTearDown(fixture.dispose);
      await fixture.store.db.delete('sync_outbox');
      final source = _source(['Dining Out', ' dining  out ']);
      final controller = await fixture.controller(source);
      addTearDown(controller.dispose);
      final originalIds = controller.preview!.drafts
          .map((draft) => draft.transactionId)
          .toList();

      await controller.createCategoryForDraft(originalIds.first, 'Dining Out');
      expect(await fixture.namedCategories('Dining Out'), isEmpty);
      await controller.commit();

      final categories = await fixture.namedCategories('Dining Out');
      final transactions = await fixture.store.getTransactions();
      expect(controller.error, isNull);
      expect(categories, hasLength(1));
      expect(transactions, hasLength(2));
      expect(transactions.map((row) => row['category_id']).toSet(), {
        categories.single['id'],
      });
      expect(transactions.map((row) => row['id']), containsAll(originalIds));
      final outbox = await fixture.store.getEligibleSyncOperations(_bookId);
      expect(
        outbox.where((row) => row['entity_type'] == 'categories'),
        hasLength(1),
      );
      expect(
        outbox.where((row) => row['entity_type'] == 'transactions'),
        hasLength(2),
      );
    },
  );

  test(
    'failed atomic commit rolls back category transaction and outbox',
    () async {
      final fixture = await _Fixture.create('rollback', linked: true);
      addTearDown(fixture.dispose);
      await fixture.store.db.delete('sync_outbox');
      final repository = LocalTransactionRepository(fixture.store as dynamic);
      final now = DateTime(2026, 9, 1);
      Transaction transaction(String title) => Transaction(
        id: 'duplicate-import-id',
        bookId: _bookId,
        title: title,
        category: 'Atomic Category',
        categoryId: 'planned-category-id',
        account: _account.name,
        date: now,
        amount: 1000,
        type: TransactionType.expense,
      );

      await expectLater(
        repository.saveImportAtomic(
          transactions: [transaction('First'), transaction('Second')],
          categoryCreations: const [
            TransactionImportCategoryCreation(
              id: 'planned-category-id',
              bookId: _bookId,
              name: 'Atomic Category',
              type: TransactionType.expense,
            ),
          ],
          transferMutations: const [],
        ),
        throwsStateError,
      );
      expect(await fixture.namedCategories('Atomic Category'), isEmpty);
      expect(await fixture.store.getTransactions(), isEmpty);
      expect(await fixture.store.getEligibleSyncOperations(_bookId), isEmpty);
    },
  );

  test(
    'web store mirrors deferred category atomic commit and rollback',
    () async {
      const webBookId = '22222222-2222-4222-8222-222222222222';
      final store = web.LocalStore(databasePath: 'beta08m-web-atomic');
      await store.initialize();
      await store.upsertFinancialBook(
        FinancialBook(
          id: webBookId,
          name: 'Web household',
          remoteLinkedAt: DateTime(2026, 9, 9),
        ).toRecord(),
        enqueueSync: false,
      );
      store.setActiveBookId(webBookId);
      final transaction = Transaction(
        id: 'web-import-transaction',
        bookId: webBookId,
        title: 'Web import',
        category: 'Web Category',
        categoryId: 'web-planned-category',
        account: 'Web Bank',
        date: DateTime(2026, 9, 1),
        amount: 1000,
        type: TransactionType.expense,
      ).toRecord();
      final category = <String, Object?>{
        'id': 'web-planned-category',
        'book_id': webBookId,
        'name': 'Web Category',
        'category_type': 'expense',
      };

      final resolved = await store.insertTransactionImportAtomic(
        transactions: [transaction],
        categoryCreations: [category],
        transferLinks: const [],
      );
      expect(resolved['web-planned-category'], 'web-planned-category');
      expect(
        await store.getMasterNames('categories', categoryType: 'expense'),
        contains('Web Category'),
      );
      expect(await store.getTransactions(), hasLength(1));

      await expectLater(
        store.insertTransactionImportAtomic(
          transactions: [
            {...transaction, 'id': 'web-duplicate'},
            {...transaction, 'id': 'web-duplicate'},
          ],
          categoryCreations: const [
            {
              'id': 'web-rollback-category',
              'book_id': webBookId,
              'name': 'Web Rollback',
              'category_type': 'expense',
            },
          ],
          transferLinks: const [],
        ),
        throwsStateError,
      );
      expect(
        await store.getMasterNames('categories', categoryType: 'expense'),
        isNot(contains('Web Rollback')),
      );
      expect(await store.getTransactions(), hasLength(1));
    },
  );

  test(
    'exact reimport after deferred creation remains duplicate-safe',
    () async {
      final fixture = await _Fixture.create('reimport', linked: true);
      addTearDown(fixture.dispose);
      final source = _source(['Dining Out', 'Dining Out']);
      var controller = await fixture.controller(source);
      await controller.createCategoryForDraft(
        controller.preview!.drafts.first.transactionId,
        'Dining Out',
      );
      await controller.commit();
      expect(controller.error, isNull);
      controller.dispose();
      final firstOutboxCount = (await fixture.store.getEligibleSyncOperations(
        _bookId,
      )).length;

      controller = await fixture.controller(source);
      addTearDown(controller.dispose);
      expect(
        controller.preview!.drafts.map((draft) => draft.classification).toSet(),
        {TransactionImportClassification.alreadyImported},
      );
      await controller.commit();

      expect(await fixture.namedCategories('Dining Out'), hasLength(1));
      expect(await fixture.store.getTransactions(), hasLength(2));
      expect(
        (await fixture.store.getEligibleSyncOperations(_bookId)).length,
        firstOutboxCount,
      );
    },
  );

  test(
    'Tithe variants use canonical identity and preserve name collision',
    () async {
      final fixture = await _Fixture.create('tithe');
      addTearDown(fixture.dispose);
      await fixture.store.ensureSystemCategories(_bookId);
      await fixture.insertCategory('custom-tithe', 'Tithe');
      final before = await fixture.namedCategories('Tithe');
      final controller = await fixture.controller(
        _source(['Tithe', 'tithe', ' TITHE ']),
      );
      addTearDown(controller.dispose);

      expect(before, hasLength(2));
      expect(
        controller.preview!.drafts
            .map((draft) => draft.categoryResolution)
            .toSet(),
        {TransactionImportCategoryResolution.mapToExisting},
      );
      await controller.commit();
      final canonicalId = SystemCategoryIds.tithe(_bookId);
      expect(controller.error, isNull);
      expect(await fixture.namedCategories('Tithe'), hasLength(2));
      expect(
        (await fixture.store.getTransactions())
            .map((row) => row['category_id'])
            .toSet(),
        {canonicalId},
      );
      expect(
        (await fixture.store.getCategoryRecords(
          includeDeleted: true,
        )).where((row) => row['id'] == 'custom-tithe'),
        hasLength(1),
      );
    },
  );

  test(
    'source-neutral Tithe keeps canonical identity without rule metadata',
    () async {
      final fixture = await _Fixture.create('source-neutral-tithe');
      addTearDown(fixture.dispose);
      await fixture.store.ensureSystemCategories(_bookId);
      final session = ImportReviewSession(
        id: 'source-neutral-tithe-session',
        bookId: _bookId,
        sourceType: ImportReviewSourceType.receipt,
        title: 'Source-neutral Tithe',
        sourceFingerprint: 'source-neutral-tithe-source',
        destinationAccountId: _account.id,
      );
      final draft = ImportReviewDraft(
        id: 'source-neutral-tithe-draft',
        sessionId: session.id,
        bookId: _bookId,
        sourceRowIdentity: 'source-neutral-tithe-fingerprint',
        sourceRowKey: 'source-neutral-tithe-row',
        deterministicTransactionId: 'source-neutral-tithe-transaction',
        deterministicTransactionAccountId: _account.id,
        sourceIndex: 1,
        transactionDate: DateTime(2026, 9, 1),
        description: 'Tithe payment',
        amountMinor: 100000,
        currencyCode: 'IDR',
        transactionType: TransactionType.expense,
        categoryName: 'Tithe',
        categoryProvenance: TransactionImportCategorySource.source,
      );
      final reviewRepository = LocalImportReviewRepository(fixture.store);
      final bundle = ImportReviewBundle(session: session, drafts: [draft]);
      await reviewRepository.save(bundle);
      final controller = await fixture.controller(
        null,
        analyze: false,
        exposeRuleCategories: false,
      );
      addTearDown(controller.dispose);

      await controller.loadSavedReview(bundle);
      await controller.commit();

      expect(controller.error, isNull);
      expect(
        (await fixture.store.getTransactions()).single['category_id'],
        SystemCategoryIds.tithe(_bookId),
      );
    },
  );

  test(
    'confirmed transfer remains uncategorized and commits in one boundary',
    () async {
      final fixture = await _Fixture.create('transfer', linked: true);
      addTearDown(fixture.dispose);
      final repository = LocalTransactionRepository(fixture.store as dynamic);
      final existing = Transaction(
        id: 'existing-transfer-leg',
        bookId: _bookId,
        title: 'Move cash',
        category: '',
        account: _cashAccount.name,
        date: DateTime(2026, 9, 1),
        amount: 50000,
        type: TransactionType.income,
      );
      await repository.save(existing);
      final draft = Transaction(
        id: 'imported-transfer-leg',
        bookId: _bookId,
        title: 'Move cash',
        category: 'Source CSV Category',
        categoryId: 'planned-category-id',
        account: _account.name,
        date: DateTime(2026, 9, 1),
        amount: 50000,
        type: TransactionType.expense,
      );
      final plan = await InternalTransferService(repository).planDraftExisting(
        draft: draft,
        existingTransactionId: existing.id,
        expectedExistingVersion: existing.version,
        draftAccountId: _account.id,
        existingAccountId: _cashAccount.id,
      );

      expect(plan.importedDraft.category, 'Transfer');
      expect(plan.importedDraft.categoryId, isNull);
      await repository.saveImportAtomic(
        transactions: [plan.importedDraft],
        categoryCreations: const [],
        transferMutations: [plan.mutation],
      );
      final saved = Transaction.fromRecord(
        (await fixture.store.getTransactions())
            .where((row) => row['id'] == draft.id)
            .single,
      );
      expect(saved.category, 'Transfer');
      expect(saved.categoryId, isNull);
      expect(await fixture.store.getTransferLinks(), hasLength(1));
    },
  );

  test(
    'offline outbox bootstraps one category and its transactions to a new device',
    () async {
      final fixture = await _Fixture.create('sync-source', linked: true);
      addTearDown(fixture.dispose);
      await fixture.store.db.delete('sync_outbox');
      final controller = await fixture.controller(_source(['Transport']));
      addTearDown(controller.dispose);
      await controller.createCategoryForDraft(
        controller.preview!.drafts.single.transactionId,
        'Transport',
      );
      await controller.commit();
      final pending = await fixture.store.getEligibleSyncOperations(_bookId);
      expect(
        pending.map((row) => row['entity_type']),
        containsAll(['categories', 'transactions']),
      );

      final sourceAdapter = InitialSyncStoreAdapter(fixture.store);
      final manifest = await sourceAdapter.captureUploadSnapshot(_bookId);
      final target = await _EmptyStore.create('sync-target');
      addTearDown(target.dispose);
      final targetAdapter = InitialSyncStoreAdapter(target.store);
      await targetAdapter.startInitialization(
        bookId: _bookId,
        direction: InitialSyncDirection.download,
        sessionId: 'beta08m-download',
        manifest: manifest,
      );
      for (final entity in initialSyncEntityOrder) {
        final rows = await sourceAdapter.readUploadRows(
          _bookId,
          entity,
          limit: 100,
        );
        await targetAdapter.stageDownloadBatch(
          _bookId,
          InitialSyncBatch(
            entityType: entity,
            rows: rows,
            nextCursor: null,
            complete: true,
          ),
        );
      }
      await targetAdapter.activateDownload(
        bookId: _bookId,
        manifest: manifest,
        authUserId: null,
      );
      target.store.setActiveBookId(_bookId);

      final targetCategories = await target.store.getCategoryRecords();
      final targetTransactions = await target.store.getTransactions();
      expect(
        targetCategories.where(
          (row) => _normalize(row['name'] as String) == 'transport',
        ),
        hasLength(1),
      );
      expect(targetTransactions, hasLength(1));
      expect(
        targetTransactions.single['category_id'],
        targetCategories
            .where((row) => _normalize(row['name'] as String) == 'transport')
            .single['id'],
      );
      expect(await target.store.getPendingSyncCount(_bookId), 0);
    },
  );

  test(
    'committed category and transaction survive encrypted backup restore',
    () async {
      final fixture = await _Fixture.create('backup');
      addTearDown(fixture.dispose);
      final controller = await fixture.controller(_source(['Transport']));
      addTearDown(controller.dispose);
      await controller.createCategoryForDraft(
        controller.preview!.drafts.single.transactionId,
        'Transport',
      );
      await controller.commit();
      final service = HouseholdBackupService(
        LocalHouseholdBackupStore(fixture.store as dynamic),
      );
      final created = await service.create(
        bookId: _bookId,
        password: 'beta08m-password',
        exportedAt: DateTime(2026, 9, 9),
      );
      expect(created.manifest.formatVersion, 6);

      final target = await _EmptyStore.create('backup-target');
      addTearDown(target.dispose);
      final targetService = HouseholdBackupService(
        LocalHouseholdBackupStore(target.store as dynamic),
      );
      final decoded = await targetService.validate(
        created.bytes,
        'beta08m-password',
      );
      await targetService.restore(
        backup: decoded,
        mode: RestoreMode.newHousehold,
        activeBookId: 'unused-local-household',
      );
      target.store.setActiveBookId(_bookId);

      expect(
        (await target.store.getCategoryRecords()).where(
          (row) => _normalize(row['name'] as String) == 'transport',
        ),
        hasLength(1),
      );
      expect(await target.store.getTransactions(), hasLength(1));
    },
  );
}

const _bookId = '11111111-1111-4111-8111-111111111111';
final _account = Account(
  id: 'account-bank',
  bookId: _bookId,
  name: 'Bank',
  accountType: AccountType.bank,
  currencyCode: 'IDR',
  openingBalanceDate: DateTime(2026, 1, 1),
);
final _cashAccount = Account(
  id: 'account-cash',
  bookId: _bookId,
  name: 'Cash',
  accountType: AccountType.cash,
  currencyCode: 'IDR',
  openingBalanceDate: DateTime(2026, 1, 1),
);
const _mapping = TransactionImportMapping(
  dateColumn: 0,
  descriptionColumn: 1,
  amountColumn: 2,
  typeColumn: 3,
  categoryColumn: 4,
);

CsvParsedSource _source(List<String> categories) => CsvParsedSource(
  fileName: 'categories.csv',
  fileFingerprint: 'beta08m-source',
  delimiter: ',',
  headers: const ['date', 'description', 'amount', 'type', 'category'],
  rows: [
    for (var index = 0; index < categories.length; index += 1)
      CsvSourceRow(
        rowNumber: index + 2,
        identityKey: 'row-$index',
        values: [
          '2026-09-01',
          'Purchase $index',
          '1000',
          'expense',
          categories[index],
        ],
      ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

class _Fixture extends _EmptyStore {
  _Fixture(super.directory, super.path, super.store, {required this.linked});

  final bool linked;

  static Future<_Fixture> create(String name, {bool linked = false}) async {
    final empty = await _EmptyStore.create(name);
    final fixture = _Fixture(
      empty.directory,
      empty.path,
      empty.store,
      linked: linked,
    );
    final now = DateTime(2026, 9, 9).millisecondsSinceEpoch;
    await fixture.store.db.insert('books', {
      'id': _bookId,
      'name': 'BETA-08M Household',
      'base_currency_code': 'IDR',
      'remote_linked_at': linked ? now : null,
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': linked ? 'synced' : 'local_only',
    });
    fixture.store.setActiveBookId(_bookId);
    await fixture.store.db.insert('household_members', {
      'id': 'member-owner',
      'book_id': _bookId,
      'display_name': 'Owner',
      'role': 'owner',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': linked ? 'synced' : 'local_only',
    });
    await fixture.store.db.insert('accounts', _account.toRecord());
    await fixture.store.db.insert('accounts', _cashAccount.toRecord());
    await fixture.insertCategory('category-travel', 'Travel');
    await fixture.insertCategory('category-business', 'Business');
    return fixture;
  }

  Future<void> insertCategory(String id, String name) async {
    final now = DateTime(2026, 9, 9).millisecondsSinceEpoch;
    await store.db.insert('categories', {
      'id': id,
      'book_id': _bookId,
      'name': name,
      'category_type': 'expense',
      'created_at': now,
      'updated_at': now,
      'version': 1,
      'device_id': 'device-1',
      'sync_status': linked ? 'synced' : 'local_only',
    });
  }

  Future<List<Map<String, Object?>>> namedCategories(String name) async =>
      (await store.getCategoryRecords(includeDeleted: true))
          .where((row) => _normalize(row['name'] as String) == _normalize(name))
          .toList();

  Future<TransactionImportController> controller(
    CsvParsedSource? source, {
    bool analyze = true,
    bool exposeRuleCategories = true,
  }) async {
    final rows = await store.getCategoryRecords();
    final categories = {
      for (final row in rows)
        row['id'] as String: ImportRuleCategory(
          id: row['id'] as String,
          bookId: row['book_id'] as String,
          name: row['name'] as String,
          type: TransactionType.values.byName(row['category_type'] as String),
        ),
    };
    final repository = LocalTransactionRepository(store as dynamic);
    final controller = TransactionImportController(
      pickFile: () async => null,
      importBatch: ImportTransactionsBatch(repository),
      existingTransactions: () => repository.getAll(includeDeleted: true),
      accounts: [_account, _cashAccount],
      expenseCategories: rows
          .where((row) => row['category_type'] == 'expense')
          .map((row) => row['name'] as String)
          .toList(),
      incomeCategories: rows
          .where((row) => row['category_type'] == 'income')
          .map((row) => row['name'] as String)
          .toList(),
      activeBookId: _bookId,
      activeMemberId: null,
      ruleCategories: () async => exposeRuleCategories ? categories : const {},
      importReviewRepository: LocalImportReviewRepository(store),
    );
    if (source != null) {
      controller.loadPreparedSource(source);
      controller.setMapping(_mapping);
      controller.selectAccount(_account);
      if (analyze) await controller.analyze();
    }
    return controller;
  }

  @override
  Future<void> reopen() async {
    await super.reopen();
    store.setActiveBookId(_bookId);
  }
}

class _EmptyStore {
  _EmptyStore(this.directory, this.path, this.store);

  final Directory directory;
  final String path;
  native.LocalStore store;

  static Future<_EmptyStore> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta08m-$name-');
    final path = p.join(directory.path, 'pilgrim.db');
    final store = native.LocalStore(databasePath: path);
    await store.initialize();
    return _EmptyStore(directory, path, store);
  }

  Future<void> reopen() async {
    await store.close();
    store = native.LocalStore(databasePath: path);
    await store.initialize();
  }

  Future<void> dispose() async {
    await store.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
