enum BrokerageActivityType {
  buy,
  sell,
  dividend,
  fee,
  tax,
  deposit,
  withdrawal,
  split;

  String get label => switch (this) {
    BrokerageActivityType.buy => 'Buy',
    BrokerageActivityType.sell => 'Sell',
    BrokerageActivityType.dividend => 'Dividend',
    BrokerageActivityType.fee => 'Fee',
    BrokerageActivityType.tax => 'Tax',
    BrokerageActivityType.deposit => 'Deposit',
    BrokerageActivityType.withdrawal => 'Withdrawal',
    BrokerageActivityType.split => 'Split',
  };

  static BrokerageActivityType? fromStoredValue(Object? value) {
    if (value is! String) return null;
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

class TransactionBrokerageMetadataPolicy {
  const TransactionBrokerageMetadataPolicy._();

  static String? validationMessage({
    required String? brokerageAccountId,
    required BrokerageActivityType? activityType,
    required int? splitNumerator,
    required int? splitDenominator,
  }) {
    final normalizedAccountId = brokerageAccountId?.trim();
    final hasAccount =
        normalizedAccountId != null && normalizedAccountId.isNotEmpty;
    final hasActivity = activityType != null;
    if (hasAccount != hasActivity) {
      return 'Brokerage account and activity type must be provided together.';
    }

    final hasSplitRatio = splitNumerator != null || splitDenominator != null;
    if (activityType != BrokerageActivityType.split) {
      if (hasSplitRatio) {
        return 'A split ratio is supported only for a split activity.';
      }
      return null;
    }

    if (splitNumerator == null ||
        splitNumerator <= 0 ||
        splitDenominator == null ||
        splitDenominator <= 0) {
      return 'Enter a valid positive split ratio.';
    }
    return null;
  }
}
