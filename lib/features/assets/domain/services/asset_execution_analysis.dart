import '../../../transactions/domain/entities/transaction.dart';

enum AssetExecutionOutcome { favorable, neutral, unfavorable }

class AssetExecutionAnalysisResult {
  const AssetExecutionAnalysisResult({
    required this.executionUnitPrice,
    required this.referenceUnitPrice,
    required this.signedDifferencePerUnit,
    required this.directionAdjustedDifferencePerUnit,
    required this.estimatedTotalDifference,
    required this.differenceBasisPoints,
    required this.outcome,
  });

  final int executionUnitPrice;
  final int referenceUnitPrice;
  final int signedDifferencePerUnit;

  /// Positive is unfavorable, negative is favorable.
  final int directionAdjustedDifferencePerUnit;

  /// Integer-money estimate using deterministic nearest-integer rounding.
  /// Positive is unfavorable, negative is favorable.
  final int estimatedTotalDifference;

  /// Direction-adjusted difference relative to the reference price.
  final double differenceBasisPoints;
  final AssetExecutionOutcome outcome;
}

class AssetExecutionAnalysis {
  const AssetExecutionAnalysis._();

  static AssetExecutionAnalysisResult calculate({
    required AssetAction action,
    required double quantity,
    required int executionUnitPrice,
    required int referenceUnitPrice,
  }) {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Quantity must be finite and greater than zero.',
      );
    }
    if (executionUnitPrice <= 0) {
      throw ArgumentError.value(
        executionUnitPrice,
        'executionUnitPrice',
        'Execution price must be greater than zero.',
      );
    }
    if (referenceUnitPrice <= 0) {
      throw ArgumentError.value(
        referenceUnitPrice,
        'referenceUnitPrice',
        'Reference price must be greater than zero.',
      );
    }

    final signedDifference = executionUnitPrice - referenceUnitPrice;
    final adjustedDifference = action == AssetAction.buy
        ? signedDifference
        : -signedDifference;
    final outcome = adjustedDifference > 0
        ? AssetExecutionOutcome.unfavorable
        : adjustedDifference < 0
        ? AssetExecutionOutcome.favorable
        : AssetExecutionOutcome.neutral;

    return AssetExecutionAnalysisResult(
      executionUnitPrice: executionUnitPrice,
      referenceUnitPrice: referenceUnitPrice,
      signedDifferencePerUnit: signedDifference,
      directionAdjustedDifferencePerUnit: adjustedDifference,
      estimatedTotalDifference: (adjustedDifference * quantity).round(),
      differenceBasisPoints: adjustedDifference / referenceUnitPrice * 10000,
      outcome: outcome,
    );
  }
}
