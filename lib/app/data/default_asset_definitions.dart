import '../../features/assets/domain/entities/asset_definition.dart';
import '../../features/assets/domain/entities/asset_kind.dart';
import '../../core/master_data/default_asset_definition_ids.dart';

List<AssetDefinition> buildDefaultAssetDefinitions({
  DateTime? timestamp,
  String deviceId = 'local-device',
}) {
  final now = (timestamp ?? DateTime.now()).toUtc();

  return [
    AssetDefinition(
      id: defaultGoldHoldingsAssetId,
      displayName: 'Gold Holdings',
      kind: AssetKind.gold,
      symbol: null,
      providerCode: 'alpha_vantage',
      providerSymbol: 'XAU',
      exchangeCode: null,
      currencyCode: 'IDR',
      unit: 'gram',
      lotSize: 1,
      onlinePricingEnabled: true,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: deviceId,
      syncStatus: 'local_only',
    ),
    AssetDefinition(
      id: defaultBitcoinWalletAssetId,
      displayName: 'Bitcoin Wallet',
      kind: AssetKind.crypto,
      symbol: 'BTC',
      providerCode: null,
      providerSymbol: null,
      exchangeCode: null,
      currencyCode: 'IDR',
      unit: 'btc',
      lotSize: 1,
      onlinePricingEnabled: false,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: deviceId,
      syncStatus: 'local_only',
    ),
    AssetDefinition(
      id: defaultInventoryAssetId,
      displayName: 'Inventory',
      kind: AssetKind.inventory,
      symbol: null,
      providerCode: null,
      providerSymbol: null,
      exchangeCode: null,
      currencyCode: 'IDR',
      unit: 'unit',
      lotSize: 1,
      onlinePricingEnabled: false,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: deviceId,
      syncStatus: 'local_only',
    ),
    _buildDefaultForeignCurrency(
      id: defaultUsdAssetId,
      displayName: 'US Dollar Cash',
      symbol: 'USD',
      timestamp: now,
      deviceId: deviceId,
    ),
    _buildDefaultForeignCurrency(
      id: defaultSgdAssetId,
      displayName: 'Singapore Dollar Cash',
      symbol: 'SGD',
      timestamp: now,
      deviceId: deviceId,
    ),
  ];
}

AssetDefinition _buildDefaultForeignCurrency({
  required String id,
  required String displayName,
  required String symbol,
  required DateTime timestamp,
  required String deviceId,
}) {
  final normalizedSymbol = symbol.trim().toUpperCase();

  return AssetDefinition(
    id: id,
    displayName: displayName,
    kind: AssetKind.foreignCurrency,
    symbol: normalizedSymbol,
    providerCode: 'alpha_vantage',
    providerSymbol: '$normalizedSymbol/IDR',
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: normalizedSymbol.toLowerCase(),
    lotSize: 1,
    onlinePricingEnabled: true,
    createdAt: timestamp,
    updatedAt: timestamp,
    deletedAt: null,
    version: 1,
    deviceId: deviceId,
    syncStatus: 'local_only',
  );
}
