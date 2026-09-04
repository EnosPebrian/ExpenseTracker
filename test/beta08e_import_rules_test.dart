import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_recovery_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_recovery_service.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/sync/data/supabase_sync_transport.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_import_rule.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_import_rule_engine.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/import/transaction_import_rules_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('deterministic rule domain', () {
    test('normalization is conservative and deterministic', () {
      expect(
        normalizeImportRuleText('  PLN   Pascabayar!!  '),
        'pln pascabayar',
      );
      expect(normalizeImportRuleText('INV-42 / A'), 'inv-42 / a');
      expect(normalizeImportRuleText('TOKO.99'), 'toko.99');
    });

    test('rejects blank, punctuation-only, broad, and excessive patterns', () {
      for (final pattern in ['', '  ', '!!', 'a']) {
        expect(
          () => _rule('invalid-$pattern', pattern: pattern),
          throwsArgumentError,
        );
      }
      expect(
        () => _rule('too-long', pattern: List.filled(161, 'x').join()),
        throwsArgumentError,
      );
    });

    test('contains, equals, and starts-with are case insensitive', () {
      final categories = _categories();
      expect(
        _evaluate(
          _rule('contains', pattern: 'PERTAMINA'),
          categories,
          description: 'Pertamina Denpasar 42',
        ),
        'Fuel',
      );
      expect(
        _evaluate(
          _rule(
            'equals',
            pattern: 'PLN',
            operator: TransactionImportRuleOperator.equals,
          ),
          categories,
          description: '  pln ',
        ),
        'Fuel',
      );
      expect(
        _evaluate(
          _rule(
            'starts',
            pattern: 'SPOTIFY',
            operator: TransactionImportRuleOperator.startsWith,
          ),
          categories,
          description: 'spotify premium',
        ),
        'Fuel',
      );
    });

    test('all source-neutral match fields work', () {
      final categories = _categories();
      final rules = [
        _rule('description', pattern: 'fuel'),
        _rule(
          'reference',
          pattern: 'ref-42',
          field: TransactionImportRuleMatchField.reference,
          categoryId: 'category-shopping',
        ),
        _rule(
          'merchant',
          pattern: 'merchant',
          field: TransactionImportRuleMatchField.merchantHint,
        ),
        _rule(
          'either',
          pattern: 'combined',
          field: TransactionImportRuleMatchField.descriptionOrReference,
        ),
      ];
      expect(
        _match(
          rules[0],
          categories,
          description: 'fuel purchase',
        ).hasSuggestion,
        isTrue,
      );
      expect(
        _match(rules[1], categories, reference: 'REF-42').categoryName,
        'Shopping',
      );
      expect(
        _match(rules[2], categories, merchant: 'Merchant').hasSuggestion,
        isTrue,
      );
      expect(
        _match(rules[3], categories, reference: 'combined-1').hasSuggestion,
        isTrue,
      );
    });

    test('expense/income and account scope are strict', () {
      final categories = _categories();
      final income = _rule(
        'income',
        pattern: 'salary',
        type: TransactionImportRuleType.income,
        categoryId: 'category-income',
      );
      expect(
        _match(income, categories, description: 'salary').hasSuggestion,
        isFalse,
      );
      expect(
        _match(
          income,
          categories,
          description: 'salary',
          type: TransactionType.income,
        ).categoryName,
        'Salary',
      );
      final scoped = _rule('scoped', pattern: 'fee', accountId: 'account-2');
      expect(
        _match(scoped, categories, description: 'fee').hasSuggestion,
        isFalse,
      );
      expect(
        _match(
          scoped,
          categories,
          description: 'fee',
          accountId: 'account-2',
          activeAccounts: const {'account-1', 'account-2'},
        ).hasSuggestion,
        isTrue,
      );
    });

    test('disabled and deleted rules never match', () {
      final categories = _categories();
      expect(
        _match(
          _rule('disabled', pattern: 'fuel', enabled: false),
          categories,
          description: 'fuel',
        ).matchedRuleIds,
        isEmpty,
      );
      expect(
        _match(
          _rule('deleted', pattern: 'fuel', deletedAt: DateTime(2026, 8, 1)),
          categories,
          description: 'fuel',
        ).matchedRuleIds,
        isEmpty,
      );
    });

    test('higher priority wins and equal same-category ties are safe', () {
      final categories = _categories();
      final result = _matchAll(
        [
          _rule('low', pattern: 'shop', priority: 10),
          _rule('high-b', pattern: 'shop', priority: 100),
          _rule('high-a', pattern: 'shop', priority: 100),
        ],
        categories,
        description: 'shop',
      );
      expect(result.ambiguous, isFalse);
      expect(result.categoryName, 'Fuel');
      expect(result.winningRuleId, 'high-a');
    });

    test('equal-priority different-category ties are ambiguous', () {
      final result = _matchAll(
        [
          _rule('fuel', pattern: 'merchant', priority: 100),
          _rule(
            'shop',
            pattern: 'merchant',
            priority: 100,
            categoryId: 'category-shopping',
          ),
        ],
        _categories(),
        description: 'merchant',
      );
      expect(result.ambiguous, isTrue);
      expect(result.categoryId, isNull);
      expect(result.matchedRuleIds, ['fuel', 'shop']);
    });

    test('unavailable or foreign category never suggests', () {
      final unavailable = _categories()
        ..['category-fuel'] = const ImportRuleCategory(
          id: 'category-fuel',
          bookId: 'book-1',
          name: 'Fuel',
          type: TransactionType.expense,
          available: false,
        );
      expect(
        _match(
          _rule('rule', pattern: 'fuel'),
          unavailable,
          description: 'fuel',
        ).warnings,
        contains('The matching rule category is unavailable.'),
      );
      final foreign = _categories()
        ..['category-fuel'] = const ImportRuleCategory(
          id: 'category-fuel',
          bookId: 'book-2',
          name: 'Fuel',
          type: TransactionType.expense,
        );
      expect(
        _match(
          _rule('rule', pattern: 'fuel'),
          foreign,
          description: 'fuel',
        ).hasSuggestion,
        isFalse,
      );
    });
  });

  group('shared ingestion precedence', () {
    test(
      'rule applies to CSV, receipt merchant, and statement drafts',
      () async {
        final descriptionRule = _rule('description-rule', pattern: 'pertamina');
        final merchantRule = _rule(
          'merchant-rule',
          pattern: 'pertamina',
          field: TransactionImportRuleMatchField.merchantHint,
        );
        final csv = await _plan(
          description: 'PERTAMINA DENPASAR',
          rules: [descriptionRule],
        );
        final receipt = await _plan(
          description: 'Receipt purchase',
          merchant: 'Pertamina',
          rules: [merchantRule],
        );
        final statement = await _plan(
          description: 'PLN PERTAMINA',
          rules: [descriptionRule],
        );
        for (final draft in [csv, receipt, statement]) {
          expect(draft.category, 'Fuel');
          expect(draft.categorySource, TransactionImportCategorySource.rule);
        }
      },
    );

    test('explicit source category outranks matching rule', () async {
      final draft = await _plan(
        description: 'PERTAMINA',
        sourceCategory: 'Shopping',
        rules: [_rule('fuel', pattern: 'pertamina')],
      );
      expect(draft.category, 'Shopping');
      expect(draft.categorySource, TransactionImportCategorySource.source);
    });

    test(
      'rule suggestion never changes source fingerprint or stable ID',
      () async {
        final without = await _plan(description: 'PERTAMINA');
        final withRule = await _plan(
          description: 'PERTAMINA',
          rules: [_rule('fuel', pattern: 'pertamina')],
        );
        expect(withRule.transactionId, without.transactionId);
        expect(withRule.sourceRowFingerprint, without.sourceRowFingerprint);
      },
    );

    test(
      'manual category wins and clearing it restores rule suggestion',
      () async {
        final controller = TransactionImportController(
          pickFile: () async => null,
          importBatch: ImportTransactionsBatch(_NoopBatchRepository()),
          existingTransactions: () async => const [],
          accounts: [_account],
          expenseCategories: const ['Fuel', 'Shopping'],
          incomeCategories: const ['Salary'],
          activeBookId: 'book-1',
          activeMemberId: 'member-1',
          importRules: () async => [_rule('fuel', pattern: 'pertamina')],
          ruleCategories: () async => _categories(),
        );
        controller.loadPreparedSource(_source(description: 'PERTAMINA'));
        controller.selectAccount(_account);
        await controller.analyze();
        final id = controller.preview!.drafts.single.transactionId;
        controller.editDraft(id, category: 'Shopping');
        expect(controller.preview!.drafts.single.category, 'Shopping');
        expect(
          controller.preview!.drafts.single.categorySource,
          TransactionImportCategorySource.manual,
        );
        controller.editDraft(id, category: '');
        expect(controller.preview!.drafts.single.category, 'Fuel');
        expect(
          controller.preview!.drafts.single.categorySource,
          TransactionImportCategorySource.rule,
        );
        expect(controller.preview!.drafts.single.transactionId, id);
      },
    );
  });

  group('SQLite and web persistence', () {
    test(
      'fresh current schema CRUD is scoped, durable, unique, and tombstone-safe',
      () async {
        final fixture = await _Fixture.create('crud');
        addTearDown(fixture.dispose);
        var store = native.LocalStore(databasePath: fixture.path);
        await store.initialize();
        expect(native.LocalStore.schemaVersion, 25);
        final refs = await _prepareStore(store);
        await store.upsertTransactionImportRule(
          _ruleRecord('rule-1', refs.expenseCategoryId, refs.accountId),
        );
        await expectLater(
          store.upsertTransactionImportRule(
            _ruleRecord(
              'rule-duplicate',
              refs.expenseCategoryId,
              refs.accountId,
            ),
          ),
          throwsStateError,
        );
        await store.close();
        store = native.LocalStore(databasePath: fixture.path);
        await store.initialize();
        addTearDown(store.close);
        expect(
          await store.getTransactionImportRules(bookId: 'book-1'),
          hasLength(1),
        );
        await store.softDeleteTransactionImportRule('rule-1', 1785628800000);
        final restored = await store.upsertTransactionImportRule(
          _ruleRecord('new-id', refs.expenseCategoryId, refs.accountId),
        );
        expect(restored['id'], 'rule-1');
        expect(restored['deleted_at'], isNull);
        expect(
          await store.getTransactionImportRules(bookId: 'foreign'),
          isEmpty,
        );
      },
    );

    test(
      'rule mutation and outbox are atomic; remote apply does not echo',
      () async {
        final fixture = await _Fixture.create('outbox');
        addTearDown(fixture.dispose);
        final store = native.LocalStore(databasePath: fixture.path);
        await store.initialize();
        addTearDown(store.close);
        final refs = await _prepareStore(store);
        final before = await store.getEligibleSyncOperations('book-1');
        await store.upsertTransactionImportRule(
          _ruleRecord('local-rule', refs.expenseCategoryId, refs.accountId),
        );
        final afterLocal = await store.getEligibleSyncOperations('book-1');
        expect(afterLocal.length, before.length + 1);
        expect(afterLocal.last['entity_type'], 'transaction_import_rules');
        await store.applyRemoteSyncBatch(
          'book-1',
          changes: [
            {
              'entity_type': 'transaction_import_rules',
              'entity_id': 'remote-rule',
              'payload': _ruleRecord(
                'remote-rule',
                refs.incomeCategoryId,
                null,
                type: 'income',
                pattern: 'salary',
              ),
            },
          ],
          finalSequence: 8,
        );
        expect(
          (await store.getEligibleSyncOperations('book-1')).length,
          afterLocal.length,
        );
        expect(
          await store.getTransactionImportRules(bookId: 'book-1'),
          hasLength(2),
        );
      },
    );

    test('cross-household account/category references are rejected', () async {
      final fixture = await _Fixture.create('references');
      addTearDown(fixture.dispose);
      final store = native.LocalStore(databasePath: fixture.path);
      await store.initialize();
      addTearDown(store.close);
      final refs = await _prepareStore(store);
      await expectLater(
        store.upsertTransactionImportRule(
          _ruleRecord('bad-category', 'missing-category', refs.accountId),
        ),
        throwsStateError,
      );
      await expectLater(
        store.upsertTransactionImportRule(
          _ruleRecord('bad-account', refs.expenseCategoryId, 'missing-account'),
        ),
        throwsStateError,
      );
      expect(await store.getTransactionImportRules(bookId: 'book-1'), isEmpty);
    });

    test(
      'v21 to current migration preserves existing household rows',
      () async {
        final fixture = await _Fixture.create('migration');
        addTearDown(fixture.dispose);
        var store = native.LocalStore(databasePath: fixture.path);
        await store.initialize();
        await _prepareStore(store);
        await store.db.execute('DROP TABLE transaction_import_rules');
        await store.db.execute('PRAGMA user_version = 21');
        await store.close();
        store = native.LocalStore(databasePath: fixture.path);
        await store.initialize();
        addTearDown(store.close);
        expect((await store.getFinancialBooks()).single['id'], 'book-1');
        expect(await store.getCategoryRecords(bookId: 'book-1'), hasLength(2));
        expect(
          await store.getTransactionImportRules(bookId: 'book-1'),
          isEmpty,
        );
        final version = await store.db.rawQuery('PRAGMA user_version');
        expect(version.single['user_version'], 25);
      },
    );

    test('web store has equivalent validation and uniqueness', () async {
      final store = web.LocalStore(databasePath: 'beta08e-web');
      await store.initialize();
      final refs = await _prepareStore(store);
      await store.upsertTransactionImportRule(
        _ruleRecord('web-rule', refs.expenseCategoryId, refs.accountId),
      );
      await expectLater(
        store.upsertTransactionImportRule(
          _ruleRecord('web-duplicate', refs.expenseCategoryId, refs.accountId),
        ),
        throwsStateError,
      );
      expect(
        await store.getTransactionImportRules(bookId: 'book-1'),
        hasLength(1),
      );
    });
  });

  test(
    'sync transport maps rule enabled state between SQLite and Supabase',
    () {
      final remote = SupabaseSyncTransport.toRemotePayload(
        'transaction_import_rules',
        {
          ..._ruleRecord('rule-sync', 'category-fuel', 'account-1'),
          'enabled': 1,
        },
      );
      expect(remote['enabled'], isTrue);
      final local = SupabaseSyncTransport.toLocalPayload(
        'transaction_import_rules',
        {...remote, 'enabled': false},
      );
      expect(local['enabled'], 0);
      expect(local['sync_status'], 'synced');
    },
  );

  test(
    'selective recovery treats a safe missing v3 rule as recoverable',
    () async {
      final snapshot = _backupSnapshot();
      final local = {
        for (final entry in snapshot.entries)
          entry.key: entry.key == 'transaction_import_rules'
              ? <Map<String, Object?>>[]
              : entry.value.map(Map<String, Object?>.of).toList(),
      };
      final store = _RecoveryStore(local);
      final backup = DecodedBackup(
        manifest: PortableBackupManifest(
          formatVersion: 3,
          applicationVersion: 'test',
          databaseSchemaVersion: 22,
          exportedAt: DateTime.utc(2026, 8, 19),
          bookId: 'book-1',
          bookName: 'Rules',
          baseCurrencyCode: 'IDR',
          entityCounts: {
            for (final entry in snapshot.entries) entry.key: entry.value.length,
          },
          contentChecksum: 'test',
          encryptionMetadata: const {},
          financialSummary: const {},
          deletedStateCounts: const {},
        ),
        snapshot: snapshot,
      );
      final service = BackupRecoveryService(store: store);
      final preview = await service.analyze(
        backup: backup,
        activeBookId: 'book-1',
      );
      final rule = preview.candidates.singleWhere(
        (candidate) => candidate.entityType == 'transaction_import_rules',
      );
      expect(rule.classification, BackupRecoveryClassification.missing);
      await service.recover(preview: preview, selectedKeys: {rule.key});
      expect(store.committed['transaction_import_rules'], hasLength(1));
    },
  );

  test(
    'backup v3 includes rules while v1/v2 decode with an empty rule set',
    () async {
      final codec = PortableBackupCodec(databaseSchemaVersion: 22);
      final snapshot = _backupSnapshot();
      final v3 = await codec.encode(
        snapshot: snapshot,
        password: 'strong-password',
      );
      expect(v3.manifest.formatVersion, portableBackupFormatVersion);
      expect(v3.manifest.entityCounts['transaction_import_rules'], 1);
      expect(
        (await codec.decode(
          v3.bytes,
          'strong-password',
        )).snapshot['transaction_import_rules'],
        hasLength(1),
      );
      for (final version in [1, 2]) {
        final old = await codec.encode(
          snapshot: snapshot,
          password: 'strong-password',
          formatVersion: version,
        );
        expect(
          (await codec.decode(
            old.bytes,
            'strong-password',
          )).snapshot['transaction_import_rules'],
          isEmpty,
        );
      }
    },
  );

  testWidgets(
    'rule manager has responsive empty state, tester, and confirmation editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: TransactionImportRulesScreen(
            bookId: 'book-1',
            accounts: [
              Account(
                id: 'account-1',
                bookId: 'book-1',
                name: 'Bank',
                accountType: AccountType.bank,
              ),
            ],
            initialRules: const [],
            initialCategories: _categories(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('No import rules yet.'), findsOneWidget);
      expect(find.text('Test rules'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('New rule'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Create import rule'), findsOneWidget);
      expect(find.text('Suggested category'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test('500 rules across 5000 drafts remains practical and deterministic', () {
    final rules = List.generate(
      500,
      (index) =>
          _rule('rule-$index', pattern: 'merchant-$index', priority: index),
    );
    const engine = TransactionImportRuleEngine();
    final categories = _categories();
    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < 5000; index++) {
      final result = engine.evaluate(
        input: TransactionImportRuleInput(
          bookId: 'book-1',
          type: TransactionType.expense,
          accountId: 'account-1',
          description: 'merchant-${index % 500}',
        ),
        rules: rules,
        categories: categories,
        activeAccountIds: const {'account-1'},
      );
      expect(result.hasSuggestion, isTrue);
    }
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 45)));
  });
}

final _account = Account(
  id: 'account-1',
  bookId: 'book-1',
  name: 'Bank',
  accountType: AccountType.bank,
);

TransactionImportRule _rule(
  String id, {
  String pattern = 'merchant',
  TransactionImportRuleType type = TransactionImportRuleType.expense,
  TransactionImportRuleMatchField field =
      TransactionImportRuleMatchField.description,
  TransactionImportRuleOperator operator =
      TransactionImportRuleOperator.contains,
  String categoryId = 'category-fuel',
  String? accountId,
  int priority = 100,
  bool enabled = true,
  DateTime? deletedAt,
}) => TransactionImportRule(
  id: id,
  bookId: 'book-1',
  name: id,
  enabled: enabled,
  priority: priority,
  transactionType: type,
  matchField: field,
  operator: operator,
  pattern: pattern,
  accountId: accountId,
  categoryId: categoryId,
  deletedAt: deletedAt,
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
);

Map<String, ImportRuleCategory> _categories() => {
  'category-fuel': const ImportRuleCategory(
    id: 'category-fuel',
    bookId: 'book-1',
    name: 'Fuel',
    type: TransactionType.expense,
  ),
  'category-shopping': const ImportRuleCategory(
    id: 'category-shopping',
    bookId: 'book-1',
    name: 'Shopping',
    type: TransactionType.expense,
  ),
  'category-income': const ImportRuleCategory(
    id: 'category-income',
    bookId: 'book-1',
    name: 'Salary',
    type: TransactionType.income,
  ),
};

TransactionImportRuleMatch _match(
  TransactionImportRule rule,
  Map<String, ImportRuleCategory> categories, {
  String description = '',
  String reference = '',
  String merchant = '',
  TransactionType type = TransactionType.expense,
  String accountId = 'account-1',
  Set<String> activeAccounts = const {'account-1'},
}) => _matchAll(
  [rule],
  categories,
  description: description,
  reference: reference,
  merchant: merchant,
  type: type,
  accountId: accountId,
  activeAccounts: activeAccounts,
);

TransactionImportRuleMatch _matchAll(
  List<TransactionImportRule> rules,
  Map<String, ImportRuleCategory> categories, {
  String description = '',
  String reference = '',
  String merchant = '',
  TransactionType type = TransactionType.expense,
  String accountId = 'account-1',
  Set<String> activeAccounts = const {'account-1'},
}) => const TransactionImportRuleEngine().evaluate(
  input: TransactionImportRuleInput(
    bookId: 'book-1',
    type: type,
    accountId: accountId,
    description: description,
    reference: reference,
    merchantHint: merchant,
  ),
  rules: rules,
  categories: categories,
  activeAccountIds: activeAccounts,
);

String? _evaluate(
  TransactionImportRule rule,
  Map<String, ImportRuleCategory> categories, {
  String description = '',
}) => _match(rule, categories, description: description).categoryName;

CsvParsedSource _source({
  required String description,
  String merchant = '',
  String category = '',
}) => CsvParsedSource(
  fileName: 'source.csv',
  fileFingerprint: 'source-fingerprint',
  delimiter: ',',
  headers: const [
    'date',
    'description',
    'amount',
    'type',
    'category',
    'reference',
    'note',
  ],
  rows: [
    CsvSourceRow(
      rowNumber: 2,
      identityKey: 'source-row-1',
      merchantHint: merchant,
      values: [
        '2026-08-19',
        description,
        '1000',
        'expense',
        category,
        'REF-1',
        '',
      ],
    ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

Future<TransactionImportDraft> _plan({
  required String description,
  String merchant = '',
  String sourceCategory = '',
  List<TransactionImportRule> rules = const [],
}) async => (await const TransactionImportPlanner().build(
  source: _source(
    description: description,
    merchant: merchant,
    category: sourceCategory,
  ),
  mapping: const TransactionImportMapping(
    dateColumn: 0,
    descriptionColumn: 1,
    amountColumn: 2,
    typeColumn: 3,
    categoryColumn: 4,
    referenceColumn: 5,
    noteColumn: 6,
  ),
  account: _account,
  activeBookId: 'book-1',
  existingTransactions: const [],
  expenseCategories: const ['Fuel', 'Shopping'],
  incomeCategories: const ['Salary'],
  importRules: rules,
  ruleCategories: _categories(),
  activeAccountIds: const {'account-1'},
)).drafts.single;

class _Refs {
  const _Refs(this.expenseCategoryId, this.incomeCategoryId, this.accountId);
  final String expenseCategoryId;
  final String incomeCategoryId;
  final String accountId;
}

Future<_Refs> _prepareStore(dynamic store) async {
  const timestamp = 1785542400000;
  await store.upsertFinancialBook({
    'id': 'book-1',
    'name': 'Rule household',
    'base_currency_code': 'IDR',
    'created_at': timestamp,
    'updated_at': timestamp,
    'deleted_at': null,
    'version': 1,
    'device_id': 'device-1',
    'sync_status': 'synced',
    'remote_linked_at': timestamp,
  });
  store.setActiveBookId('book-1');
  await store.saveMasterName('categories', 'Fuel', categoryType: 'expense');
  await store.saveMasterName('categories', 'Salary', categoryType: 'income');
  await store.saveMasterName('accounts', 'Bank');
  final expense = await store.getCategoryRecords(categoryType: 'expense');
  final income = await store.getCategoryRecords(categoryType: 'income');
  final accounts = await store.getAccounts();
  return _Refs(
    expense.single['id'] as String,
    income.single['id'] as String,
    accounts.single['id'] as String,
  );
}

Map<String, Object?> _ruleRecord(
  String id,
  String categoryId,
  String? accountId, {
  String type = 'expense',
  String pattern = 'pertamina',
}) => {
  'id': id,
  'book_id': 'book-1',
  'name': id,
  'enabled': 1,
  'priority': 100,
  'transaction_type': type,
  'match_field': 'description',
  'match_operator': 'contains',
  'pattern': pattern,
  'pattern_key': normalizeImportRuleText(pattern),
  'account_id': accountId,
  'category_id': categoryId,
  'created_at': 1785542400000,
  'updated_at': 1785542400000,
  'deleted_at': null,
  'version': 1,
  'device_id': 'device-1',
  'sync_status': 'pending',
};

Map<String, List<Map<String, Object?>>> _backupSnapshot() => {
  for (final key in portableBackupEntityKeys) key: <Map<String, Object?>>[],
  'household': [
    {
      'id': 'book-1',
      'name': 'Rule household',
      'base_currency_code': 'IDR',
      'created_at': 1785542400000,
      'updated_at': 1785542400000,
      'deleted_at': null,
      'version': 1,
      'device_id': 'device-1',
    },
  ],
  'accounts': [
    {
      'id': 'account-1',
      'book_id': 'book-1',
      'name': 'Bank',
      'account_type': 'asset',
      'currency_code': 'IDR',
      'opening_balance': 0,
      'opening_balance_date': null,
      'created_at': 1785542400000,
      'updated_at': 1785542400000,
      'deleted_at': null,
      'version': 1,
      'device_id': 'device-1',
    },
  ],
  'members': [
    {
      'id': 'member-1',
      'book_id': 'book-1',
      'name': 'Owner',
      'role': 'owner',
      'is_active_device': 1,
      'created_at': 1785542400000,
      'updated_at': 1785542400000,
      'deleted_at': null,
      'version': 1,
      'device_id': 'device-1',
    },
  ],
  'categories': [
    {
      'id': 'category-fuel',
      'book_id': 'book-1',
      'name': 'Fuel',
      'category_type': 'expense',
      'created_at': 1785542400000,
      'updated_at': 1785542400000,
      'deleted_at': null,
      'version': 1,
      'device_id': 'device-1',
    },
  ],
  'transaction_import_rules': [
    _ruleRecord('rule-backup', 'category-fuel', 'account-1'),
  ],
};

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;

  static Future<_Fixture> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('beta08e-$name-');
    return _Fixture(directory, p.join(directory.path, 'tracker.db'));
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _NoopBatchRepository implements TransactionBatchRepository {
  @override
  Future<void> saveAllAtomic(List<Transaction> transactions) async {}
}

class _RecoveryStore implements BackupRecoveryStore {
  _RecoveryStore(this.snapshot);

  final Map<String, List<Map<String, Object?>>> snapshot;
  Map<String, List<Map<String, Object?>>> committed = const {};

  @override
  Future<int> commitRecovery(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) async {
    committed = records;
    return 0;
  }

  @override
  Future<BackupRecoveryCloudState> recoveryCloudState(String bookId) async =>
      const BackupRecoveryCloudState(linked: false, ready: true);

  @override
  Future<Map<String, List<Map<String, Object?>>>> recoverySnapshot(
    String bookId,
  ) async => snapshot;
}
