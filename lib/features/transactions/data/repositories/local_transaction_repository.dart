import '../../../../core/database/local_store.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this.store);
  final LocalStore store;

  @override
  Future<List<Transaction>> getAll() async =>
      (await store.getTransactions()).map(Transaction.fromRecord).toList();

  @override
  Future<void> save(Transaction transaction) =>
      store.upsertTransaction(transaction.toRecord());

  @override
  Future<void> softDelete(Transaction transaction) =>
      store.softDeleteTransaction(
        transaction.id,
        transaction.deletedAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        version: transaction.version,
      );
}
