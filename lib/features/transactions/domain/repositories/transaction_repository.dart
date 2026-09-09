import '../entities/transaction.dart';
import '../entities/internal_transfer_link.dart';
import '../import/transaction_import_category_review.dart';
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

class TransactionImportTransferMutation {
  const TransactionImportTransferMutation({
    required this.link,
    this.expectedTransactionVersions = const {},
    this.requireNewTransactionIds = const {},
  });

  final InternalTransferLink link;
  final Map<String, int> expectedTransactionVersions;
  final Set<String> requireNewTransactionIds;
}

abstract interface class TransactionImportAtomicRepository {
  Future<Map<String, String>> saveImportAtomic({
    required List<Transaction> transactions,
    required List<TransactionImportCategoryCreation> categoryCreations,
    required List<TransactionImportTransferMutation> transferMutations,
  });
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
