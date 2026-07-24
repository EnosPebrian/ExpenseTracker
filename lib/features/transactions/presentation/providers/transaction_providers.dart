import '../../../../core/database/local_store.dart';
import '../../data/repositories/local_transaction_repository.dart';
import '../../domain/usecases/transaction_usecases.dart';
import '../controllers/transaction_controller.dart';

/// Transitional dependency factory until Riverpod is introduced.
class TransactionProviders {
  static TransactionController controller(
    LocalStore store, {
    AssetDefinitionResolver? assetDefinitionResolver,
    Future<void> Function()? afterMutation,
  }) {
    final repository = LocalTransactionRepository(store);
    return TransactionController(
      create: CreateTransaction(
        repository,
        assetDefinitionResolver: assetDefinitionResolver,
      ),
      update: UpdateTransaction(
        repository,
        assetDefinitionResolver: assetDefinitionResolver,
      ),
      delete: DeleteTransaction(repository),
      get: GetTransactions(repository),
      duplicate: DuplicateTransaction(
        repository,
        assetDefinitionResolver: assetDefinitionResolver,
      ),
      afterMutation: afterMutation,
    );
  }
}
