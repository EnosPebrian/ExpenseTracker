import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_category_review.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_import_rule_engine.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/import/transaction_import_category_resolution.dart';

void main() {
  test('known CSV category maps to the canonical existing name', () async {
    final preview = await const TransactionImportPlanner().build(
      source: _source(['Groceries', '  groceries  ', 'GROCERIES', 'Grocery']),
      mapping: _mapping,
      account: _account,
      activeBookId: _bookId,
      existingTransactions: const [],
      expenseCategories: const ['Groceries'],
      incomeCategories: const ['Salary'],
      ruleCategories: _categories,
    );

    for (final draft in preview.drafts.take(3)) {
      expect(draft.category, 'Groceries');
      expect(draft.categorySource, TransactionImportCategorySource.source);
      expect(draft.requiresCategoryResolution, isFalse);
      expect(draft.issues.where((issue) => issue.blocking), isEmpty);
    }
    expect(preview.drafts.last.category, 'Grocery');
    expect(preview.drafts.last.requiresCategoryResolution, isTrue);
  });

  test('unknown CSV category remains reviewable but blocks commit', () async {
    final repository = _MemoryBatchRepository();
    final controller = await _analyzedController(
      repository: repository,
      categories: const ['Groceries', 'Dining Out'],
    );
    addTearDown(controller.dispose);

    final unknown = controller.preview!.drafts.last;
    expect(unknown.category, 'Dining Out');
    expect(unknown.requiresCategoryResolution, isTrue);
    expect(unknown.issues.any((issue) => issue.blocking), isTrue);
    expect(controller.preview!.readyCount, 1);

    await controller.commit();
    expect(repository.saved, isEmpty);
    expect(
      controller.error,
      'Resolve every unknown CSV category before importing.',
    );
  });

  test(
    'legacy exact category commits without import-rule category metadata',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = await _analyzedController(
        repository: repository,
        categories: const ['Groceries'],
        ruleCategories: const {},
      );
      addTearDown(controller.dispose);

      expect(
        controller.preview!.drafts.single.categoryResolution,
        TransactionImportCategoryResolution.mapToExisting,
      );
      expect(
        controller.preview!.drafts.single.categorySource,
        TransactionImportCategorySource.source,
      );
      await controller.commit();

      expect(controller.error, isNull);
      expect(repository.saved.single.category, 'Groceries');
      expect(repository.saved.single.categoryId, isNull);
    },
  );

  test(
    'mapping unknown category to existing resolves stable identity',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = await _analyzedController(
        repository: repository,
        categories: const ['Dining Out'],
      );
      addTearDown(controller.dispose);
      final id = controller.preview!.drafts.single.transactionId;

      controller.editDraft(id, category: 'Groceries');
      final resolved = controller.preview!.drafts.single;
      expect(resolved.requiresCategoryResolution, isFalse);
      expect(resolved.categorySource, TransactionImportCategorySource.manual);

      await controller.commit();
      expect(controller.error, isNull);
      expect(repository.saved.single.category, 'Groceries');
      expect(repository.saved.single.categoryId, 'category-groceries');
    },
  );

  test('manual row category commits without source-mapping metadata', () async {
    final repository = _MemoryBatchRepository();
    final controller = await _analyzedController(
      repository: repository,
      categories: const ['Dining Out'],
      ruleCategories: const {},
    );
    addTearDown(controller.dispose);
    final id = controller.preview!.drafts.single.transactionId;

    controller.editDraft(id, category: 'Groceries');
    await controller.commit();

    expect(controller.error, isNull);
    expect(repository.saved.single.category, 'Groceries');
    expect(repository.saved.single.categoryId, isNull);
  });

  test('explicit mapped category is revalidated by stable identity', () async {
    final repository = _MemoryBatchRepository();
    var categories = Map<String, ImportRuleCategory>.of(_categories);
    final controller = TransactionImportController(
      pickFile: () async => null,
      importBatch: ImportTransactionsBatch(repository),
      existingTransactions: () async => repository.saved,
      accounts: [_account],
      expenseCategories: const ['Groceries'],
      incomeCategories: const ['Salary'],
      activeBookId: _bookId,
      activeMemberId: 'member-1',
      ruleCategories: () async => categories,
    );
    addTearDown(controller.dispose);
    controller.loadPreparedSource(_source(const ['Dining Out']));
    controller.selectAccount(_account);
    await controller.analyze();
    final id = controller.preview!.drafts.single.transactionId;
    controller.mapCategory(id, 'Groceries');

    categories = const {};
    await controller.commit();

    expect(repository.saved, isEmpty);
    expect(
      controller.error,
      'A mapped category changed or is unavailable. Review it again.',
    );
  });

  test(
    'mapping one repeated source category maps every matching row',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = await _analyzedController(
        repository: repository,
        categories: const ['Transport', ' transport ', 'TRANSPORT'],
      );
      addTearDown(controller.dispose);

      controller.mapCategory(
        controller.preview!.drafts.first.transactionId,
        'Groceries',
      );

      expect(
        controller.preview!.drafts.map((draft) => draft.category).toSet(),
        {'Groceries'},
      );
      expect(controller.hasUnresolvedCategoryResolutions, isFalse);
    },
  );

  test(
    'ignoring unknown category is explicit and commits uncategorized',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = await _analyzedController(
        repository: repository,
        categories: const ['Dining Out'],
      );
      addTearDown(controller.dispose);
      final id = controller.preview!.drafts.single.transactionId;

      controller.ignoreCategory(id);
      final ignored = controller.preview!.drafts.single;
      expect(ignored.category, isEmpty);
      expect(ignored.categoryExplicitlyIgnored, isTrue);
      expect(ignored.requiresCategoryResolution, isFalse);

      await controller.commit();
      expect(controller.error, isNull);
      expect(repository.saved.single.category, isEmpty);
      expect(repository.saved.single.categoryId, isNull);
    },
  );

  test(
    'creating category is deferred and committed atomically with the row',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = await _analyzedController(
        repository: repository,
        categories: const ['Dining Out'],
      );
      addTearDown(controller.dispose);
      final id = controller.preview!.drafts.single.transactionId;

      expect(await controller.createCategoryForDraft(id, 'Dining Out'), isTrue);
      expect(repository.createdCategories, isEmpty);
      expect(
        controller.preview!.drafts.single.requiresCategoryResolution,
        false,
      );
      expect(controller.expenseCategories, isNot(contains('Dining Out')));

      await controller.commit();
      expect(repository.createdCategories.single.name, 'Dining Out');
      expect(repository.saved.single.category, 'Dining Out');
      expect(
        repository.saved.single.categoryId,
        repository.createdCategories.single.id,
      );
    },
  );

  test('repeated normalized source rows share one create intent', () async {
    final repository = _MemoryBatchRepository();
    final controller = await _analyzedController(
      repository: repository,
      categories: const ['Transport', ' transport ', 'TRANSPORT'],
    );
    addTearDown(controller.dispose);
    final originalIds = controller.preview!.drafts
        .map((draft) => draft.transactionId)
        .toList();

    await controller.createCategoryForDraft(
      controller.preview!.drafts.first.transactionId,
      'Transport',
    );

    final drafts = controller.preview!.drafts;
    expect(drafts.map((draft) => draft.transactionId), originalIds);
    expect(drafts.map((draft) => draft.categoryResolution).toSet(), {
      TransactionImportCategoryResolution.createCategory,
    });
    expect(
      drafts.map((draft) => draft.plannedCategoryId).toSet(),
      hasLength(1),
    );

    await controller.commit();
    expect(repository.createdCategories, hasLength(1));
    expect(repository.saved, hasLength(3));
  });

  test('manual row override wins over later source-category mapping', () async {
    final repository = _MemoryBatchRepository();
    final categories = {
      ..._categories,
      'category-business': const ImportRuleCategory(
        id: 'category-business',
        bookId: _bookId,
        name: 'Business',
        type: TransactionType.expense,
      ),
    };
    final controller = await _analyzedController(
      repository: repository,
      categories: const ['Transport', ' transport '],
      ruleCategories: categories,
      expenseCategories: const ['Groceries', 'Business'],
    );
    addTearDown(controller.dispose);
    final first = controller.preview!.drafts.first;
    final second = controller.preview!.drafts.last;

    controller.editDraft(first.transactionId, category: 'Business');
    controller.mapCategory(second.transactionId, 'Groceries');

    expect(controller.preview!.drafts.first.category, 'Business');
    expect(controller.preview!.drafts.last.category, 'Groceries');
  });

  test(
    'map create and ignore preserve deterministic transaction identity',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = await _analyzedController(
        repository: repository,
        categories: const ['Map', 'Create', 'Ignore'],
      );
      addTearDown(controller.dispose);
      final original = {
        for (final draft in controller.preview!.drafts)
          draft.sourceCategory: draft.transactionId,
      };

      controller.mapCategory(original['Map']!, 'Groceries');
      await controller.createCategoryForDraft(original['Create']!, 'Created');
      controller.ignoreCategory(original['Ignore']!);

      expect({
        for (final draft in controller.preview!.drafts)
          draft.sourceCategory: draft.transactionId,
      }, original);
    },
  );

  test(
    'five thousand repeated rows resolve in one bounded bulk pass',
    () async {
      final repository = _MemoryBatchRepository();
      final controller = TransactionImportController(
        pickFile: () async => null,
        importBatch: ImportTransactionsBatch(repository),
        existingTransactions: () async => const [],
        accounts: [_account],
        expenseCategories: const ['Groceries'],
        incomeCategories: const ['Salary'],
        activeBookId: _bookId,
        activeMemberId: 'member-1',
        ruleCategories: () async => _categories,
      );
      addTearDown(controller.dispose);
      controller.loadPreparedSource(_largeSource(5000));
      controller.selectAccount(_account);
      final watch = Stopwatch()..start();
      await controller.analyze();
      await controller.createCategoryForDraft(
        controller.preview!.drafts.first.transactionId,
        'Transport',
      );
      watch.stop();

      expect(controller.preview!.drafts, hasLength(5000));
      expect(
        controller.preview!.drafts
            .map((draft) => draft.plannedCategoryId)
            .toSet(),
        hasLength(1),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
    },
  );

  test('unrelated edits cannot bypass unresolved category safety', () async {
    final repository = _MemoryBatchRepository();
    final controller = await _analyzedController(
      repository: repository,
      categories: const ['Dining Out'],
    );
    addTearDown(controller.dispose);
    final draft = controller.preview!.drafts.single;

    controller.editDraft(draft.transactionId, description: 'Edited purchase');
    final edited = controller.preview!.drafts.single;
    expect(edited.category, 'Dining Out');
    expect(edited.requiresCategoryResolution, isTrue);
    expect(edited.issues.any((issue) => issue.blocking), isTrue);
  });

  testWidgets('review widget shows all three explicit resolutions', (
    tester,
  ) async {
    var ignored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionImportCategoryResolutionPanel(
            sourceCategory: 'Dining Out',
            transactionType: TransactionType.expense,
            existingCategories: const ['Groceries'],
            canCreate: true,
            onMap: (_) {},
            onCreate: (_) async => true,
            onIgnore: () => ignored = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unknown CSV category: “Dining Out”'), findsOneWidget);
    expect(find.text('Map to existing'), findsOneWidget);
    expect(find.text('Create category'), findsOneWidget);
    expect(find.text('Ignore category'), findsOneWidget);
    await tester.tap(find.text('Ignore category'));
    expect(ignored, isTrue);
  });
}

const _bookId = 'book-1';
final _account = Account(
  id: 'account-1',
  bookId: _bookId,
  name: 'Bank',
  accountType: AccountType.bank,
);
const _mapping = TransactionImportMapping(
  dateColumn: 0,
  descriptionColumn: 1,
  amountColumn: 2,
  typeColumn: 3,
  categoryColumn: 4,
);
const _categories = {
  'category-groceries': ImportRuleCategory(
    id: 'category-groceries',
    bookId: _bookId,
    name: 'Groceries',
    type: TransactionType.expense,
  ),
};

CsvParsedSource _source(List<String> categories) => CsvParsedSource(
  fileName: 'categories.csv',
  fileFingerprint: 'category-source',
  delimiter: ',',
  headers: const ['date', 'description', 'amount', 'type', 'category'],
  rows: [
    for (var index = 0; index < categories.length; index += 1)
      CsvSourceRow(
        rowNumber: index + 2,
        identityKey: 'row-${index + 1}',
        values: [
          '2026-09-${(index + 1).toString().padLeft(2, '0')}',
          'Purchase ${index + 1}',
          '1000',
          'expense',
          categories[index],
        ],
      ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

Future<TransactionImportController> _analyzedController({
  required _MemoryBatchRepository repository,
  required List<String> categories,
  Map<String, ImportRuleCategory> ruleCategories = _categories,
  List<String> expenseCategories = const ['Groceries'],
}) async {
  final controller = TransactionImportController(
    pickFile: () async => null,
    importBatch: ImportTransactionsBatch(repository),
    existingTransactions: () async => repository.saved,
    accounts: [_account],
    expenseCategories: expenseCategories,
    incomeCategories: const ['Salary'],
    activeBookId: _bookId,
    activeMemberId: 'member-1',
    ruleCategories: () async => ruleCategories,
  );
  controller.loadPreparedSource(_source(categories));
  controller.selectAccount(_account);
  await controller.analyze();
  return controller;
}

CsvParsedSource _largeSource(int count) => CsvParsedSource(
  fileName: 'large.csv',
  fileFingerprint: 'large-category-source',
  delimiter: ',',
  headers: const ['date', 'description', 'amount', 'type', 'category'],
  rows: [
    for (var index = 0; index < count; index += 1)
      CsvSourceRow(
        rowNumber: index + 2,
        identityKey: 'large-row-$index',
        values: [
          '2026-09-01',
          'Purchase $index',
          '1000',
          'expense',
          index.isEven ? 'Transport' : ' transport ',
        ],
      ),
  ],
  headerMode: CsvHeaderMode.firstRowHeaders,
);

class _MemoryBatchRepository
    implements TransactionBatchRepository, TransactionImportAtomicRepository {
  final saved = <Transaction>[];
  final createdCategories = <TransactionImportCategoryCreation>[];

  @override
  Future<void> saveAllAtomic(List<Transaction> transactions) async {
    saved.addAll(transactions);
  }

  @override
  Future<Map<String, String>> saveImportAtomic({
    required List<Transaction> transactions,
    required List<TransactionImportCategoryCreation> categoryCreations,
    required List<TransactionImportTransferMutation> transferMutations,
  }) async {
    createdCategories.addAll(categoryCreations);
    saved.addAll(transactions);
    return {for (final item in categoryCreations) item.id: item.id};
  }
}
