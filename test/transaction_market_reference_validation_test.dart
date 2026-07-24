import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

void main() {
  test('validates reference price, IDR currency, and matching unit', () {
    final valid = _trade();
    expect(() => validateTransaction(valid), returnsNormally);

    for (final invalid in [
      valid.copyWith(marketReferenceUnitPrice: 0),
      valid.copyWith(marketReferenceUnitPrice: -1),
      valid.copyWith(marketReferenceCurrencyCode: 'USD'),
      valid.copyWith(marketReferenceUnit: 'sgd'),
    ]) {
      expect(
        () => validateTransaction(invalid),
        throwsA(isA<TransactionValidationException>()),
      );
    }
  });

  test('ordinary transaction cannot persist execution reference metadata', () {
    final ordinary = Transaction(
      title: 'Salary',
      category: 'Salary',
      account: 'Bank',
      date: DateTime.utc(2026, 7, 24),
      amount: 1000000,
      type: TransactionType.income,
      marketReferenceUnitPrice: 100,
      marketReferenceCurrencyCode: 'IDR',
      marketReferenceUnit: 'unit',
      marketReferenceSource: AssetMarketReferenceSource.manual,
      marketReferenceQuotedAt: DateTime.utc(2026, 7, 24),
    );
    expect(
      () => validateTransaction(ordinary),
      throwsA(isA<TransactionValidationException>()),
    );
  });
}

Transaction _trade() => Transaction(
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
  marketReferenceUnitPrice: 16250,
  marketReferenceCurrencyCode: 'IDR',
  marketReferenceUnit: 'usd',
  marketReferenceSource: AssetMarketReferenceSource.manual,
  marketReferenceQuotedAt: DateTime.utc(2026, 7, 24, 8),
);
