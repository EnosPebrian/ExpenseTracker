import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/csv_export_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/budgets/domain/entities/monthly_category_budget.dart';
import 'package:pilgrim_tracker/features/budgets/domain/services/monthly_budget_calculator.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/services/account_balance_calculator.dart';
import 'package:pilgrim_tracker/features/sync/data/initial_sync_store_native.dart';
import 'package:pilgrim_tracker/features/sync/domain/initial_sync_models.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/internal_transfer_integrity_validator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/internal_transfer_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/screens/transaction_list_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'SQLite 22 to 23 is additive and leaves legacy transfer untouched',
    () async {
      final fixture = await _Fixture.create('migration');
      addTearDown(fixture.dispose);
      var store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      await _prepareStore(store);
      final legacy = _transaction(
        id: 'legacy-transfer',
        type: TransactionType.transfer,
        account: 'Cash -> Bank',
      );
      await store.upsertTransaction(legacy.toRecord(), enqueueSync: false);
      await store.db.execute('DROP TABLE transfer_links');
      await store.db.execute('PRAGMA user_version = 22');
      await store.close();

      store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      final version = await store.db.rawQuery('PRAGMA user_version');
      expect(version.single['user_version'], 25);
      expect(native.LocalStore.schemaVersion, 25);
      expect((await store.getTransactions()).single['id'], legacy.id);
      expect(
        (await store.getTransactions()).single['transaction_type'],
        'transfer',
      );
      expect(await store.getTransferLinks(), isEmpty);
    },
  );

  test(
    'manual create persists two stable legs, one link, and three outbox rows',
    () async {
      final setup = await _Setup.create('manual');
      addTearDown(setup.dispose);
      final before = (await setup.store.getEligibleSyncOperations(
        'book-1',
      )).length;
      final transfer = await setup.service.create(
        bookId: 'book-1',
        enteredByMemberId: null,
        title: 'Move cash',
        sourceAccountId: setup.cash.id,
        destinationAccountId: setup.bank.id,
        date: DateTime(2026, 8, 20),
        amount: 250000,
        outgoingTransactionId: 'outgoing-1',
        incomingTransactionId: 'incoming-1',
        linkId: 'link-1',
      );

      expect(transfer.outgoing.id, 'outgoing-1');
      expect(transfer.incoming.id, 'incoming-1');
      expect(transfer.link.id, 'link-1');
      expect(transfer.outgoing.type, TransactionType.expense);
      expect(transfer.incoming.type, TransactionType.income);
      expect(await setup.store.getTransactions(), hasLength(2));
      expect(await setup.store.getTransferLinks(), hasLength(1));
      final outbox = await setup.store.getEligibleSyncOperations('book-1');
      expect(outbox.length, before + 3);
      expect(outbox.skip(before).map((row) => row['entity_type']), [
        'transactions',
        'transactions',
        'transfer_links',
      ]);

      final transactions = await setup.repository.getAll();
      final cash = AccountBalanceCalculator.calculate(
        account: setup.cash,
        transactions: transactions,
      );
      final bank = AccountBalanceCalculator.calculate(
        account: setup.bank,
        transactions: transactions,
      );
      expect(cash, -250000);
      expect(bank, 250000);
      expect(cash + bank, 0);

      final summary = FinancialSummary.calculate(
        transactions: transactions,
        transferLinks: [transfer.link],
        referenceDate: DateTime(2026, 8, 20),
      );
      expect(summary.monthlyIncome, 0);
      expect(summary.monthlyExpenses, 0);
      expect(summary.monthlyTithe, 0);
      expect(summary.recordedBalance, 0);
      expect(summary.activityCount, 1);

      final budget = MonthlyBudgetCalculator.calculate(
        month: DateTime(2026, 8),
        budgets: [
          MonthlyCategoryBudget(
            id: 'budget-1',
            bookId: 'book-1',
            categoryId: 'transfer-category',
            monthStart: DateTime(2026, 8),
            limitMinor: 500000,
            currencyCode: 'IDR',
          ),
        ],
        transactions: transactions,
        categoryNamesById: const {'transfer-category': 'Transfer'},
        pairedTransactionIds: transfer.link.transactionIds,
      );
      expect(budget.totalSpendMinor, 0);

      final controller = TransactionController(
        create: CreateTransaction(setup.repository),
        update: UpdateTransaction(setup.repository),
        delete: DeleteTransaction(setup.repository),
        get: GetTransactions(setup.repository),
        duplicate: DuplicateTransaction(setup.repository),
        internalTransfers: setup.service,
      );
      await controller.load();
      expect(controller.displayTransactions, hasLength(1));
      expect(
        controller.displayTransactions.single.type,
        TransactionType.transfer,
      );
      expect(controller.displayTransactions.single.account, 'Cash -> Bank');
    },
  );

  test('edit keeps all IDs coherent and stale versions are rejected', () async {
    final setup = await _Setup.create('edit');
    addTearDown(setup.dispose);
    final created = await setup.createTransfer();
    final edited = await setup.service.edit(
      linkId: created.link.id,
      expectedLinkVersion: created.link.version,
      expectedOutgoingVersion: created.outgoing.version,
      expectedIncomingVersion: created.incoming.version,
      title: 'Edited transfer',
      sourceAccountId: setup.bank.id,
      destinationAccountId: setup.cash.id,
      date: DateTime(2026, 8, 21),
      amount: 90000,
    );
    expect(edited.link.id, created.link.id);
    expect(edited.outgoing.id, created.outgoing.id);
    expect(edited.incoming.id, created.incoming.id);
    expect(edited.outgoing.account, 'Bank');
    expect(edited.incoming.account, 'Cash');
    expect(edited.outgoing.amount, 90000);
    expect(edited.incoming.amount, 90000);
    await expectLater(
      setup.service.edit(
        linkId: edited.link.id,
        expectedLinkVersion: 1,
        expectedOutgoingVersion: 1,
        expectedIncomingVersion: 1,
        title: 'Stale',
        sourceAccountId: setup.cash.id,
        destinationAccountId: setup.bank.id,
        date: DateTime(2026, 8, 22),
        amount: 1,
      ),
      throwsA(isA<InternalTransferValidationException>()),
    );
  });

  test(
    'convert preserves both imported IDs and unpair restores classification',
    () async {
      final setup = await _Setup.create('convert');
      addTearDown(setup.dispose);
      final outgoing = _transaction(
        id: 'import-out',
        type: TransactionType.expense,
        account: 'Cash',
        amount: 70000,
      );
      final incoming = _transaction(
        id: 'import-in',
        type: TransactionType.income,
        account: 'Bank',
        amount: 70000,
      );
      await setup.repository.save(outgoing);
      await setup.repository.save(incoming);
      final ordinary = FinancialSummary.calculate(
        transactions: [outgoing, incoming],
        referenceDate: DateTime(2026, 8, 20),
      );
      expect(ordinary.monthlyIncome, 70000);
      expect(ordinary.monthlyExpenses, 70000);

      final link = await setup.service.convertExisting(
        outgoingTransactionId: outgoing.id,
        incomingTransactionId: incoming.id,
        sourceAccountId: setup.cash.id,
        destinationAccountId: setup.bank.id,
        expectedOutgoingVersion: outgoing.version,
        expectedIncomingVersion: incoming.version,
        linkId: 'converted-link',
      );
      expect(link.outgoingTransactionId, 'import-out');
      expect(link.incomingTransactionId, 'import-in');
      expect(await setup.store.getTransactions(), hasLength(2));
      final paired = FinancialSummary.calculate(
        transactions: [outgoing, incoming],
        transferLinks: [link],
        referenceDate: DateTime(2026, 8, 20),
      );
      expect(paired.monthlyIncome, 0);
      expect(paired.monthlyExpenses, 0);

      await setup.service.unpair(
        linkId: link.id,
        expectedVersion: link.version,
      );
      final storedLinks = await setup.repository.getTransferLinks(
        includeDeleted: true,
      );
      expect(storedLinks.single.deletedAt, isNotNull);
      final rows = await setup.repository.getAll();
      expect(rows.map((row) => row.id).toSet(), {'import-out', 'import-in'});
      final unpaired = FinancialSummary.calculate(
        transactions: rows,
        transferLinks: storedLinks,
        referenceDate: DateTime(2026, 8, 20),
      );
      expect(unpaired.monthlyIncome, 70000);
      expect(unpaired.monthlyExpenses, 70000);

      await expectLater(
        setup.service.convertExisting(
          outgoingTransactionId: outgoing.id,
          incomingTransactionId: incoming.id,
          sourceAccountId: setup.cash.id,
          destinationAccountId: setup.bank.id,
          expectedOutgoingVersion: outgoing.version + 1,
          expectedIncomingVersion: incoming.version,
        ),
        throwsA(isA<InternalTransferValidationException>()),
      );
    },
  );

  test('delete atomically tombstones relation and both legs', () async {
    final setup = await _Setup.create('delete');
    addTearDown(setup.dispose);
    final created = await setup.createTransfer();
    await setup.service.delete(
      linkId: created.link.id,
      expectedLinkVersion: 1,
      expectedOutgoingVersion: 1,
      expectedIncomingVersion: 1,
    );
    final transactions = await setup.repository.getAll(includeDeleted: true);
    final links = await setup.repository.getTransferLinks(includeDeleted: true);
    expect(transactions, hasLength(2));
    expect(transactions.every((row) => row.deletedAt != null), isTrue);
    expect(links.single.deletedAt, isNotNull);
    expect(
      AccountBalanceCalculator.calculate(
        account: setup.cash,
        transactions: transactions,
      ),
      0,
    );
    expect(
      AccountBalanceCalculator.calculate(
        account: setup.bank,
        transactions: transactions,
      ),
      0,
    );
  });

  test('validator rejects invalid and duplicate active pairings', () {
    final validator = const InternalTransferIntegrityValidator();
    final cash = _account('cash', 'Cash');
    final bank = _account('bank', 'Bank');
    final outgoing = _transaction(
      id: 'out',
      type: TransactionType.expense,
      account: 'Cash',
    );
    final incoming = _transaction(
      id: 'in',
      type: TransactionType.income,
      account: 'Bank',
    );
    final valid = _link('link', outgoing.id, incoming.id, cash.id, bank.id);
    validator.validate(
      link: valid,
      outgoing: outgoing,
      incoming: incoming,
      sourceAccount: cash,
      destinationAccount: bank,
    );
    expect(
      () => validator.validate(
        link: _link('same-account', outgoing.id, incoming.id, cash.id, cash.id),
        outgoing: outgoing,
        incoming: incoming.copyWith(account: 'Cash'),
        sourceAccount: cash,
        destinationAccount: cash,
      ),
      throwsA(isA<InternalTransferValidationException>()),
    );
    expect(
      () => validator.validate(
        link: valid,
        outgoing: outgoing,
        incoming: incoming.copyWith(amount: 1),
        sourceAccount: cash,
        destinationAccount: bank,
      ),
      throwsA(isA<InternalTransferValidationException>()),
    );
    expect(
      () => validator.validate(
        link: _link('duplicate', outgoing.id, 'other-in', cash.id, bank.id),
        outgoing: outgoing,
        incoming: incoming.copyWith(id: 'other-in'),
        sourceAccount: cash,
        destinationAccount: bank,
        existingLinks: [valid],
      ),
      throwsA(isA<InternalTransferValidationException>()),
    );
    final usd = _account('usd', 'USD', currency: 'USD');
    expect(
      () => validator.validate(
        link: valid,
        outgoing: outgoing,
        incoming: incoming.copyWith(account: 'USD'),
        sourceAccount: cash,
        destinationAccount: usd,
      ),
      throwsA(isA<InternalTransferValidationException>()),
    );
  });

  test(
    'native atomic save rolls leg updates back when relation insert fails',
    () async {
      final setup = await _Setup.create('atomic');
      addTearDown(setup.dispose);
      final created = await setup.createTransfer();
      await expectLater(
        setup.store.saveInternalTransferAtomic(
          transactions: [
            created.outgoing.copyWith(title: 'must roll back').toRecord(),
          ],
          link: created.link.copyWith(id: 'duplicate-active-link').toRecord(),
        ),
        throwsA(anything),
      );
      final stored = (await setup.repository.getAll()).firstWhere(
        (row) => row.id == created.outgoing.id,
      );
      expect(stored.title, created.outgoing.title);
      expect(await setup.store.getTransferLinks(), hasLength(1));
    },
  );

  test(
    'remote invalid relation is rejected atomically on native and web',
    () async {
      final setup = await _Setup.create('remote');
      addTearDown(setup.dispose);
      final invalid = _link(
        'remote-link',
        'missing-out',
        'missing-in',
        setup.cash.id,
        setup.bank.id,
      ).toRecord();
      await expectLater(
        setup.store.applyRemoteSyncBatch(
          'book-1',
          changes: [
            {
              'entity_type': 'transfer_links',
              'entity_id': 'remote-link',
              'payload': invalid,
            },
          ],
          finalSequence: 1,
        ),
        throwsStateError,
      );
      expect(await setup.store.getTransferLinks(), isEmpty);

      final webStore = web.LocalStore(databasePath: 'beta08f0-remote-web');
      await webStore.initialize();
      await _prepareStore(webStore);
      await expectLater(
        webStore.applyRemoteSyncBatch(
          'book-1',
          changes: [
            {
              'entity_type': 'transfer_links',
              'entity_id': 'remote-link',
              'payload': invalid,
            },
          ],
          finalSequence: 1,
        ),
        throwsStateError,
      );
      expect(await webStore.getTransferLinks(), isEmpty);
    },
  );

  test(
    'backup v4, v3 compatibility, clone remap, and CSV preserve context',
    () async {
      final setup = await _Setup.create('portable');
      addTearDown(setup.dispose);
      final created = await setup.createTransfer();
      final snapshot = await setup.store.createHouseholdBackupSnapshot(
        'book-1',
      );
      final codec = PortableBackupCodec(databaseSchemaVersion: 23);
      final v4 = await codec.encode(snapshot: snapshot, password: 'secret');
      final decodedV4 = await codec.decode(v4.bytes, 'secret');
      expect(v4.manifest.formatVersion, 4);
      expect(decodedV4.snapshot['transactions'], hasLength(2));
      expect(decodedV4.snapshot['transfer_links'], hasLength(1));

      final v3 = await codec.encode(
        snapshot: snapshot,
        password: 'secret',
        formatVersion: 3,
      );
      final decodedV3 = await codec.decode(v3.bytes, 'secret');
      expect(decodedV3.snapshot['transactions'], hasLength(2));
      expect(decodedV3.snapshot['transfer_links'], isEmpty);

      final clone = HouseholdBackupIntegrity.prepareForRestore(
        snapshot,
        remapAsCopy: true,
      );
      final clonedLink = clone['transfer_links']!.single;
      final clonedTransactions = clone['transactions']!
          .map((row) => row['id'])
          .toSet();
      expect(clonedLink['id'], isNot(created.link.id));
      expect(
        clonedTransactions,
        contains(clonedLink['outgoing_transaction_id']),
      );
      expect(
        clonedTransactions,
        contains(clonedLink['incoming_transaction_id']),
      );

      final csv = const CsvExportService().create(
        snapshot,
        const CsvExportFilter(),
      );
      final files = {
        for (final file in ZipDecoder().decodeBytes(csv.bytes).files)
          file.name: file,
      };
      expect(files, contains('transfer_links.csv'));
      final transactionCsv = utf8.decode(
        files['transactions.csv']!.readBytes()!,
      );
      expect(transactionCsv, contains('transfer_link_id'));
      expect(transactionCsv, contains('outgoing'));
      expect(transactionCsv, contains('incoming'));
    },
  );

  test(
    'initial download reconstructs a complete pair without echo outbox',
    () async {
      final source = await _Setup.create('initial-source');
      addTearDown(source.dispose);
      final created = await source.createTransfer();
      final snapshot = await source.store.createHouseholdBackupSnapshot(
        'book-1',
      );
      final manifest = InitialSyncManifest(
        bookId: 'book-1',
        bookName: 'Transfer household',
        baseCurrencyCode: 'IDR',
        counts: {
          for (final entityType in initialSyncEntityOrder)
            entityType: (snapshot[entityType] ?? const []).length,
        },
        snapshotSequence: 41,
        memberRole: 'member',
        householdMemberId: 'member-1',
        remoteInitializationComplete: true,
      );

      final targetFixture = await _Fixture.create('initial-target');
      final target = native.LocalStore(databasePath: targetFixture.path);
      await target.initialize();
      addTearDown(() async {
        await target.close();
        await targetFixture.dispose();
      });
      final adapter = InitialSyncStoreAdapter(target);
      await adapter.startInitialization(
        bookId: 'book-1',
        direction: InitialSyncDirection.download,
        sessionId: 'pair-download',
        manifest: manifest,
      );
      for (final entityType in initialSyncEntityOrder) {
        final rows = (snapshot[entityType] ?? const [])
            .map(Map<String, Object?>.of)
            .toList();
        await adapter.stageDownloadBatch(
          'book-1',
          InitialSyncBatch(
            entityType: entityType,
            rows: rows,
            nextCursor: rows.isEmpty ? null : rows.last['id'] as String,
            complete: true,
          ),
        );
      }
      await adapter.activateDownload(
        bookId: 'book-1',
        manifest: manifest,
        authUserId: 'auth-member',
      );

      final transactions = await target.getTransactions(bookId: 'book-1');
      final links = await target.getTransferLinks(bookId: 'book-1');
      expect(transactions.map((row) => row['id']).toSet(), {
        created.outgoing.id,
        created.incoming.id,
      });
      expect(links.single['id'], created.link.id);
      expect(await target.getEligibleSyncOperations('book-1'), isEmpty);
    },
  );

  testWidgets(
    'Windows and Android layouts show one logical transfer with safe details',
    (tester) async {
      late _Setup setup;
      late CanonicalInternalTransfer created;
      late TransactionController controller;
      await tester.runAsync(() async {
        setup = await _Setup.create('ui');
        created = await setup.createTransfer();
        controller = TransactionController(
          create: CreateTransaction(setup.repository),
          update: UpdateTransaction(setup.repository),
          delete: DeleteTransaction(setup.repository),
          get: GetTransactions(setup.repository),
          duplicate: DuplicateTransaction(setup.repository),
          internalTransfers: setup.service,
        );
        await controller.load();
      });
      addTearDown(() => tester.runAsync(setup.dispose));

      for (final size in const [Size(1440, 900), Size(390, 844)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TransactionListScreen(
                controller: controller,
                initialDate: DateTime(2026, 8, 20),
                onEdit: (_) {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Canonical transfer'), findsOneWidget);
        expect(find.textContaining('Cash -> Bank'), findsOneWidget);
        expect(find.text(created.link.id), findsNothing);

        await tester.tap(find.text('Canonical transfer'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('INTERNAL TRANSFER / POSTED'), findsOneWidget);
        expect(find.text('From'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('To'), findsOneWidget);
        expect(find.text('Bank'), findsOneWidget);
        expect(find.text('Edit transfer'), findsOneWidget);
        expect(find.text('Unpair'), findsOneWidget);
        expect(find.text(created.link.id), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}

Transaction _transaction({
  required String id,
  required TransactionType type,
  required String account,
  int amount = 100000,
}) => Transaction(
  id: id,
  bookId: 'book-1',
  title: 'Transfer test',
  category: 'Transfer',
  account: account,
  date: DateTime(2026, 8, 20),
  amount: amount,
  type: type,
  createdAt: DateTime(2026, 8, 20),
  updatedAt: DateTime(2026, 8, 20),
  syncStatus: 'pending',
);

Account _account(String id, String name, {String currency = 'IDR'}) => Account(
  id: id,
  bookId: 'book-1',
  name: name,
  accountType: AccountType.bank,
  currencyCode: currency,
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
);

InternalTransferLink _link(
  String id,
  String outgoingId,
  String incomingId,
  String sourceId,
  String destinationId,
) => InternalTransferLink(
  id: id,
  bookId: 'book-1',
  outgoingTransactionId: outgoingId,
  incomingTransactionId: incomingId,
  sourceAccountId: sourceId,
  destinationAccountId: destinationId,
  currencyCode: 'IDR',
  amount: 100000,
  createdAt: DateTime(2026, 8, 20),
  updatedAt: DateTime(2026, 8, 20),
);

Future<void> _prepareStore(dynamic store) async {
  const timestamp = 1787184000000;
  await store.upsertFinancialBook({
    'id': 'book-1',
    'name': 'Transfer household',
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
  await store.upsertHouseholdMember({
    'id': 'member-1',
    'book_id': 'book-1',
    'display_name': 'Owner',
    'role': 'owner',
    'auth_user_id': null,
    'created_at': timestamp,
    'updated_at': timestamp,
    'deleted_at': null,
    'version': 1,
    'device_id': 'device-1',
    'sync_status': 'synced',
  }, enqueueSync: false);
  await store.upsertAccount(
    _account('cash', 'Cash').toRecord(),
    enqueueSync: false,
  );
  await store.upsertAccount(
    _account('bank', 'Bank').toRecord(),
    enqueueSync: false,
  );
}

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
    await _prepareStore(store);
    final repository = LocalTransactionRepository(store);
    final accounts = await repository.getAllAccounts();
    return _Setup(
      fixture,
      store,
      repository,
      InternalTransferService(repository),
      accounts.firstWhere((account) => account.id == 'cash'),
      accounts.firstWhere((account) => account.id == 'bank'),
    );
  }

  Future<CanonicalInternalTransfer> createTransfer() => service.create(
    bookId: 'book-1',
    enteredByMemberId: null,
    title: 'Canonical transfer',
    sourceAccountId: cash.id,
    destinationAccountId: bank.id,
    date: DateTime(2026, 8, 20),
    amount: 100000,
    outgoingTransactionId: 'outgoing',
    incomingTransactionId: 'incoming',
    linkId: 'link',
  );

  Future<void> dispose() async {
    await store.close();
    await fixture.dispose();
  }
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta08f0-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
