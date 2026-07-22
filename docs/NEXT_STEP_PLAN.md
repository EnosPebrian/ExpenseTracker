# Pilgrim Tracker Next Step Plan

**Milestone:** Persistent asset definitions and currency-safe valuation

Do not combine this with Drift, Riverpod, GoRouter, synchronization, or dashboard chart work.

D9C Quote validation
D9D Cache dan manual-price consistency
D10 Foreign-currency asset model + FX pricing
D11 FX buy/sell, valuation, realized gain
D12 Oversell, fees, spread, rounding
D13 Asset-management finalization
D14 Regression, cleanup, documentation, release hardening

## Goal

Replace static asset-name assumptions with first-class definitions.

Examples:

```text
Gold Holdings
kind: gold
unit: gram
currency: IDR
provider symbol: XAU
lot size: 1
```

```text
BBCA
kind: stock
unit: share
currency: IDR
exchange: IDX
lot size: 100
```

```text
AAPL
kind: stock
unit: share
currency: USD
exchange: NASDAQ
lot size: 1
```

## Domain additions

Create:

```text
features/assets/domain/entities/asset_definition.dart
features/assets/domain/repositories/asset_definition_repository.dart
features/assets/data/repositories/local_asset_definition_repository.dart
features/assets/controllers/asset_definition_controller.dart
```

Fields:

```text
id
displayName
kind
symbol
providerCode
providerSymbol
exchangeCode
currencyCode
unit
lotSize
onlinePricingEnabled
createdAt
updatedAt
deletedAt
version
deviceId
syncStatus
```

Validation:

- display name, unit, currency required
- lot size positive
- stock symbol required for stock
- provider symbol required only for online pricing
- IDR and USD never silently mixed

## Persistence

Upgrade SQLite from version 5.

Add:

```text
getAssetDefinitions
upsertAssetDefinition
softDeleteAssetDefinition
ensureAssetDefinitionSeeds
```

to native and web stores.

Preserve old transactions and cached prices. Seed current groups without destructive rewriting.

## Transaction integration

Preferred direction:

```text
Transaction
  assetDefinitionId
  assetName snapshot
  assetSymbol snapshot
  assetAction
  quantity
  unit snapshot
  unitPrice
```

Keep existing snapshot fields during migration.

## Portfolio integration

Use definition lot size, unit, currency, symbol, and provider symbol. Keep calculations pure.

Tests:

- BBCA 1,000 shares / 100 = 10 lots
- AAPL lot size 1
- renamed definition keeps history readable
- missing definition falls back safely
- quote currency mismatch is rejected
- non-IDR stock does not use IDR assumptions

## UI

Add asset management:

- add/edit asset
- kind
- ticker/provider symbol
- exchange
- currency
- unit
- lot size
- online-pricing toggle

Asset Conversion selects a concrete definition.

## Acceptance checklist

- [ ] v5 upgrades without data loss
- [ ] definitions persist after restart
- [ ] web parity exists
- [ ] Gold, BBCA, and AAPL can differ
- [ ] lot size configurable
- [ ] quote currency mismatch blocked
- [ ] old conversions remain visible
- [ ] manual/online prices still work
- [ ] analyzer clean
- [ ] 93 existing tests preserved
- [ ] new tests pass
- [ ] docs updated

## Must wait

- price charts/history
- background refresh
- synchronization
- Drift/Riverpod/GoRouter
- full net worth
- dashboard chart
- OCR
