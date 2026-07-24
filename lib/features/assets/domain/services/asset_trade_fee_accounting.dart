import '../../../transactions/domain/entities/transaction.dart';

class AssetTradeFeeAccounting {
  const AssetTradeFeeAccounting._();

  static int buyCostContribution(Transaction transaction) {
    return transaction.amount +
        (transaction.feeTreatment == AssetFeeTreatment.capitalizeIntoCostBasis
            ? transaction.feeAmount
            : 0);
  }

  static int netSaleProceeds(Transaction transaction) {
    return transaction.amount -
        (transaction.feeTreatment == AssetFeeTreatment.deductFromSaleProceeds
            ? transaction.feeAmount
            : 0);
  }

  static int settlementAmount(Transaction transaction) {
    if (transaction.feeTreatment == AssetFeeTreatment.none) {
      return transaction.amount;
    }

    return transaction.assetAction == AssetAction.sell
        ? transaction.amount - transaction.feeAmount
        : transaction.amount + transaction.feeAmount;
  }
}
