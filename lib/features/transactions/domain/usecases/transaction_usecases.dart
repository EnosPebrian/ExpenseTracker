import '../../../assets/domain/entities/asset_definition.dart';
import '../../../assets/domain/services/asset_transaction_sequence_validator.dart';
import '../../../assets/domain/services/asset_numeric_policy.dart';
import '../../../assets/domain/services/asset_trade_validator.dart';
import '../entities/transaction.dart';
import '../entities/transaction_relation_type.dart';
import '../repositories/transaction_repository.dart';
import 'save_asset_conversion_with_fee.dart';

class TransactionValidationException implements Exception {
  TransactionValidationException(this.message, {this.assetValidation});
  final String message;
  final AssetSequenceValidationResult? assetValidation;
  @override
  String toString() => message;
}

typedef AssetDefinitionResolver = AssetDefinition? Function(String id);

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
  if (transaction.feeAmount < 0) {
    throw TransactionValidationException('Transaction fee cannot be negative.');
  }
  if (transaction.relationType == TransactionRelationType.assetFeeExpense) {
    if (transaction.relatedTransactionId?.trim().isEmpty != false ||
        transaction.type != TransactionType.expense ||
        transaction.feeAmount != 0 ||
        transaction.feeTreatment != AssetFeeTreatment.none) {
      throw TransactionValidationException(
        'The managed asset fee expense relationship is invalid.',
      );
    }
  } else if (transaction.relatedTransactionId != null) {
    throw TransactionValidationException(
      'A related transaction requires a supported relationship type.',
    );
  }
  if (transaction.type == TransactionType.assetConversion) {
    final quantity = transaction.quantity;
    final kind = AssetNumericPolicy.inferKind(
      unit: transaction.unit,
      symbol: transaction.assetSymbol,
      assetName: transaction.assetName,
    );
    final result = AssetNumericPolicy.validateQuantity(
      quantity: quantity ?? 0,
      kind: kind,
      symbol: transaction.assetSymbol,
    );
    if (!result.isValid) {
      throw TransactionValidationException(result.message!);
    }
  }
  _validateMarketReference(transaction);
  if (transaction.feeAmount > 0) {
    if (transaction.type != TransactionType.assetConversion ||
        transaction.assetAction == null) {
      throw TransactionValidationException(
        'Transaction fees are supported only for asset trades.',
      );
    }

    if (transaction.feeTreatment == AssetFeeTreatment.none) {
      throw TransactionValidationException(
        'Choose how to handle the transaction fee.',
      );
    }

    if (transaction.assetAction == AssetAction.buy &&
        transaction.feeTreatment == AssetFeeTreatment.deductFromSaleProceeds) {
      throw TransactionValidationException(
        'Buy fees can only be added to cost basis or recorded as an expense.',
      );
    }

    if (transaction.assetAction == AssetAction.sell &&
        transaction.feeTreatment == AssetFeeTreatment.capitalizeIntoCostBasis) {
      throw TransactionValidationException(
        'Sell fees can only be deducted from proceeds or recorded as an expense.',
      );
    }

    if (transaction.assetAction == AssetAction.sell &&
        transaction.feeTreatment == AssetFeeTreatment.deductFromSaleProceeds &&
        transaction.feeAmount >= transaction.amount) {
      throw TransactionValidationException(
        'The transaction fee must be less than the gross sale amount.',
      );
    }
  }
}

void _validateMarketReference(Transaction transaction) {
  final hasReferenceMetadata =
      transaction.marketReferenceUnitPrice != null ||
      transaction.marketReferenceCurrencyCode != null ||
      transaction.marketReferenceUnit != null ||
      transaction.marketReferenceSource != null ||
      transaction.marketReferenceQuotedAt != null;
  if (!hasReferenceMetadata) return;

  if (transaction.type != TransactionType.assetConversion ||
      transaction.relationType == TransactionRelationType.assetFeeExpense) {
    throw TransactionValidationException(
      'Execution references are supported only for parent asset trades.',
    );
  }

  final price = transaction.marketReferenceUnitPrice;
  if (price == null || price <= 0) {
    throw TransactionValidationException(
      'Enter a reference price greater than zero.',
    );
  }
  final executionPrice = transaction.unitPrice;
  if (executionPrice == null || executionPrice <= 0) {
    throw TransactionValidationException(
      'A valid execution price is required for comparison.',
    );
  }
  if (transaction.marketReferenceCurrencyCode?.trim().toUpperCase() != 'IDR') {
    throw TransactionValidationException(
      'The execution reference currency must be IDR.',
    );
  }
  final transactionUnit = transaction.unit?.trim().toLowerCase();
  final referenceUnit = transaction.marketReferenceUnit?.trim().toLowerCase();
  if (transactionUnit == null ||
      transactionUnit.isEmpty ||
      referenceUnit != transactionUnit) {
    throw TransactionValidationException(
      'The execution reference unit must match the asset unit.',
    );
  }
  if (transaction.marketReferenceSource == null) {
    throw TransactionValidationException(
      'Choose a source for the execution reference.',
    );
  }
}

class CreateTransaction {
  CreateTransaction(
    this.repository, {
    this.assetSequenceValidator = const AssetTransactionSequenceValidator(),
    this.assetDefinitionResolver,
    AssetTradeValidator? assetTradeValidator,
  }) : assetTradeValidator =
           assetTradeValidator ??
           AssetTradeValidator(sequenceValidator: assetSequenceValidator);
  final TransactionRepository repository;
  final AssetTransactionSequenceValidator assetSequenceValidator;
  final AssetDefinitionResolver? assetDefinitionResolver;
  final AssetTradeValidator assetTradeValidator;

  Future<Transaction> call(Transaction transaction) async {
    _ensureNotManagedExpense(transaction);
    validateTransaction(transaction);
    final prepared = transaction.copyWith(
      version: 1,
      updatedAt: transaction.createdAt,
      syncStatus: 'pending',
    );
    await _validateCandidate(
      repository: repository,
      tradeValidator: assetTradeValidator,
      assetDefinitionResolver: assetDefinitionResolver,
      candidate: prepared,
    );
    if (prepared.type == TransactionType.assetConversion) {
      await SaveAssetConversionWithFee(repository).save(prepared);
    } else {
      await repository.save(prepared);
    }
    return prepared;
  }
}

class UpdateTransaction {
  UpdateTransaction(
    this.repository, {
    this.assetSequenceValidator = const AssetTransactionSequenceValidator(),
    this.assetDefinitionResolver,
    AssetTradeValidator? assetTradeValidator,
  }) : assetTradeValidator =
           assetTradeValidator ??
           AssetTradeValidator(sequenceValidator: assetSequenceValidator);
  final TransactionRepository repository;
  final AssetTransactionSequenceValidator assetSequenceValidator;
  final AssetDefinitionResolver? assetDefinitionResolver;
  final AssetTradeValidator assetTradeValidator;

  Future<Transaction> call(Transaction transaction) async {
    _ensureNotManagedExpense(transaction);
    validateTransaction(transaction);
    final updated = transaction.copyWith(
      version: transaction.version + 1,
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );
    await _validateCandidate(
      repository: repository,
      tradeValidator: assetTradeValidator,
      assetDefinitionResolver: assetDefinitionResolver,
      candidate: updated,
      replacedTransactionId: transaction.id,
    );
    if (updated.type == TransactionType.assetConversion) {
      await SaveAssetConversionWithFee(repository).save(updated);
    } else {
      await repository.save(updated);
    }
    return updated;
  }
}

class DeleteTransaction {
  DeleteTransaction(
    this.repository, {
    this.assetSequenceValidator = const AssetTransactionSequenceValidator(),
  });
  final TransactionRepository repository;
  final AssetTransactionSequenceValidator assetSequenceValidator;

  Future<void> call(Transaction transaction) async {
    _ensureNotManagedExpense(transaction);
    if (transaction.type == TransactionType.assetConversion) {
      final result = assetSequenceValidator.validateRemoval(
        existingTransactions: await repository.getAll(),
        removedTransaction: transaction,
      );
      _throwIfInvalid(result);
    }

    final now = DateTime.now();
    final deleted = transaction.copyWith(
      version: transaction.version + 1,
      deletedAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );
    if (transaction.type == TransactionType.assetConversion) {
      await SaveAssetConversionWithFee(repository).delete(deleted);
    } else {
      await repository.softDelete(deleted);
    }
  }
}

class GetTransactions {
  GetTransactions(this.repository);
  final TransactionRepository repository;
  Future<List<Transaction>> call() => repository.getAll();
}

class DuplicateTransaction {
  DuplicateTransaction(
    this.repository, {
    this.assetSequenceValidator = const AssetTransactionSequenceValidator(),
    this.assetDefinitionResolver,
    AssetTradeValidator? assetTradeValidator,
  }) : assetTradeValidator =
           assetTradeValidator ??
           AssetTradeValidator(sequenceValidator: assetSequenceValidator);
  final TransactionRepository repository;
  final AssetTransactionSequenceValidator assetSequenceValidator;
  final AssetDefinitionResolver? assetDefinitionResolver;
  final AssetTradeValidator assetTradeValidator;

  Future<Transaction> call(
    Transaction original, {
    bool withoutAmount = false,
  }) async {
    _ensureNotManagedExpense(original);
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
      assetDefinitionId: original.assetDefinitionId,
      assetName: original.assetName,
      assetSymbol: original.assetSymbol,
      assetAction: original.assetAction,
      feeAmount: original.feeAmount,
      feeTreatment: original.feeTreatment,
    );
    validateTransaction(duplicate);

    final prepared = duplicate.copyWith(syncStatus: 'pending');

    await _validateCandidate(
      repository: repository,
      tradeValidator: assetTradeValidator,
      assetDefinitionResolver: assetDefinitionResolver,
      candidate: prepared,
    );
    if (prepared.type == TransactionType.assetConversion) {
      await SaveAssetConversionWithFee(repository).save(prepared);
    } else {
      await repository.save(prepared);
    }

    return prepared;
  }
}

void _ensureNotManagedExpense(Transaction transaction) {
  if (transaction.relationType == TransactionRelationType.assetFeeExpense) {
    throw TransactionValidationException(managedAssetFeeExpenseMessage);
  }
}

Future<void> _validateCandidate({
  required TransactionRepository repository,
  required AssetTradeValidator tradeValidator,
  required AssetDefinitionResolver? assetDefinitionResolver,
  required Transaction candidate,
  String? replacedTransactionId,
}) async {
  if (candidate.type != TransactionType.assetConversion) {
    return;
  }

  final definitionId = candidate.assetDefinitionId?.trim();
  final definition = definitionId == null || definitionId.isEmpty
      ? null
      : assetDefinitionResolver?.call(definitionId);
  final result = tradeValidator.validateCandidate(
    existingTransactions: await repository.getAll(),
    candidate: candidate,
    definition: definition,
    replacedTransactionId: replacedTransactionId,
  );
  if (!result.isValid) {
    throw TransactionValidationException(
      result.message ?? 'The asset transaction is invalid.',
      assetValidation: result.sequenceValidation,
    );
  }
}

void _throwIfInvalid(AssetSequenceValidationResult result) {
  if (!result.isValid) {
    throw TransactionValidationException(
      result.message,
      assetValidation: result,
    );
  }
}
