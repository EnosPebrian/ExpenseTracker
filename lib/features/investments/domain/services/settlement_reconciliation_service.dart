import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../entities/brokerage_settlement.dart';

/// Suggestions only. Even a unique candidate requires explicit review.
class SettlementReconciliationService {
  const SettlementReconciliationService();

  List<Transaction> candidates({
    required BrokerageSettlement evidence,
    required Account account,
    required Iterable<Transaction> trades,
    int windowDays = 7,
  }) {
    if (windowDays < 0) throw ArgumentError.value(windowDays, 'windowDays');
    final result = trades.where((trade) {
      if (!evidence.isCompatibleTrade(trade, account)) return false;
      final settlementDay = DateTime.utc(
        evidence.date.year,
        evidence.date.month,
        evidence.date.day,
      );
      final tradeDay = DateTime.utc(
        trade.date.year,
        trade.date.month,
        trade.date.day,
      );
      final days = settlementDay.difference(tradeDay).inDays;
      return days >= 0 && days <= windowDays;
    }).toList();
    result.sort((left, right) {
      final leftReference =
          evidence.reference.isNotEmpty && evidence.reference == left.reference;
      final rightReference =
          evidence.reference.isNotEmpty &&
          evidence.reference == right.reference;
      if (leftReference != rightReference) return leftReference ? -1 : 1;
      final leftAmount = evidence.amount == left.amount;
      final rightAmount = evidence.amount == right.amount;
      if (leftAmount != rightAmount) return leftAmount ? -1 : 1;
      final date = left.date.compareTo(right.date);
      return date != 0 ? date : left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }
}
