import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  const bookId = 'beta08b-book';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pilgrim-beta08b-');
    store = LocalStore(databasePath: p.join(directory.path, 'import.db'));
    await store.initialize();
    await store.upsertFinancialBook(
      FinancialBook(
        id: bookId,
        name: 'Import Test',
        remoteLinkedAt: DateTime(2026, 8, 19),
      ).toRecord(),
      enqueueSync: false,
    );
    store.setActiveBookId(bookId);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Transaction row(String id, String title) => Transaction(
    id: id,
    bookId: bookId,
    title: title,
    category: 'Groceries',
    account: 'Bank',
    date: DateTime(2026, 8, 19),
    amount: 100,
    type: TransactionType.expense,
  );

  test(
    'confirmed batch inserts transactions and ordinary outbox atomically',
    () async {
      final usecase = ImportTransactionsBatch(
        LocalTransactionRepository(store),
      );
      await usecase([row('a', 'A'), row('b', 'B')]);
      expect(await store.getTransactions(), hasLength(2));
      expect(await store.getPendingSyncCount(bookId), 2);
    },
  );

  test('stable identity collision rolls back records and outbox', () async {
    final usecase = ImportTransactionsBatch(LocalTransactionRepository(store));
    await expectLater(
      usecase([row('same', 'A'), row('same', 'B')]),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(await store.getTransactions(), isEmpty);
    expect(await store.getPendingSyncCount(bookId), 0);
  });

  test(
    'database conflict at later row rolls back earlier row and outbox',
    () async {
      final repository = LocalTransactionRepository(store);
      await repository.save(row('existing', 'Existing'));
      final beforeOutbox = await store.getPendingSyncCount(bookId);
      await expectLater(
        repository.saveAllAtomic([
          row('new', 'New'),
          row('existing', 'Collision'),
        ]),
        throwsA(anything),
      );
      final records = await store.getTransactions();
      expect(records.map((item) => item['id']), ['existing']);
      expect(await store.getPendingSyncCount(bookId), beforeOutbox);
    },
  );

  test('invalid zero amount is rejected before any persistence', () async {
    final invalid = row('zero', 'Zero').copyWith(amount: 0);
    await expectLater(
      ImportTransactionsBatch(LocalTransactionRepository(store))([invalid]),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(await store.getTransactions(), isEmpty);
    expect(await store.getPendingSyncCount(bookId), 0);
  });
}
