enum TransactionRelationType {
  none,
  assetFeeExpense;

  static TransactionRelationType fromStoredValue(String? value) {
    for (final type in values) {
      if (type.name == value) {
        return type;
      }
    }

    return none;
  }
}

const managedAssetFeeExpenseMessage =
    'This expense is managed from its asset transaction.';
