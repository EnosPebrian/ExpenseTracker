import '../../../transactions/domain/entities/transaction.dart';
import '../entities/asset_definition.dart';
import '../entities/asset_kind.dart';
import 'asset_numeric_policy.dart';
import 'asset_stock_lot_policy.dart';
import 'asset_transaction_sequence_validator.dart';

class AssetTradeValidationResult {
  const AssetTradeValidationResult({
    required this.isValid,
    required this.sequenceValidation,
    this.lotValidation,
    this.message,
  });

  final bool isValid;
  final AssetSequenceValidationResult sequenceValidation;
  final AssetStockLotValidationResult? lotValidation;
  final String? message;
}

/// Coordinates reusable sequence and stock-lot validation before persistence.
class AssetTradeValidator {
  const AssetTradeValidator({
    this.sequenceValidator = const AssetTransactionSequenceValidator(),
    this.stockLotPolicy = const AssetStockLotPolicy(),
  });

  final AssetTransactionSequenceValidator sequenceValidator;
  final AssetStockLotPolicy stockLotPolicy;

  AssetTradeValidationResult validateCandidate({
    required List<Transaction> existingTransactions,
    required Transaction candidate,
    AssetDefinition? definition,
    String? replacedTransactionId,
  }) {
    final sequence = sequenceValidator.validateCandidate(
      existingTransactions: existingTransactions,
      candidate: candidate,
      replacedTransactionId: replacedTransactionId,
    );

    if (candidate.type != TransactionType.assetConversion) {
      return AssetTradeValidationResult(
        isValid: sequence.isValid,
        sequenceValidation: sequence,
        message: sequence.isValid ? null : sequence.message,
      );
    }

    final kind = AssetNumericPolicy.inferKind(
      unit: candidate.unit,
      symbol: candidate.assetSymbol,
      assetName: candidate.assetName,
    );
    if (kind != AssetKind.stock) {
      return AssetTradeValidationResult(
        isValid: sequence.isValid,
        sequenceValidation: sequence,
        message: sequence.isValid ? null : sequence.message,
      );
    }

    final definitionError = _definitionError(candidate, definition);
    if (definitionError != null) {
      return AssetTradeValidationResult(
        isValid: false,
        sequenceValidation: sequence,
        message: definitionError,
      );
    }

    final lot = stockLotPolicy.evaluate(
      definition: definition!,
      action: candidate.assetAction ?? AssetAction.buy,
      requestedShares: candidate.quantity ?? 0,
      availableShares: sequence.availableQuantity,
    );
    final isValid = sequence.isValid && lot.isValid;
    return AssetTradeValidationResult(
      isValid: isValid,
      sequenceValidation: sequence,
      lotValidation: lot,
      message: !sequence.isValid ? sequence.message : lot.message,
    );
  }

  static String? _definitionError(
    Transaction candidate,
    AssetDefinition? definition,
  ) {
    final definitionId = candidate.assetDefinitionId?.trim();
    if (definitionId == null || definitionId.isEmpty) {
      return 'Choose an active concrete stock definition.';
    }
    if (definition == null || definition.id != definitionId) {
      return 'The selected stock definition could not be found.';
    }
    if (definition.isDeleted) {
      return 'The selected stock definition is no longer active.';
    }
    if (definition.kind != AssetKind.stock) {
      return 'The selected asset definition is not a stock.';
    }
    if (definition.lotSize < 1) {
      return '${definition.normalizedSymbol ?? definition.displayName} has an '
          'invalid lot size.';
    }
    return null;
  }
}
