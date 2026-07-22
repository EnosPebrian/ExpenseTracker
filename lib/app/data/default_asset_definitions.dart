import '../../features/assets/domain/entities/asset_definition.dart';
import '../../features/assets/domain/entities/asset_kind.dart';

List<AssetDefinition> buildDefaultAssetDefinitions({
  DateTime? timestamp,
  String deviceId = 'local-device',
}) {
  final now = (timestamp ?? DateTime.now()).toUtc();

  return [
    AssetDefinition(
      id: 'asset-gold-holdings',
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
      id: 'asset-bitcoin-wallet',
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
      id: 'asset-inventory',
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
  ];
}
