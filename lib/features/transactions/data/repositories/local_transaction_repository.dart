import '../../../../core/database/local_store.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/internal_transfer_link.dart';
import '../../domain/import/transaction_import_category_review.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../../master_data/domain/entities/account.dart';

class LocalTransactionRepository
    implements
        TransactionRepository,
        TransactionBatchRepository,
        TransactionImportAtomicRepository,
        InternalTransferRepository {
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
  Future<void> saveAllAtomic(List<Transaction> transactions) =>
      store.insertTransactionsAtomic(
        transactions.map((transaction) => transaction.toRecord()).toList(),
      );

  @override
  Future<Map<String, String>> saveImportAtomic({
    required List<Transaction> transactions,
    required List<TransactionImportCategoryCreation> categoryCreations,
    required List<TransactionImportTransferMutation> transferMutations,
  }) => store.insertTransactionImportAtomic(
    transactions: transactions.map((item) => item.toRecord()).toList(),
    categoryCreations: categoryCreations
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'book_id': item.bookId,
            'name': item.name,
            'category_type': item.type.name,
          },
        )
        .toList(),
    transferLinks: transferMutations
        .map((item) => item.link.toRecord())
        .toList(),
    expectedTransactionVersions: {
      for (final item in transferMutations) ...item.expectedTransactionVersions,
    },
    requireNewTransactionIds: {
      for (final item in transferMutations) ...item.requireNewTransactionIds,
    },
  );

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

  @override
  Future<List<Transaction>> getAllTransactions({bool includeDeleted = false}) =>
      getAll(includeDeleted: includeDeleted);

  @override
  Future<List<Account>> getAllAccounts({bool includeDeleted = false}) async =>
      (await store.getAccounts(
        includeDeleted: includeDeleted,
      )).map(Account.fromRecord).toList();

  @override
  Future<List<InternalTransferLink>> getTransferLinks({
    bool includeDeleted = false,
  }) async => (await store.getTransferLinks(
    includeDeleted: includeDeleted,
  )).map(InternalTransferLink.fromRecord).toList();

  @override
  Future<void> saveInternalTransferAtomic({
    required List<Transaction> transactions,
    required InternalTransferLink link,
    Map<String, int> expectedTransactionVersions = const {},
    Set<String> requireNewTransactionIds = const {},
  }) => store.saveInternalTransferAtomic(
    transactions: transactions.map((item) => item.toRecord()).toList(),
    link: link.toRecord(),
    expectedTransactionVersions: expectedTransactionVersions,
    requireNewTransactionIds: requireNewTransactionIds,
  );
}
