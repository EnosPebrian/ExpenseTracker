import '../../../transactions/domain/entities/transaction.dart';

/// Shared identity and ordering rules for measurable-asset transactions.
class AssetTransactionIdentity {
  const AssetTransactionIdentity._();

  static String key(Transaction transaction) {
    final definitionId = transaction.assetDefinitionId?.trim();

    if (definitionId != null && definitionId.isNotEmpty) {
      return 'definition:${_normalize(definitionId)}';
    }

    final symbol = transaction.assetSymbol?.trim();
    final unit = _normalize(transaction.unit ?? 'unit');

    if (symbol != null && symbol.isNotEmpty) {
      return 'legacy:symbol:${_normalize(symbol)}:$unit';
    }

    return 'legacy:name:${_normalize(resolveAssetName(transaction))}:$unit';
  }

  static AssetAction resolveAction(Transaction transaction) {
    final storedAction = transaction.assetAction;

    if (storedAction != null) {
      return storedAction;
    }

    final normalizedTitle = transaction.title.toLowerCase();

    if (normalizedTitle.contains('sale') || normalizedTitle.contains('sell')) {
      return AssetAction.sell;
    }

    return AssetAction.buy;
  }

  static String resolveAssetName(Transaction transaction) {
    final storedName = transaction.assetName?.trim();

    if (storedName != null && storedName.isNotEmpty) {
      return storedName;
    }

    final accountParts = transaction.account
        .split('->')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (accountParts.length >= 2) {
      return resolveAction(transaction) == AssetAction.sell
          ? accountParts.first
          : accountParts.last;
    }

    return transaction.title.trim();
  }

  static int compareChronologically(Transaction left, Transaction right) {
    final dateComparison = left.date.compareTo(right.date);

    if (dateComparison != 0) {
      return dateComparison;
    }

    return left.createdAt.compareTo(right.createdAt);
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
