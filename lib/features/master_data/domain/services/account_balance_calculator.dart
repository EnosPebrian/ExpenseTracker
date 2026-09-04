import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_relation_type.dart';
import '../entities/account.dart';

class AccountBalanceCalculator {
  const AccountBalanceCalculator._();

  static int calculate({
    required Account account,
    required Iterable<Transaction> transactions,
  }) => calculateAsOf(account: account, transactions: transactions);

  /// Calculates the account balance immediately before [endExclusive].
  ///
  /// A null boundary preserves the existing current-balance behavior.
  static int calculateAsOf({
    required Account account,
    required Iterable<Transaction> transactions,
    DateTime? endExclusive,
  }) {
    final openingDate = account.openingBalanceDate;
    final includeOpening =
        openingDate != null &&
        (endExclusive == null ||
            _localDate(openingDate).isBefore(_localDate(endExclusive)));
    var balance = includeOpening ? account.openingBalance : 0;

    for (final transaction in transactions) {
      if (!belongsToAccount(account, transaction) ||
          transaction.deletedAt != null ||
          (endExclusive != null && !transaction.date.isBefore(endExclusive)) ||
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
          belongsToAccount(account, transaction) &&
          _localDate(transaction.date).isBefore(localStart),
    );
  }

  static bool belongsToAccount(Account account, Transaction transaction) {
    final recordedAccount = transaction.account.trim();
    var cashAccount = recordedAccount;
    if (transaction.type == TransactionType.assetConversion) {
      final route = recordedAccount.split('->');
      if (route.length == 2) {
        cashAccount = switch (transaction.assetAction) {
          AssetAction.buy => route.first.trim(),
          AssetAction.sell => route.last.trim(),
          null => recordedAccount,
        };
      }
    }
    return cashAccount.toLowerCase() == account.name.trim().toLowerCase();
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
