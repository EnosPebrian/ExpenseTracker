import '../entities/transaction.dart';
import '../entities/internal_transfer_link.dart';
import '../../../master_data/domain/entities/account.dart';

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

abstract interface class TransactionBatchRepository {
  Future<void> saveAllAtomic(List<Transaction> transactions);
}

abstract interface class InternalTransferRepository {
  Future<List<Transaction>> getAllTransactions({bool includeDeleted = false});
  Future<List<Account>> getAllAccounts({bool includeDeleted = false});
  Future<List<InternalTransferLink>> getTransferLinks({
    bool includeDeleted = false,
  });
  Future<void> saveInternalTransferAtomic({
    required List<Transaction> transactions,
    required InternalTransferLink link,
    Map<String, int> expectedTransactionVersions = const {},
    Set<String> requireNewTransactionIds = const {},
  });
}
