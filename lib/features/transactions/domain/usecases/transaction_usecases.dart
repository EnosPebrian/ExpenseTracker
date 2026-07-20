import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

class TransactionValidationException implements Exception {
  TransactionValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

void validateTransaction(Transaction transaction) {
  if (transaction.title.trim().isEmpty) {
    throw TransactionValidationException(
      'A transaction description is required.',
    );
  }
  if (transaction.amount < 0) {
    throw TransactionValidationException(
      'Transaction amount cannot be negative.',
    );
  }
  if (transaction.type == TransactionType.assetConversion &&
      (transaction.quantity == null || transaction.quantity! <= 0)) {
    throw TransactionValidationException(
      'Asset conversions require a positive quantity.',
    );
  }
}

class CreateTransaction {
  CreateTransaction(this.repository);
  final TransactionRepository repository;
  Future<Transaction> call(Transaction transaction) async {
    validateTransaction(transaction);
    final prepared = transaction.copyWith(
      version: 1,
      updatedAt: transaction.createdAt,
      syncStatus: 'pending',
    );
    await repository.save(prepared);
    return prepared;
  }
}

class UpdateTransaction {
  UpdateTransaction(this.repository);
  final TransactionRepository repository;
  Future<Transaction> call(Transaction transaction) async {
    validateTransaction(transaction);
    final updated = transaction.copyWith(
      version: transaction.version + 1,
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );
    await repository.save(updated);
    return updated;
  }
}

class DeleteTransaction {
  DeleteTransaction(this.repository);
  final TransactionRepository repository;
  Future<void> call(Transaction transaction) async {
    final now = DateTime.now();
    await repository.softDelete(
      transaction.copyWith(
        version: transaction.version + 1,
        deletedAt: now,
        updatedAt: now,
        syncStatus: 'pending',
      ),
    );
  }
}

class GetTransactions {
  GetTransactions(this.repository);
  final TransactionRepository repository;
  Future<List<Transaction>> call() => repository.getAll();
}

class DuplicateTransaction {
  DuplicateTransaction(this.repository);
  final TransactionRepository repository;
  Future<Transaction> call(
    Transaction original, {
    bool withoutAmount = false,
  }) async {
    final duplicate = Transaction(
      projectId: original.projectId,
      title: original.title,
      category: original.category,
      account: original.account,
      date: DateTime.now(),
      amount: withoutAmount ? 0 : original.amount,
      type: original.type,
      quantity: original.quantity,
      unit: original.unit,
      unitPrice: original.unitPrice,
    );
    validateTransaction(duplicate);

    final prepared = duplicate.copyWith(syncStatus: 'pending');

    await repository.save(prepared);

    return prepared;
  }
}
