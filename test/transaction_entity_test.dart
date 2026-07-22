import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
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
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final record = transaction.toRecord();

    expect(record['asset_definition_id'], 'asset-bbca');
    expect(record['asset_name'], 'Bank Central Asia');
    expect(record['asset_symbol'], 'BBCA');
    expect(record['asset_action'], 'buy');

    final restored = Transaction.fromRecord(record);

    expect(restored.assetDefinitionId, 'asset-bbca');
    expect(restored.assetName, 'Bank Central Asia');
    expect(restored.assetSymbol, 'BBCA');
    expect(restored.assetAction, AssetAction.buy);
    expect(restored.quantity, 100);
    expect(restored.unit, 'share');
  });
}
