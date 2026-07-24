import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';

void main() {
  test('execution reference defaults are backward compatible', () {
    final transaction = Transaction(
      title: 'Legacy expense',
      category: 'General',
      account: 'Cash',
      date: DateTime(2026, 7, 1),
      amount: 1000,
      type: TransactionType.expense,
    );
    expect(transaction.marketReferenceUnitPrice, isNull);
    expect(transaction.marketReferenceSource, isNull);
  });

  test(
    'execution reference mapping, clearing, and unknown source are stable',
    () {
      final quotedAt = DateTime.utc(2026, 7, 24, 8);
      final transaction = Transaction(
        title: 'USD acquisition',
        category: 'Asset conversion',
        account: 'Cash -> USD',
        date: quotedAt,
        amount: 16300000,
        type: TransactionType.assetConversion,
        quantity: 1000,
        unit: 'usd',
        unitPrice: 16300,
        assetAction: AssetAction.buy,
        marketReferenceUnitPrice: 16250,
        marketReferenceCurrencyCode: 'IDR',
        marketReferenceUnit: 'usd',
        marketReferenceSource: AssetMarketReferenceSource.cachedQuote,
        marketReferenceQuotedAt: quotedAt,
      );
      final restored = Transaction.fromRecord(transaction.toRecord());
      expect(transaction.toRecord()['market_reference_source'], 'cached_quote');
      expect(restored.marketReferenceUnitPrice, 16250);
      expect(
        restored.marketReferenceSource,
        AssetMarketReferenceSource.cachedQuote,
      );
      expect(
        restored.marketReferenceQuotedAt?.millisecondsSinceEpoch,
        quotedAt.millisecondsSinceEpoch,
      );

      final cleared = restored.copyWith(
        marketReferenceUnitPrice: null,
        marketReferenceCurrencyCode: null,
        marketReferenceUnit: null,
        marketReferenceSource: null,
        marketReferenceQuotedAt: null,
      );
      expect(cleared.marketReferenceUnitPrice, isNull);
      expect(cleared.marketReferenceSource, isNull);

      final unknownRecord = Map<String, Object?>.of(transaction.toRecord())
        ..['market_reference_source'] = 'future_source';
      expect(
        Transaction.fromRecord(unknownRecord).marketReferenceSource,
        AssetMarketReferenceSource.unknown,
      );
    },
  );
  test('transaction relation defaults are backward compatible', () {
    final transaction = Transaction(
      title: 'Legacy expense',
      category: 'General',
      account: 'Cash',
      date: DateTime(2026, 7, 1),
      amount: 1000,
      type: TransactionType.expense,
    );

    expect(transaction.relatedTransactionId, isNull);
    expect(transaction.relationType, TransactionRelationType.none);
  });

  test('relation mapping, copyWith, and unknown fallback are stable', () {
    final child = Transaction(
      title: 'Fee - Buy USD',
      category: 'Asset Fees',
      account: 'Cash',
      date: DateTime(2026, 7, 1),
      amount: 100000,
      type: TransactionType.expense,
      relatedTransactionId: 'parent-id',
      relationType: TransactionRelationType.assetFeeExpense,
    );

    final restored = Transaction.fromRecord(child.toRecord());
    final cleared = restored.copyWith(
      relatedTransactionId: null,
      relationType: TransactionRelationType.none,
    );
    final unknownRecord = Map<String, Object?>.of(child.toRecord())
      ..['relation_type'] = 'futureRelation';

    expect(restored.relatedTransactionId, 'parent-id');
    expect(restored.relationType, TransactionRelationType.assetFeeExpense);
    expect(cleared.relatedTransactionId, isNull);
    expect(cleared.relationType, TransactionRelationType.none);
    expect(
      Transaction.fromRecord(unknownRecord).relationType,
      TransactionRelationType.none,
    );
  });

  test('asset fee defaults are backward compatible', () {
    final transaction = Transaction(
      title: 'Legacy asset trade',
      category: 'Asset conversion',
      account: 'Cash -> Gold',
      date: DateTime(2026, 7, 1),
      amount: 1000000,
      type: TransactionType.assetConversion,
    );

    expect(transaction.feeAmount, 0);
    expect(transaction.feeTreatment, AssetFeeTreatment.none);
  });

  test('copyWith can explicitly clear nullable transaction fields', () {
    final transaction = Transaction(
      projectId: 'life',
      title: 'Gold acquisition',
      category: 'Asset conversion',
      account: 'Cash Enos -> Gold Holdings',
      date: DateTime(2026, 7, 19),
      amount: 50000000,
      type: TransactionType.assetConversion,
      quantity: 20,
      unit: 'gram',
      unitPrice: 2500000,
      assetDefinitionId: 'asset-gold',
      deletedAt: DateTime(2026, 7, 20),
    );

    final cleared = transaction.copyWith(
      projectId: null,
      quantity: null,
      unit: null,
      unitPrice: null,
      deletedAt: null,
      assetDefinitionId: null,
    );

    expect(cleared.projectId, isNull);
    expect(cleared.quantity, isNull);
    expect(cleared.unit, isNull);
    expect(cleared.unitPrice, isNull);
    expect(cleared.deletedAt, isNull);
    expect(cleared.assetDefinitionId, isNull);
  });

  test('copyWith preserves nullable fields when they are omitted', () {
    final deletedAt = DateTime(2026, 7, 20);

    final transaction = Transaction(
      projectId: 'life',
      title: 'Gold acquisition',
      category: 'Asset conversion',
      account: 'Cash Enos -> Gold Holdings',
      date: DateTime(2026, 7, 19),
      amount: 50000000,
      type: TransactionType.assetConversion,
      quantity: 20,
      unit: 'gram',
      unitPrice: 2500000,
      assetDefinitionId: 'asset-gold',
      deletedAt: deletedAt,
    );

    final updated = transaction.copyWith(title: 'Updated title');

    expect(updated.projectId, 'life');
    expect(updated.quantity, 20);
    expect(updated.unit, 'gram');
    expect(updated.unitPrice, 2500000);
    expect(updated.deletedAt, deletedAt);
    expect(updated.assetDefinitionId, 'asset-gold');
  });

  test('record mapping preserves asset definition identity and snapshots', () {
    final timestamp = DateTime.utc(2026, 7, 22, 10, 30);

    final transaction = Transaction(
      id: 'transaction-bbca',
      projectId: 'investment',
      title: 'BBCA acquisition',
      category: 'Asset conversion',
      account: 'Cash Enos -> Bank Central Asia (BBCA)',
      date: timestamp,
      amount: 1000000,
      type: TransactionType.assetConversion,
      quantity: 100,
      unit: 'share',
      unitPrice: 10000,
      assetDefinitionId: 'asset-bbca',
      assetName: 'Bank Central Asia',
      assetSymbol: 'BBCA',
      assetAction: AssetAction.buy,
      feeAmount: 25000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final record = transaction.toRecord();

    expect(record['asset_definition_id'], 'asset-bbca');
    expect(record['asset_name'], 'Bank Central Asia');
    expect(record['asset_symbol'], 'BBCA');
    expect(record['asset_action'], 'buy');
    expect(record['fee_amount'], 25000);
    expect(record['fee_treatment'], 'capitalizeIntoCostBasis');

    final restored = Transaction.fromRecord(record);

    expect(restored.assetDefinitionId, 'asset-bbca');
    expect(restored.assetName, 'Bank Central Asia');
    expect(restored.assetSymbol, 'BBCA');
    expect(restored.assetAction, AssetAction.buy);
    expect(restored.feeAmount, 25000);
    expect(restored.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(restored.quantity, 100);
    expect(restored.unit, 'share');
  });

  test('copyWith preserves fee data and zero normalizes treatment', () {
    final transaction = Transaction(
      title: 'USD acquisition',
      category: 'Asset conversion',
      account: 'Cash -> USD',
      date: DateTime(2026, 7, 1),
      amount: 16200000,
      type: TransactionType.assetConversion,
      feeAmount: 100000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
    );

    final copied = transaction.copyWith(title: 'Copied');
    final cleared = transaction.copyWith(feeAmount: 0);

    expect(copied.feeAmount, 100000);
    expect(copied.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(cleared.feeAmount, 0);
    expect(cleared.feeTreatment, AssetFeeTreatment.none);
  });

  test('unknown persisted fee treatment safely falls back to none', () {
    final timestamp = DateTime.utc(2026, 7, 1);
    final record = Transaction(
      id: 'unknown-fee-treatment',
      title: 'USD acquisition',
      category: 'Asset conversion',
      account: 'Cash -> USD',
      date: timestamp,
      amount: 16200000,
      type: TransactionType.assetConversion,
      feeAmount: 100000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      createdAt: timestamp,
      updatedAt: timestamp,
    ).toRecord()..['fee_treatment'] = 'futureTreatment';

    final restored = Transaction.fromRecord(record);

    expect(restored.feeAmount, 100000);
    expect(restored.feeTreatment, AssetFeeTreatment.none);
  });
}
