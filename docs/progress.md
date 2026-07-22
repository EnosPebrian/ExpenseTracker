# Pilgrim Tracker Progress

**Snapshot date:** 2026-07-21

```text
flutter analyze
No issues found!

flutter test
93 tests passed
```

## Current application state

- Flutter shell runs on web preview, Android, and Windows targets.
- Navigation contains Overview, Assets, Transactions, Accounts, Categories, Asset Conversion, Projects, Tithe, and Reports.
- Overview is period-based and no longer carries detailed asset analytics.
- Assets is a dedicated portfolio destination.
- Transactions use repository/use-case/controller flow.
- Native storage uses SQLite version 5.
- Web uses a compatible in-memory preview store.
- Accounts, categories, and projects are seeded/manageable.
- Tithe summaries use an effective-date policy.

## Dashboard work completed

- Assets inserted after Overview.
- navigation tests updated
- Overview reduced to monthly balance, income, expenses, tithe, cash flow, spending, recent transactions, and activity
- detailed assets moved to Assets

## Asset transaction work completed

Transaction now supports:

```text
assetName
assetSymbol
assetAction
quantity
unit
unitPrice
```

- buy/sell actions are explicit
- stock ticker is required
- shares and grams are recorded
- SQLite v4 added asset name/action
- SQLite v5 added symbol and market-price cache
- legacy conversions remain calculable

## Market-price work completed

Added:

```text
AppEnvironment
MarketQuote
AssetSymbolMatch
AssetPriceRepository
AlphaVantageAssetPriceRepository
AssetMarketPrice
AssetPriceController
```

Capabilities:

- stock quote parsing
- symbol-search service
- gold spot retrieval
- USD/IDR and ounce/gram conversion
- provider/rate-limit errors
- injected HTTP client tests
- online and manual prices
- cached latest native prices
- source/status/date display
- no-key manual fallback

## Portfolio engine completed

Added:

```text
AssetPortfolio
AssetHolding
AssetKind
AssetPortfolioCalculator
```

Implemented:

- gold quantity
- stock shares/lots
- chronological processing
- weighted-average cost
- remaining cost basis
- partial sale
- realized/unrealized gains
- market value
- quote matching
- cost-basis fallback
- legacy support
- soft-delete filtering

## Assets UI completed

- portfolio value
- cost basis
- realized/unrealized gain
- holdings
- quantity/lots/shares
- average/current price
- market value and return
- online/manual refresh
- quote source/status/date
- provider error and empty states

## Current boundaries

- `AppShell` composes features.
- HTTP parsing stays in data implementation.
- quote retrieval uses a domain repository.
- portfolio math stays in a pure domain service.
- widgets render and trigger controller actions.
- native and web stores keep compatible methods.

## Known gaps

High priority:

- no persistent `AssetDefinition`
- lot size fixed at 100 for stocks
- stock online refresh assumes IDR
- provider symbol/exchange/currency not separately configured
- overselling not blocked before save
- fee treatment shown but not persisted/applied
- client API key unsuitable for public release

Medium priority:

- web storage is in-memory
- latest quote only, no history
- symbol-search has no UI
- no refresh-age/rate-limit policy
- no complete net worth with cash/liabilities
- no market-value allocation chart
- no safe ticker-correction flow

Planned migrations:

- Drift
- Riverpod
- GoRouter
- ledger entries
- revisions
- sync queue
- persistent tithe entities

## Next implementation

Add persistent `AssetDefinition` with:

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

Then migrate v5 safely, seed defaults, integrate conversion selection, use configured lot/currency, reject quote-currency mismatch, add oversell validation/fees, and preserve all 93 tests.
