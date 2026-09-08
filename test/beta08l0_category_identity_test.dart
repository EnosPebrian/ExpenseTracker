import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/sync/domain/conflict_resolution_service.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_transport.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_import_rule.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_import_rule_engine.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/quick_add/quick_add_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/edit/transaction_form.dart';

import 'support/beta06_fixture.dart';

Map<String, List<Map<String, Object?>>> snapshot() {
  final data = HouseholdBackupIntegrity.prepareForRestore(beta06Snapshot());
  for (final row in data['transactions']!) {
    row['category_id'] = 'category-${row['transaction_type']}';
  }
  return data;
}

Transaction expense({String? categoryId = 'category-expense'}) => Transaction(
  id: 'new-expense',
  bookId: 'book-beta06',
  title: 'Lunch',
  category: 'Groceries',
  categoryId: categoryId,
  account: 'Cash',
  date: DateTime(2026, 8, 1),
  amount: 12000,
  type: TransactionType.expense,
);

void main() {
  test(
    'manual conflict merge cannot mix category snapshot and identity',
    () async {
      final backend = ConflictBackend();
      final service = ConflictResolutionService(
        repository: backend,
        transport: backend,
      );
      final conflict = SyncConflict(
        id: 'conflict',
        bookId: 'book-beta06',
        entityType: 'transactions',
        entityId: 'tx',
        operationId: 'op',
        baseVersion: 1,
        serverVersion: 2,
        createdAt: DateTime.utc(2026),
        localPayload: const {'category': 'Food', 'category_id': 'food'},
        serverPayload: const {'category': 'Dining', 'category_id': 'dining'},
      );
      await expectLater(
        service.resolve(
          conflict,
          ConflictResolutionType.manualMerge,
          mergedPayload: const {'category': 'Food', 'category_id': 'dining'},
        ),
        throwsStateError,
      );
      expect(backend.calls, 0);
      await service.resolve(
        conflict,
        ConflictResolutionType.manualMerge,
        mergedPayload: const {'category': 'Food', 'category_id': 'food'},
      );
      expect(backend.calls, 1);
    },
  );
  test('model preserves ID, snapshot and explicit null independently', () {
    final value = expense();
    final roundTrip = Transaction.fromRecord(value.toRecord());
    expect(roundTrip.categoryId, value.categoryId);
    expect(roundTrip.category, 'Groceries');
    expect(value.copyWith(title: 'Edited').categoryId, value.categoryId);
    expect(value.copyWith(categoryId: null).categoryId, isNull);
    expect(
      Transaction.fromRecord(
        {...value.toRecord()}..remove('category_id'),
      ).categoryId,
      isNull,
    );
  });

  test(
    'v25 migration preserves rows and uniquely backfills archived names only',
    () async {
      final directory = await Directory.systemTemp.createTemp('beta08l0-');
      final store = native.LocalStore(
        databasePath: '${directory.path}/test.db',
      );
      await store.initialize();
      await store.activateHouseholdBackupSnapshot(snapshot());
      await store.db.insert('categories', {
        ...snapshot()['categories']!.last,
        'id': 'collision',
        'name': ' groceries ',
      });
      await store.db.update(
        'categories',
        {'deleted_at': 123},
        where: 'id = ?',
        whereArgs: ['category-income'],
      );
      await store.upsertTransaction(
        expense(categoryId: null).copyWith(category: 'Missing').toRecord(),
      );
      final before = await store.getTransactions(includeDeleted: true);
      final pending = await store.getPendingSyncCount('book-beta06');
      await store.db.execute('DROP INDEX idx_transactions_category_id');
      await store.db.execute(
        'ALTER TABLE transactions DROP COLUMN category_id',
      );
      await store.db.execute('PRAGMA user_version = 25');
      await store.close();
      await store.initialize();
      expect(await store.getSchemaVersion(), 26);
      final rows = {
        for (final r in await store.getTransactions(includeDeleted: true))
          r['id']: r,
      };
      expect(rows.length, before.length);
      expect(rows['transaction-income']!['category_id'], 'category-income');
      expect(rows['transaction-expense']!['category_id'], isNull);
      expect(rows['new-expense']!['category_id'], isNull);
      for (final old in before) {
        expect(
          {...rows[old['id']]!}..remove('category_id'),
          {...old}..remove('category_id'),
        );
      }
      expect(await store.getPendingSyncCount('book-beta06'), pending);
      await store.close();
      await directory.delete(recursive: true);
    },
  );

  for (final platform in ['native', 'web']) {
    test(
      '$platform round-trip, rename, legacy pull and atomic foreign rejection',
      () async {
        final directory = await Directory.systemTemp.createTemp('beta08l0-');
        final dynamic store = platform == 'native'
            ? native.LocalStore(databasePath: '${directory.path}/test.db')
            : web.LocalStore();
        await store.initialize();
        await store.activateHouseholdBackupSnapshot(
          snapshot(),
          replaceBookId: 'book-beta06',
        );
        await store.upsertTransaction(expense().toRecord());
        await store.saveMasterName(
          'categories',
          'Fresh food',
          previousName: 'Groceries',
          categoryType: 'expense',
        );
        var rows =
            (await store.getTransactions()) as List<Map<String, Object?>>;
        expect(
          rows.firstWhere((r) => r['id'] == 'new-expense')['category'],
          'Groceries',
        );
        expect(
          rows.firstWhere((r) => r['id'] == 'new-expense')['category_id'],
          'category-expense',
        );
        final pending = await store.getPendingSyncCount('book-beta06');
        final legacy = expense().toRecord()..remove('category_id');
        Future<void> pull(Map<String, Object?> payload) =>
            store.applyRemoteSyncBatch(
                  'book-beta06',
                  changes: [
                    {
                      'entity_type': 'transactions',
                      'entity_id': 'new-expense',
                      'payload': payload,
                    },
                  ],
                  finalSequence: 12,
                )
                as Future<void>;
        await pull(legacy);
        rows = (await store.getTransactions()) as List<Map<String, Object?>>;
        expect(
          rows.firstWhere((r) => r['id'] == 'new-expense')['category_id'],
          'category-expense',
        );
        await pull({...legacy, 'category': 'Dining'});
        rows = (await store.getTransactions()) as List<Map<String, Object?>>;
        expect(
          rows.firstWhere((r) => r['id'] == 'new-expense')['category_id'],
          isNull,
        );
        expect(await store.getPendingSyncCount('book-beta06'), pending);
        final before = jsonEncode(rows);
        await expectLater(
          store.upsertTransaction(
            expense(categoryId: 'foreign-category').toRecord(),
          ),
          throwsStateError,
        );
        await expectLater(
          pull(expense(categoryId: 'foreign-category').toRecord()),
          throwsStateError,
        );
        expect(jsonEncode(await store.getTransactions()), before);
        await store.close();
        await directory.delete(recursive: true);
      },
    );
  }

  test('Quick Add selected category reaches persisted transaction', () async {
    final repo = MemoryTransactions();
    final transactions = TransactionController(
      create: CreateTransaction(repo),
      update: UpdateTransaction(repo),
      delete: DeleteTransaction(repo),
      get: GetTransactions(repo),
      duplicate: DuplicateTransaction(repo),
    );
    final controller = QuickAddController(
      transactions: transactions,
      config: QuickAddConfig(
        accounts: ['Cash'],
        expenseCategories: ['Groceries'],
        incomeCategories: ['Salary'],
        expenseCategoryIdsByName: {'Groceries': 'category-expense'},
        projects: [],
        assetDefinitions: [
          AssetDefinition(
            id: 'gold',
            displayName: 'Gold',
            kind: AssetKind.gold,
            currencyCode: 'IDR',
            unit: 'gram',
            lotSize: 1,
            symbol: null,
            providerCode: null,
            providerSymbol: null,
            exchangeCode: null,
            deletedAt: null,
            version: 1,
            deviceId: 'test',
            syncStatus: 'local',
            onlinePricingEnabled: false,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    controller.setAmountText('12000');
    expect(await controller.save(), isTrue);
    expect(repo.saved.single.categoryId, 'category-expense');
    expect(repo.saved.single.category, 'Groceries');
    controller.dispose();
    transactions.dispose();
  });

  testWidgets('editing category changes name and ID together', (tester) async {
    Transaction? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: expense(),
            options: const TransactionFormOptions(
              accounts: ['Cash'],
              expenseCategories: ['Groceries', 'Dining'],
              incomeCategories: ['Salary'],
              projects: [],
              expenseCategoryIdsByName: {
                'Groceries': 'category-expense',
                'Dining': 'category-dining',
              },
            ),
            onSubmit: (value) async => saved = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Groceries').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.category, 'Dining');
    expect(saved!.categoryId, 'category-dining');
  });

  for (final mode in ['resolved', 'unresolved', 'rule']) {
    test('source-neutral $mode import identity finalization', () async {
      final repo = MemoryTransactions();
      final account = Account(
        id: 'account-cash',
        bookId: 'book-beta06',
        name: 'Cash',
      );
      final controller = TransactionImportController(
        pickFile: () async => SelectedCsvFile(
          name: 'input.csv',
          bytes: utf8.encode(
            'date,description,amount,type,category\n2026-08-01,Market,12000,expense,${mode == 'rule' ? '' : 'Groceries'}',
          ),
        ),
        importBatch: ImportTransactionsBatch(repo),
        existingTransactions: () async => repo.saved,
        accounts: [account],
        expenseCategories: const ['Groceries'],
        incomeCategories: const ['Salary'],
        activeBookId: 'book-beta06',
        activeMemberId: 'member-owner',
        ruleCategories: () async => mode == 'unresolved'
            ? {}
            : const {
                'category-expense': ImportRuleCategory(
                  id: 'category-expense',
                  bookId: 'book-beta06',
                  name: 'Groceries',
                  type: TransactionType.expense,
                ),
              },
        importRules: () async => mode == 'rule'
            ? [
                TransactionImportRule(
                  bookId: 'book-beta06',
                  name: 'Market rule',
                  transactionType: TransactionImportRuleType.expense,
                  matchField: TransactionImportRuleMatchField.description,
                  operator: TransactionImportRuleOperator.equals,
                  pattern: 'Market',
                  categoryId: 'category-expense',
                ),
              ]
            : [],
      );
      controller.selectAccount(account);
      await controller.selectCsv();
      await controller.analyze();
      await controller.commit();
      expect(controller.error, isNull);
      expect(repo.saved.single.category, 'Groceries');
      expect(
        repo.saved.single.categoryId,
        mode == 'unresolved' ? isNull : 'category-expense',
      );
      controller.dispose();
    });
  }

  test(
    'v5 encrypted round-trip and clone remap preserve category identity',
    () async {
      final codec = PortableBackupCodec(databaseSchemaVersion: 26);
      final encoded = await codec.encode(
        snapshot: snapshot(),
        password: 'synthetic-test',
      );
      expect(encoded.manifest.formatVersion, 5);
      final decoded = await codec.decode(encoded.bytes, 'synthetic-test');
      expect(
        decoded.snapshot['transactions']!.last['category_id'],
        'category-expense',
      );
      final clone = HouseholdBackupIntegrity.prepareForRestore(
        decoded.snapshot,
        remapAsCopy: true,
      );
      final ids = clone['categories']!.map((row) => row['id']).toSet();
      for (final row in clone['transactions']!) {
        expect(ids, contains(row['category_id']));
        expect(row['category_id'], isNot(startsWith('category-')));
      }
      HouseholdBackupIntegrity.validate(clone);
    },
  );
  for (final version in [1, 2, 3, 4]) {
    test('backup v$version stays readable with null legacy identity', () async {
      final codec = PortableBackupCodec(databaseSchemaVersion: 25);
      final encoded = await codec.encode(
        snapshot: snapshot(),
        password: 'synthetic-test',
        formatVersion: version,
      );
      final decoded = await codec.decode(encoded.bytes, 'synthetic-test');
      expect(
        decoded.snapshot['transactions']!.every(
          (row) => row['category_id'] == null,
        ),
        isTrue,
      );
      expect(decoded.snapshot['transactions']!.last['category'], 'Groceries');
    });
  }
}

class MemoryTransactions
    implements TransactionRepository, TransactionBatchRepository {
  final saved = <Transaction>[];
  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async =>
      List.of(saved);
  @override
  Future<void> save(Transaction transaction) async => saved.add(transaction);
  @override
  Future<void> saveAllAtomic(List<Transaction> transactions) async =>
      saved.addAll(transactions);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ConflictBackend
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
