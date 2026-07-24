import '../entities/asset_definition.dart';
import 'asset_definition_usage_policy.dart';

class AssetDefinitionRetirementPolicy {
  const AssetDefinitionRetirementPolicy();

  static const retiredStockPortfolioId = 'asset-stock-portfolio';

  static const restoreBlockedMessage =
      'This legacy system definition has been retired and cannot be restored.';

  static const editBlockedMessage =
      'This legacy system definition is read-only. Create a concrete stock '
      'definition for future trades.';

  static const legacyPositionMessage =
      'This older generic stock definition has an open position. It can only '
      'be used to close the existing holding. Create a concrete stock '
      'definition for future purchases.';

  bool isRetiredSystemId(String? id) {
    return id?.trim() == retiredStockPortfolioId;
  }

  bool isRetiredSystemDefinition(AssetDefinition definition) {
    return isRetiredSystemId(definition.id);
  }

  bool shouldArchive(
    AssetDefinition definition,
    AssetDefinitionUsageResult usage,
  ) {
    return isRetiredSystemDefinition(definition) &&
        !definition.isDeleted &&
        !usage.hasOpenPosition;
  }

  bool canBuy(AssetDefinition definition) {
    return !definition.isDeleted && !isRetiredSystemDefinition(definition);
  }

  bool canSell(AssetDefinition definition, AssetDefinitionUsageResult usage) {
    if (definition.isDeleted) return false;
    if (!isRetiredSystemDefinition(definition)) return true;
    return usage.hasOpenPosition && usage.openQuantity > 0;
  }

  bool canRestore(AssetDefinition definition) {
    return !isRetiredSystemDefinition(definition);
  }

  bool canEdit(AssetDefinition definition) {
    return !isRetiredSystemDefinition(definition) && !definition.isDeleted;
  }
}
