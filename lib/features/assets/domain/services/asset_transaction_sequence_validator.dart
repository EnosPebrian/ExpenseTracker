import '../../../transactions/domain/entities/transaction.dart';
import 'asset_numeric_policy.dart';
import 'asset_transaction_identity.dart';

class AssetSequenceValidationResult {
  const AssetSequenceValidationResult({
    required this.isValid,
    required this.availableQuantity,
    required this.requestedQuantity,
    required this.shortfall,
    required this.unit,
    this.invalidTransactionId,
    this.invalidTransactionDate,
    this.invalidatesLaterTransaction = false,
  });

  final bool isValid;
  final double availableQuantity;
  final double requestedQuantity;
  final double shortfall;
  final String unit;
  final String? invalidTransactionId;
  final DateTime? invalidTransactionDate;
  final bool invalidatesLaterTransaction;

  String get message {
    final label = unit.trim().isEmpty ? 'units' : unit.trim().toUpperCase();
    final available = _formatQuantity(availableQuantity);
    final requested = _formatQuantity(requestedQuantity);

    if (invalidatesLaterTransaction) {
      return 'This change would make a later $label sale exceed the '
          'available balance.';
    }

    return 'You can sell up to $label $available. Requested: '
        '$label $requested.';
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }
}

/// Validates that a proposed asset history never produces a negative holding.
class AssetTransactionSequenceValidator {
  const AssetTransactionSequenceValidator();

  AssetSequenceValidationResult validateCandidate({
    required List<Transaction> existingTransactions,
    required Transaction candidate,
    String? replacedTransactionId,
  }) {
    if (candidate.type != TransactionType.assetConversion ||
        candidate.deletedAt != null) {
      return _validResult(candidate);
    }

    final replaced = _findById(existingTransactions, replacedTransactionId);
    final affectedKeys = <String>{AssetTransactionIdentity.key(candidate)};

    if (replaced != null && replaced.type == TransactionType.assetConversion) {
      affectedKeys.add(AssetTransactionIdentity.key(replaced));
    }

    final proposed =
        existingTransactions
            .where(
              (transaction) =>
                  transaction.deletedAt == null &&
                  transaction.id != replacedTransactionId,
            )
            .toList()
          ..add(candidate);

    return _validateHistory(
      transactions: proposed,
      affectedKeys: affectedKeys,
      candidate: candidate,
    );
  }

  AssetSequenceValidationResult validateRemoval({
    required List<Transaction> existingTransactions,
    required Transaction removedTransaction,
  }) {
    if (removedTransaction.type != TransactionType.assetConversion) {
      return _validResult(removedTransaction);
    }

    return _validateHistory(
      transactions: existingTransactions
          .where(
            (transaction) =>
                transaction.deletedAt == null &&
                transaction.id != removedTransaction.id,
          )
          .toList(),
      affectedKeys: {AssetTransactionIdentity.key(removedTransaction)},
      candidate: removedTransaction,
      candidateWasRemoved: true,
    );
  }

  AssetSequenceValidationResult _validateHistory({
    required List<Transaction> transactions,
    required Set<String> affectedKeys,
    required Transaction candidate,
    bool candidateWasRemoved = false,
  }) {
    var candidateAvailable = 0.0;
    final candidateKey = AssetTransactionIdentity.key(candidate);

    for (final key in affectedKeys) {
      final history =
          transactions
              .where(
                (transaction) =>
                    transaction.type == TransactionType.assetConversion &&
                    transaction.deletedAt == null &&
                    (transaction.quantity ?? 0) > 0 &&
                    AssetTransactionIdentity.key(transaction) == key,
              )
              .toList()
            ..sort(AssetTransactionIdentity.compareChronologically);

      final reference = history.isEmpty ? candidate : history.first;
      final kind = AssetNumericPolicy.inferKind(
        unit: reference.unit,
        symbol: reference.assetSymbol,
        assetName: reference.assetName,
      );
      final tolerance = AssetNumericPolicy.comparisonToleranceFor(kind);

      var runningQuantity = 0.0;

      for (final transaction in history) {
        final quantity = transaction.quantity ?? 0;
        final action = AssetTransactionIdentity.resolveAction(transaction);

        if (action == AssetAction.buy) {
          runningQuantity = AssetNumericPolicy.normalizeQuantity(
            runningQuantity + quantity,
            kind,
          );
          continue;
        }

        if (transaction.id == candidate.id && key == candidateKey) {
          candidateAvailable = runningQuantity;
        }

        if (quantity - runningQuantity > tolerance) {
          final available = runningQuantity < 0
              ? 0.0
              : AssetNumericPolicy.normalizeQuantity(runningQuantity, kind);
          final isCandidate = transaction.id == candidate.id;
          final occursAfterCandidate =
              AssetTransactionIdentity.compareChronologically(
                candidate,
                transaction,
              ) <
              0;

          return AssetSequenceValidationResult(
            isValid: false,
            availableQuantity: available,
            requestedQuantity: quantity,
            shortfall: quantity - available,
            unit: transaction.unit ?? candidate.unit ?? 'unit',
            invalidTransactionId: transaction.id,
            invalidTransactionDate: transaction.date,
            invalidatesLaterTransaction:
                !isCandidate && (candidateWasRemoved || occursAfterCandidate),
          );
        }

        runningQuantity = AssetNumericPolicy.normalizeQuantity(
          runningQuantity - quantity,
          kind,
        );
      }
    }

    final action = AssetTransactionIdentity.resolveAction(candidate);

    return AssetSequenceValidationResult(
      isValid: true,
      availableQuantity: action == AssetAction.sell && !candidateWasRemoved
          ? candidateAvailable
          : 0,
      requestedQuantity: candidate.quantity ?? 0,
      shortfall: 0,
      unit: candidate.unit ?? 'unit',
    );
  }

  static Transaction? _findById(List<Transaction> transactions, String? id) {
    if (id == null) {
      return null;
    }

    for (final transaction in transactions) {
      if (transaction.id == id) {
        return transaction;
      }
    }

    return null;
  }

  static AssetSequenceValidationResult _validResult(Transaction transaction) {
    return AssetSequenceValidationResult(
      isValid: true,
      availableQuantity: 0,
      requestedQuantity: transaction.quantity ?? 0,
      shortfall: 0,
      unit: transaction.unit ?? 'unit',
    );
  }
}
