import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_relation_type.dart';
import '../entities/account.dart';

class AccountBalanceCalculator {
  const AccountBalanceCalculator._();

  static int calculate({
    required Account account,
    required Iterable<Transaction> transactions,
  }) {
    var balance = account.hasOpeningBalance ? account.openingBalance : 0;

    for (final transaction in transactions) {
      if (!_belongsTo(account, transaction) ||
          transaction.deletedAt != null ||
          !_isOnOrAfterOpeningDate(account, transaction.date)) {
        continue;
      }

      balance += cashEffect(transaction);
    }

    return balance;
  }

  static int cashEffect(Transaction transaction) {
    if (transaction.deletedAt != null) return 0;

    switch (transaction.type) {
      case TransactionType.income:
        return transaction.amount;
      case TransactionType.expense:
        return -transaction.amount;
      case TransactionType.transfer:
        // The legacy transfer record does not identify both sides or direction.
        return 0;
      case TransactionType.assetConversion:
        if (transaction.relationType ==
            TransactionRelationType.assetFeeExpense) {
          return 0;
        }
        switch (transaction.assetAction) {
          case AssetAction.buy:
            final capitalizedFee =
                transaction.feeTreatment ==
                    AssetFeeTreatment.capitalizeIntoCostBasis
                ? transaction.feeAmount
                : 0;
            return -(transaction.amount + capitalizedFee);
          case AssetAction.sell:
            final deductedFee =
                transaction.feeTreatment ==
                    AssetFeeTreatment.deductFromSaleProceeds
                ? transaction.feeAmount
                : 0;
            return transaction.amount - deductedFee;
          case null:
            return 0;
        }
    }
  }

  static bool hasTransactionsBeforeOpeningDate({
    required Account account,
    required Iterable<Transaction> transactions,
    DateTime? openingBalanceDate,
  }) {
    final effectiveDate = openingBalanceDate ?? account.openingBalanceDate;
    if (effectiveDate == null) return false;
    final localStart = _localDate(effectiveDate);

    return transactions.any(
      (transaction) =>
          transaction.deletedAt == null &&
          _belongsTo(account, transaction) &&
          _localDate(transaction.date).isBefore(localStart),
    );
  }

  static bool _belongsTo(Account account, Transaction transaction) {
    return transaction.account.trim().toLowerCase() ==
        account.name.trim().toLowerCase();
  }

  static bool _isOnOrAfterOpeningDate(Account account, DateTime date) {
    final effectiveDate = account.openingBalanceDate;
    if (effectiveDate == null) return true;
    return !_localDate(date).isBefore(_localDate(effectiveDate));
  }

  static DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
