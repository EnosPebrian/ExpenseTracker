import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

class FakeTransactionRepository implements TransactionRepository {
  final saved = <Transaction>[];
  @override
  Future<List<Transaction>> getAll() async => List.of(saved);
  @override
  Future<void> save(Transaction transaction) async => saved.add(transaction);
  @override
  Future<void> softDelete(Transaction transaction) async =>
      saved.add(transaction);
}

Transaction sample() => Transaction(
  projectId: 'life',
  title: 'Groceries',
  category: 'Konsumsi',
  account: 'BNI Enos',
  date: DateTime(2026, 7, 19),
  amount: 125000,
  type: TransactionType.expense,
);

void main() {
  test('CreateTransaction validates and saves through repository', () async {
    final repository = FakeTransactionRepository();
    final created = await CreateTransaction(repository)(sample());
    expect(repository.saved.single.id, created.id);
    expect(created.projectId, 'life');
    expect(created.syncStatus, 'pending');
  });

  test('UpdateTransaction preserves UUID and increments version', () async {
    final repository = FakeTransactionRepository();
    final original = sample();
    final updated = await UpdateTransaction(repository)(
      original.copyWith(amount: 150000),
    );
    expect(updated.id, original.id);
    expect(updated.version, original.version + 1);
    expect(updated.amount, 150000);
  });

  test(
    'DuplicateTransaction creates a fresh UUID and resets metadata',
    () async {
      final repository = FakeTransactionRepository();
      final original = sample().copyWith(version: 4, syncStatus: 'synced');
      final duplicate = await DuplicateTransaction(repository)(original);
      expect(duplicate.id, isNot(original.id));
      expect(duplicate.projectId, original.projectId);
      expect(duplicate.amount, original.amount);
      expect(duplicate.version, 1);
      expect(duplicate.syncStatus, 'pending');
      expect(repository.saved.single.syncStatus, 'pending');
    },
  );

  test('DeleteTransaction sends a versioned soft-delete record', () async {
    final repository = FakeTransactionRepository();
    final original = sample();
    await DeleteTransaction(repository)(original);
    final deleted = repository.saved.single;
    expect(deleted.id, original.id);
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.version, original.version + 1);
    expect(deleted.syncStatus, 'pending');
  });
}
