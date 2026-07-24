import '../../../transactions/domain/entities/transaction.dart';
import '../entities/asset_definition.dart';
import 'asset_numeric_policy.dart';
import 'asset_portfolio_calculator.dart';

enum AssetDefinitionProtectedField {
  general,
  kind,
  symbol,
  exchangeCode,
  currencyCode,
  unit,
  lotSize,
}

class AssetDefinitionEditIssue {
  const AssetDefinitionEditIssue({required this.field, required this.message});

  final AssetDefinitionProtectedField field;
  final String message;
}

class AssetDefinitionEditResult {
  const AssetDefinitionEditResult(this.issues);

  final List<AssetDefinitionEditIssue> issues;

  bool get isValid => issues.isEmpty;
  AssetDefinitionEditIssue? get firstIssue => issues.firstOrNull;

  String? errorFor(AssetDefinitionProtectedField field) {
    for (final issue in issues) {
      if (issue.field == field) return issue.message;
    }
    return null;
  }
}

class AssetDefinitionUsageResult {
  const AssetDefinitionUsageResult({
    required this.hasLinkedTransactions,
    required this.linkedTransactionCount,
    required this.activeTransactionCount,
    required this.openQuantity,
    required this.hasOpenPosition,
    required this.canArchive,
    required this.canEditIdentity,
    required this.blockingReason,
  });

  final bool hasLinkedTransactions;
  final int linkedTransactionCount;
  final int activeTransactionCount;
  final double openQuantity;
  final bool hasOpenPosition;
  final bool canArchive;
  final bool canEditIdentity;
  final String? blockingReason;
}

class AssetDefinitionUsagePolicy {
  const AssetDefinitionUsagePolicy();

  AssetDefinitionUsageResult analyze({
    required AssetDefinition definition,
    required Iterable<Transaction> transactions,
  }) {
    final definitionId = definition.id.trim();
    final linked = transactions
        .where((transaction) {
          return transaction.type == TransactionType.assetConversion &&
              transaction.assetDefinitionId?.trim() == definitionId;
        })
        .toList(growable: false);
    final active = linked
        .where((transaction) => transaction.deletedAt == null)
        .toList(growable: false);
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: active,
      assetDefinitions: [definition],
    );
    var openQuantity = 0.0;
    for (final holding in portfolio.holdings) {
      if (holding.assetDefinitionId == definition.id) {
        openQuantity = holding.quantity;
        break;
      }
    }
    openQuantity = AssetNumericPolicy.normalizeQuantity(
      openQuantity,
      definition.kind,
    );
    final hasOpenPosition = !AssetNumericPolicy.isEffectivelyZero(
      openQuantity,
      definition.kind,
    );
    final canArchive = !definition.isDeleted && !hasOpenPosition;

    return AssetDefinitionUsageResult(
      hasLinkedTransactions: linked.isNotEmpty,
      linkedTransactionCount: linked.length,
      activeTransactionCount: active.length,
      openQuantity: openQuantity,
      hasOpenPosition: hasOpenPosition,
      canArchive: canArchive,
      canEditIdentity: !definition.isDeleted && linked.isEmpty,
      blockingReason: definition.isDeleted
          ? 'This asset is already archived.'
          : hasOpenPosition
          ? 'Close the open holding before archiving this asset.'
          : null,
    );
  }

  AssetDefinitionEditResult validateEdit({
    required AssetDefinition existing,
    required AssetDefinition candidate,
    required AssetDefinitionUsageResult usage,
  }) {
    if (existing.isDeleted) {
      return const AssetDefinitionEditResult([
        AssetDefinitionEditIssue(
          field: AssetDefinitionProtectedField.general,
          message: 'Restore this asset before editing it.',
        ),
      ]);
    }
    if (!usage.hasLinkedTransactions) {
      return const AssetDefinitionEditResult([]);
    }

    final issues = <AssetDefinitionEditIssue>[];
    if (existing.kind != candidate.kind) {
      _add(issues, AssetDefinitionProtectedField.kind, 'Asset kind');
    }
    if (existing.normalizedSymbol != candidate.normalizedSymbol) {
      _add(issues, AssetDefinitionProtectedField.symbol, 'Symbol');
    }
    if (existing.normalizedExchangeCode != candidate.normalizedExchangeCode) {
      _add(issues, AssetDefinitionProtectedField.exchangeCode, 'Exchange');
    }
    if (existing.normalizedCurrencyCode != candidate.normalizedCurrencyCode) {
      _add(issues, AssetDefinitionProtectedField.currencyCode, 'Currency');
    }
    if (existing.normalizedUnit != candidate.normalizedUnit) {
      _add(issues, AssetDefinitionProtectedField.unit, 'Unit');
    }
    if (existing.lotSize != candidate.lotSize) {
      _add(issues, AssetDefinitionProtectedField.lotSize, 'Lot size');
    }

    return AssetDefinitionEditResult(List.unmodifiable(issues));
  }

  static void _add(
    List<AssetDefinitionEditIssue> issues,
    AssetDefinitionProtectedField field,
    String label,
  ) {
    issues.add(
      AssetDefinitionEditIssue(
        field: field,
        message:
            '$label cannot be changed because this asset is already used by '
            'transactions. Create a new asset definition instead.',
      ),
    );
  }
}
