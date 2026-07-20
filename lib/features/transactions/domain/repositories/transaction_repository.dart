import '../entities/transaction.dart';

abstract interface class TransactionRepository {
  Future<List<Transaction>> getAll();
  Future<void> save(Transaction transaction);
  Future<void> softDelete(Transaction transaction);
}
