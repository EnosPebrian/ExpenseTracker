import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';

void main() {
  final account = Account(
    id: 'account',
    bookId: 'book',
    name: 'Bank',
    accountType: AccountType.bank,
  );
  SelectedCsvFile file() => SelectedCsvFile(
    name: 'canonical.csv',
    bytes: utf8.encode(
      'date,description,amount,type,category\n'
      '2026-08-01,Food,250000,expense,Groceries\n'
      '2026-08-02,Salary,1500000,income,Salary',
    ),
  );

  TransactionImportController controller({
    required _BatchRepository repository,
    Future<SelectedCsvFile?> Function()? picker,
    Future<bool> Function()? freshness,
  }) => TransactionImportController(
    pickFile: picker ?? () async => file(),
    importBatch: ImportTransactionsBatch(repository),
    existingTransactions: () async => repository.saved,
    accounts: [account],
    expenseCategories: const ['Groceries'],
    incomeCategories: const ['Salary'],
    activeBookId: 'book',
    activeMemberId: 'member',
    refreshBeforeAnalysis: freshness,
  );

  test('file-picker cancellation creates no draft or mutation', () async {
    final repository = _BatchRepository();
    final subject = controller(
      repository: repository,
      picker: () async => null,
    );
    await subject.selectCsv();
    expect(subject.source, isNull);
    expect(repository.calls, 0);
  });

  test('canonical review is complete before any mutation', () async {
    final repository = _BatchRepository();
    final subject = controller(repository: repository);
    subject.selectAccount(account);
    await subject.selectCsv();
    await subject.analyze();
    expect(subject.preview?.readyCount, 2);
    expect(repository.calls, 0);
  });

  test('mixed type bulk category assignment is blocked', () async {
    final repository = _BatchRepository();
    final subject = controller(repository: repository);
    subject.selectAccount(account);
    await subject.selectCsv();
    await subject.analyze();
    for (final draft in subject.preview!.drafts) {
      subject.toggleSelected(draft.transactionId, true);
    }
    expect(subject.bulkAssignCategory('Groceries'), isFalse);
  });

  test(
    'draft edit preserves source identity and recalculates duplicates',
    () async {
      final repository = _BatchRepository();
      repository.saved.add(
        Transaction(
          id: 'existing-id',
          bookId: 'book',
          title: 'Existing merchant',
          category: 'Groceries',
          account: 'Bank',
          date: DateTime(2026, 8, 1),
          amount: 250000,
          type: TransactionType.expense,
        ),
      );
      final subject = controller(repository: repository);
      subject.selectAccount(account);
      await subject.selectCsv();
      await subject.analyze();
      final before = subject.preview!.drafts.first;

      subject.editDraft(before.transactionId, description: 'Existing merchant');

      final after = subject.preview!.drafts.first;
      expect(after.transactionId, before.transactionId);
      expect(after.sourceRowFingerprint, before.sourceRowFingerprint);
      expect(
        after.classification,
        TransactionImportClassification.semanticDuplicate,
      );
      expect(after.included, isFalse);
    },
  );

  test('review can explicitly include a semantic duplicate', () async {
    final repository = _BatchRepository();
    repository.saved.add(
      Transaction(
        id: 'existing-id',
        bookId: 'book',
        title: 'Food',
        category: 'Groceries',
        account: 'Bank',
        date: DateTime(2026, 8, 1),
        amount: 250000,
        type: TransactionType.expense,
      ),
    );
    final subject = controller(repository: repository);
    subject.selectAccount(account);
    await subject.selectCsv();
    await subject.analyze();
    final duplicate = subject.preview!.drafts.first;
    expect(
      duplicate.classification,
      TransactionImportClassification.semanticDuplicate,
    );

    subject.toggleIncluded(duplicate.transactionId, true);
    await subject.commit();

    expect(repository.saved, hasLength(3));
    expect(subject.result?.importedIds, contains(duplicate.transactionId));
  });

  test('bulk inclusion controls affect only importable review rows', () async {
    final repository = _BatchRepository();
    final subject = controller(repository: repository);
    subject.selectAccount(account);
    await subject.selectCsv();
    await subject.analyze();

    subject.excludeAll();
    expect(subject.preview?.readyCount, 0);
    subject.includeAllSafeNew();
    expect(subject.preview?.readyCount, 2);
  });

  test('exclude then commit saves only included rows in one call', () async {
    final repository = _BatchRepository();
    final subject = controller(repository: repository);
    subject.selectAccount(account);
    await subject.selectCsv();
    await subject.analyze();
    subject.toggleIncluded(subject.preview!.drafts.first.transactionId, false);
    await subject.commit();
    expect(repository.calls, 1);
    expect(repository.saved, hasLength(1));
    expect(subject.result?.importedIds, hasLength(1));
  });

  test(
    're-import exact file creates zero new rows and zero batch writes',
    () async {
      final repository = _BatchRepository();
      final first = controller(repository: repository);
      first.selectAccount(account);
      await first.selectCsv();
      await first.analyze();
      await first.commit();
      expect(repository.saved, hasLength(2));

      final repeated = controller(repository: repository);
      repeated.selectAccount(account);
      await repeated.selectCsv();
      await repeated.analyze();
      expect(repeated.preview?.readyCount, 0);
      expect(
        repeated.preview?.count(
          TransactionImportClassification.alreadyImported,
        ),
        2,
      );
      expect(repository.calls, 1);
    },
  );

  test('offline linked preview records local-only freshness warning', () async {
    final repository = _BatchRepository();
    final subject = controller(
      repository: repository,
      freshness: () async => false,
    );
    subject.selectAccount(account);
    await subject.selectCsv();
    await subject.analyze();
    expect(subject.preview?.remoteFreshnessVerified, isFalse);
    expect(subject.preview?.readyCount, 2);
  });
}

class _BatchRepository implements TransactionBatchRepository {
  final List<Transaction> saved = [];
  int calls = 0;

  @override
  Future<void> saveAllAtomic(List<Transaction> transactions) async {
    calls++;
    saved.addAll(transactions);
  }
}
