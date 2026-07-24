import '../entities/asset_definition.dart';
import '../entities/asset_market_price.dart';

class AssetMarketReferencePolicy {
  const AssetMarketReferencePolicy();

  bool isCompatible({
    required AssetDefinition definition,
    required AssetMarketPrice price,
  }) {
    return price.roundedPrice > 0 &&
        price.assetKey.trim().toLowerCase() ==
            definition.marketPriceKey.trim().toLowerCase() &&
        price.currencyCode.trim().toUpperCase() ==
            definition.normalizedCurrencyCode &&
        price.unit.trim().toLowerCase() == definition.normalizedUnit;
  }

  AssetMarketPrice? latestCompatible({
    required AssetDefinition definition,
    required Iterable<AssetMarketPrice> prices,
  }) {
    final compatible =
        prices
            .where(
              (price) => isCompatible(definition: definition, price: price),
            )
            .toList()
          ..sort((left, right) => right.quotedAt.compareTo(left.quotedAt));
    return compatible.firstOrNull;
  }
}
