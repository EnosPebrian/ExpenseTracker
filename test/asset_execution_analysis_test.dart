import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_execution_analysis.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  group('AssetExecutionAnalysis', () {
    test('buy above reference is unfavorable', () {
      final result = AssetExecutionAnalysis.calculate(
        action: AssetAction.buy,
        quantity: 1000,
        executionUnitPrice: 16300,
        referenceUnitPrice: 16250,
      );

      expect(result.signedDifferencePerUnit, 50);
      expect(result.directionAdjustedDifferencePerUnit, 50);
      expect(result.estimatedTotalDifference, 50000);
      expect(result.differenceBasisPoints, closeTo(30.769, 0.001));
      expect(result.outcome, AssetExecutionOutcome.unfavorable);
    });

    test('buy below reference is favorable', () {
      final result = AssetExecutionAnalysis.calculate(
        action: AssetAction.buy,
        quantity: 1000,
        executionUnitPrice: 16200,
        referenceUnitPrice: 16250,
      );
      expect(result.estimatedTotalDifference, -50000);
      expect(result.outcome, AssetExecutionOutcome.favorable);
    });

    test('sell below reference is unfavorable', () {
      final result = AssetExecutionAnalysis.calculate(
        action: AssetAction.sell,
        quantity: 100,
        executionUnitPrice: 9900,
        referenceUnitPrice: 10000,
      );
      expect(result.directionAdjustedDifferencePerUnit, 100);
      expect(result.estimatedTotalDifference, 10000);
      expect(result.differenceBasisPoints, 100);
      expect(result.outcome, AssetExecutionOutcome.unfavorable);
    });

    test('sell above reference is favorable', () {
      final result = AssetExecutionAnalysis.calculate(
        action: AssetAction.sell,
        quantity: 100,
        executionUnitPrice: 10100,
        referenceUnitPrice: 10000,
      );
      expect(result.directionAdjustedDifferencePerUnit, -100);
      expect(result.outcome, AssetExecutionOutcome.favorable);
    });

    test('matching reference is neutral', () {
      final result = AssetExecutionAnalysis.calculate(
        action: AssetAction.buy,
        quantity: 1,
        executionUnitPrice: 10000,
        referenceUnitPrice: 10000,
      );
      expect(result.estimatedTotalDifference, 0);
      expect(result.outcome, AssetExecutionOutcome.neutral);
    });

    test('fractional quantity uses deterministic nearest-money rounding', () {
      final result = AssetExecutionAnalysis.calculate(
        action: AssetAction.buy,
        quantity: 0.125,
        executionUnitPrice: 10005,
        referenceUnitPrice: 10000,
      );
      expect(result.estimatedTotalDifference, 1);
    });

    test('rejects invalid quantities and reference prices', () {
      expect(
        () => AssetExecutionAnalysis.calculate(
          action: AssetAction.buy,
          quantity: 0,
          executionUnitPrice: 100,
          referenceUnitPrice: 100,
        ),
        throwsArgumentError,
      );
      for (final invalid in [0, -1]) {
        expect(
          () => AssetExecutionAnalysis.calculate(
            action: AssetAction.buy,
            quantity: 1,
            executionUnitPrice: 100,
            referenceUnitPrice: invalid,
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
