import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/investments/domain/entities/brokerage_settlement.dart';
import 'package:pilgrim_tracker/features/investments/domain/services/settlement_reconciliation_service.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_brokerage_metadata.dart';

final account = Account(
  id: 'broker',
  bookId: 'book',
  name: 'Broker',
  accountType: AccountType.brokerage,
  currencyCode: 'IDR',
);
final date = DateTime(2026, 9, 15);
BrokerageSettlement evidence(String id) => BrokerageSettlement(
  id: id,
  bookId: 'book',
  brokerageAccountId: 'broker',
  date: date,
  type: BrokerageSettlementType.buySettlement,
  amount: 200,
  currencyCode: 'IDR',
  sourceFingerprint: 'source',
  sourceRowIdentity: id,
  sourceRowFingerprint: 'row',
  reference: 'ref',
  note: 'original note',
  createdAt: date,
  updatedAt: date,
);
Transaction trade(String id) => Transaction(
  id: id,
  bookId: 'book',
  title: 'Buy',
  category: '',
  account: 'Broker',
  date: date,
  amount: 100,
  type: TransactionType.assetConversion,
  brokerageAccountId: 'broker',
  brokerageActivityType: BrokerageActivityType.buy,
);

void main() {
  test('unmatched source evidence round trips all preserved fields', () {
    final source = evidence('one');
    final restored = BrokerageSettlement.fromRecord(source.toRecord());
    expect(restored.toRecord(), source.toRecord());
    expect(restored.state, 'unmatched');
    expect(restored.tradeIds, isEmpty);
  });
  test('many-to-many reviewed links leave underlying trades unchanged', () {
    final a = trade('a');
    final b = trade('b');
    final before = [a.toRecord(), b.toRecord()];
    final first = evidence(
      'one',
    ).reconcile([a, b], account: account, reviewedAt: date);
    final second = evidence(
      'two',
    ).reconcile([a], account: account, reviewedAt: date);
    expect(first.tradeIds, {'a', 'b'});
    expect(second.tradeIds, {'a'});
    expect(first.state, 'reconciled');
    expect(first.id, 'one');
    expect([a.toRecord(), b.toRecord()], before);
    expect(
      first.reconcile([], account: account, reviewedAt: date).state,
      'unmatched',
    );
  });
  test('foreign, wrong direction and deleted trades cannot reconcile', () {
    for (final invalid in [
      trade('a').copyWith(bookId: 'foreign'),
      trade('a').copyWith(brokerageActivityType: BrokerageActivityType.sell),
      trade('a').copyWith(deletedAt: date),
    ]) {
      expect(
        () => evidence(
          'one',
        ).reconcile([invalid], account: account, reviewedAt: date),
        throwsStateError,
      );
    }
  });
  test('ambiguous suggestions remain unmatched without side effects', () {
    final source = evidence('one');
    final candidates = const SettlementReconciliationService().candidates(
      evidence: source,
      account: account,
      trades: [trade('b'), trade('a')],
    );
    expect(candidates.map((t) => t.id), ['a', 'b']);
    expect(source.state, 'unmatched');
    expect(source.version, 1);
  });
  test('settlement aliases are explicit and interest is not a settlement', () {
    expect(
      BrokerageSettlementType.parse(' buy_settlement '),
      BrokerageSettlementType.buySettlement,
    );
    expect(
      BrokerageSettlementType.parse('SELL SETTLEMENT'),
      BrokerageSettlementType.sellSettlement,
    );
    expect(BrokerageSettlementType.parse('INTEREST'), isNull);
  });
}
