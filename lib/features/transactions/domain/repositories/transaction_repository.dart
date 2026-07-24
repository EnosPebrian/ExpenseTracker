import '../entities/transaction.dart';

abstract interface class TransactionRepository {
  Future<List<Transaction>> getAll({bool includeDeleted = false});
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  });
  Future<void> save(Transaction transaction);
  Future<void> softDelete(Transaction transaction);
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  });
}
