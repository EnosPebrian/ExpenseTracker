import '../../../../core/database/local_store.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this.store);
  final LocalStore store;

  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async =>
      (await store.getTransactions(
        includeDeleted: includeDeleted,
      )).map(Transaction.fromRecord).toList();

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async {
    final record = await store.getAssetFeeExpense(
      parentTransactionId,
      includeDeleted: includeDeleted,
    );
    return record == null ? null : Transaction.fromRecord(record);
  }

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

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) => store.saveAssetFeeChange(
    parent: parent.toRecord(),
    linkedExpense: linkedExpense?.toRecord(),
    obsoleteLinkedExpense: obsoleteLinkedExpense?.toRecord(),
  );
}
