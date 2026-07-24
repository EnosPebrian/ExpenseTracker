import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/tithe/domain/tithe_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  test('execution reference metadata does not change portfolio accounting', () {
    final trade = Transaction(
      title: 'USD acquisition',
      category: 'Asset conversion',
      account: 'Cash -> USD',
      date: DateTime.utc(2026, 7, 24),
      amount: 16300000,
      type: TransactionType.assetConversion,
      quantity: 1000,
      unit: 'usd',
      unitPrice: 16300,
      assetDefinitionId: 'asset-usd',
      assetName: 'US Dollar Cash',
      assetSymbol: 'USD',
      assetAction: AssetAction.buy,
      feeAmount: 100000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
    );
    final referenced = trade.copyWith(
      marketReferenceUnitPrice: 16250,
      marketReferenceCurrencyCode: 'IDR',
      marketReferenceUnit: 'usd',
      marketReferenceSource: AssetMarketReferenceSource.manual,
      marketReferenceQuotedAt: DateTime.utc(2026, 7, 24, 8),
    );

    final baseline = AssetPortfolioCalculator.calculate(transactions: [trade]);
    final withReference = AssetPortfolioCalculator.calculate(
      transactions: [referenced],
    );

    expect(withReference.totalCostBasis, baseline.totalCostBasis);
    expect(withReference.totalMarketValue, baseline.totalMarketValue);
    expect(withReference.totalRealizedGain, baseline.totalRealizedGain);
    expect(withReference.totalUnrealizedGain, baseline.totalUnrealizedGain);
    expect(
      withReference.holdings.single.averageCost,
      baseline.holdings.single.averageCost,
    );

    final baselineSummary = FinancialSummary.calculate(
      transactions: [trade],
      referenceDate: DateTime(2026, 7, 24),
      tithePolicy: TithePolicy.defaultPolicy,
    );
    final referencedSummary = FinancialSummary.calculate(
      transactions: [referenced],
      referenceDate: DateTime(2026, 7, 24),
      tithePolicy: TithePolicy.defaultPolicy,
    );
    expect(referencedSummary.recordedBalance, baselineSummary.recordedBalance);
    expect(referencedSummary.monthlyTithe, baselineSummary.monthlyTithe);
  });
}
