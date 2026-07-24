# Pilgrim Tracker Architecture

**Snapshot date:** 2026-07-21  
**Verified state:** Analyzer clean; 93 tests passing  
**Style:** Feature-first, local-first, layered, incrementally migrated

## 1. Non-negotiable principles

1. Local storage is the immediate source of truth.
2. Internet is optional for normal transactions.
3. Money uses integer values.
4. Quantity and money remain separate.
5. Presentation does not calculate portfolio accounting.
6. Domain code does not import Flutter UI.
7. Domain repositories are contracts; data implementations satisfy them.
8. Persisted changes require migrations and tests.
9. Project, asset, tithe, and sync metadata must be preserved.
10. Completed feature boundaries must not collapse into `AppShell`.

## 2. Current stack

```text
Flutter / Dart
SQLite via sqflite_common_ffi on native
Conditional LocalStore web fallback
ChangeNotifier controllers
Repository and use-case boundaries
UUID identifiers
package:http for market data
```

Transitional choices:

- ChangeNotifier while Riverpod is planned
- index-based shell navigation while GoRouter is planned
- direct SQLite store while Drift is planned
- in-memory web preview while persistent web storage is planned

Do not mix a broad framework migration into an unrelated feature batch.

## 3. Structure

```text
lib/
  app/
  core/
    config/
    database/
    design/
    shared/
  features/
    analytics/
    assets/
    dashboard/
    master_data/
    reports/
    tithe/
    transactions/
```

Dependency direction:

```text
presentation -> controller/application -> domain
data implementation -> domain contract
core infrastructure -> platform-specific services
```

## 4. AppShell boundary

`AppShell` is the current composition root. It may construct stores/controllers, bootstrap data, connect navigation, calculate page inputs, observe controllers, and dispose resources.

It must not perform HTTP parsing, calculate weighted-average cost, execute SQL directly, or duplicate feature business logic.

Current navigation indices:

```text
0 Overview
1 Assets
2 Transactions
3 Accounts
4 Categories
5 Asset Conversion
6 Projects
7 Tithe
8 Reports
```

## 5. Transaction feature

```text
features/transactions/
  data/repositories/
  domain/entities/
  domain/repositories/
  domain/usecases/
  presentation/controllers/
  presentation/edit/
  presentation/quick_add/
  presentation/screens/
  presentation/widgets/
```

The persisted transaction source for asset buys/sells contains:

```text
quantity
unit
unitPrice
assetName
assetSymbol
assetAction
feeAmount
feeTreatment
relatedTransactionId
relationType
```

New records must not depend on title/account parsing.

Asset trades using separate-expense fee treatment are coordinated in the
transaction use-case layer. The repository persists the parent and its managed
ordinary-expense child through one atomic change set. UI controllers never
orchestrate the two writes, and generated children cannot be independently
edited, duplicated, or deleted.

## 6. Assets feature

```text
features/assets/
  controllers/
    asset_conversion_controller.dart
    asset_price_controller.dart
  data/repositories/
    alpha_vantage_asset_price_repository.dart
  domain/entities/
    asset_market_price.dart
    asset_portfolio.dart
    asset_symbol_match.dart
    market_quote.dart
  domain/repositories/
    asset_price_repository.dart
  domain/services/
    asset_numeric_policy.dart
    asset_portfolio_calculator.dart
    asset_stock_lot_policy.dart
    asset_trade_validator.dart
  presentation/formatters/
    asset_quantity_formatter.dart
  presentation/screens/
    asset_conversion_screen.dart
    assets_dashboard_screen.dart
  presentation/widgets/
```

`AssetNumericPolicy` is the single pure-domain source for measurable asset
precision, new/edit quantity validation, deterministic integer unit-price
rounding, comparison tolerance, and near-zero normalization. Presentation uses
`AssetQuantityFormatter`, which applies the same policy while grouping digits
and trimming unnecessary zeroes. Historical over-precision `REAL` quantities
remain readable and calculable; the stricter policy applies only when a user
creates or edits an asset transaction.

`AssetStockLotPolicy` is the pure definition-driven source for stock lot rules.
Quantities continue to be shares; lots and odd-lot status are derived from the
linked definition's `lotSize`. `AssetTradeValidator` coordinates that policy
with chronological oversell validation. New and edited stock trades use the
quantity available at the candidate date, excluding the original edit record.
Historical odd-lot transactions remain readable, while cleanup sales may sell
whole lots or remove the odd residue to leave a whole-lot or zero balance.

`AssetDefinitionIntegrityPolicy` is the pure-domain validation boundary for new
and edited concrete asset definitions. It normalizes identity comparisons at
validation time without rewriting stored history. Stock identity is symbol plus
exchange, with a missing exchange treated as potentially conflicting; non-stock
definitions protect their established market-price identity. Online provider
code and symbol pairs are unique across asset kinds, and archived definitions
participate in all conflict checks. The controller applies the policy immediately
before persistence and during seed initialization. Archive/restore coordination
is provided by the D13B usage policy and controller lifecycle flow.

`AssetDefinitionUsagePolicy` derives definition lifecycle state from transaction
history. Links use only `assetDefinitionId`; snapshot names and symbols never
link concrete definitions. Soft-deleted asset conversions remain historical
links but do not affect open quantity, while generated fee expenses are ignored.
Open quantity reuses `AssetPortfolioCalculator` and D12D numeric normalization.
The controller blocks archiving open holdings, restores the same persisted row
only after D13A validation, and protects kind, symbol, exchange, currency, unit,
and lot size once any historical transaction is linked. Display name and online
provider configuration remain editable subject to integrity checks.

Asset catalog discovery is presentation-only. `AssetDefinitionCatalogQuery`
holds local search, lifecycle, kind, pricing, and sort state, while the pure
`AssetDefinitionCatalogFilter` derives a deterministic view without mutating
controller or repository state. `AssetDefinitionFormPresets` supplies
create-only suggestions and respects dirty fields; persistence validation still
flows through `AssetDefinitionController` and `AssetDefinitionIntegrityPolicy`.

Responsibilities:

- `AssetConversionController`: form state, validation, explicit buy/sell transaction creation
- `AssetDefinitionController`: save-time integrity coordination and field errors
- `AssetDefinitionIntegrityPolicy`: pure structural and identity conflict rules
- `AssetDefinitionUsagePolicy`: pure usage, archive eligibility, and linked-edit rules
- `AssetDefinitionCatalogFilter`: pure presentation catalog filtering and sorting
- `AssetDefinitionFormPresets`: create-only, dirty-field-aware form suggestions
- `AssetDefinitionRetirementPolicy`: exact-ID legacy retirement, buy/sell eligibility, and restore/edit restrictions
- `AssetPortfolioCalculator`: pure weighted-average calculations and legacy compatibility
- `AssetPriceRepository`: provider contract
- `AlphaVantageAssetPriceRepository`: HTTP/provider parsing
- `AssetPriceController`: cache, refresh, manual price, loading/error state
- `AssetsDashboardScreen`: rendering and action triggers only

## 7. Market-price flow

```text
transactions + cached prices
        |
AssetPortfolioCalculator
        |
AssetsDashboardScreen
        |
user refresh/manual action
        |
AssetPriceController
        |
AssetPriceRepository
        |
provider or manual input
        |
AssetMarketPrice
        |
LocalStore cache
        |
controller notification and recalculation
```

## 8. Overview/Assets boundary

Overview owns period activity: income, expenses, net cash flow, tithe, categories, and recent activity.

Assets owns quantity, lots, cost basis, market prices, market value, and realized/unrealized gains.

Do not move detailed holdings back to Overview.

## 9. Persistence architecture

Conditional export:

```dart
export 'local_store_web.dart'
    if (dart.library.io) 'local_store_native.dart';
```

Native uses versioned SQLite (currently version 10). Web exposes the same method
surface but is currently in-memory. Both stores provide all-or-nothing managed
asset-fee parent/child changes.

Asset execution references are optional immutable transaction snapshots.
Presentation selects a manual or compatible cached quote explicitly; the asset
controller validates identity and snapshot metadata, while the pure
`AssetExecutionAnalysis` service calculates direction-aware differences.
Portfolio, fee, financial-summary, and tithe accounting do not consume this
analytical metadata. The latest-price cache remains mutable and is not price
history.

## 10. Environment configuration

```dart
String.fromEnvironment('ALPHA_VANTAGE_API_KEY')
```

The key is for private/local development only. Public builds need a secure backend proxy.

## 11. Testing

Current verified suite: 297 tests.

Required coverage includes transaction mapping, SQLite round trips, migrations, conversion controller/widget, provider parsing, quote cache, price controller, portfolio calculations, navigation/dashboard widgets, and financial summaries.

## 12. Planned migrations

- Drift behind existing repository/store boundaries
- Riverpod through incremental controller replacement
- GoRouter after route contracts are tested
- full ledger entries and transaction revisions

## 13. Asset guardrails

Do:

- add first-class `AssetDefinition`
- separate display name and provider symbol
- store currency/exchange/unit/lot size
- validate sales before save
- persist fees and treatment
- keep provider code behind repository contract
- keep portfolio math pure
- add migrations and native/web tests

Do not:

- parse tickers from titles for new records
- put HTTP in widgets
- put SQL in controllers
- store money as `double`
- overwrite cost basis with market value
- count unrealized gain as income
- assume every stock uses IDR
- silently oversell
- commit API keys

## 14. Obsolete asset-definition compatibility

The retired generic stock definition is recognized only by the fixed ID
`asset-stock-portfolio`; display names never trigger retirement behavior.
`AssetDefinitionRetirementPolicy` owns this identity and the associated
archive, buy, sell, edit, and restore rules.

Bootstrap excludes this definition from fresh seeds. The definition controller
soft-archives an existing unused or fully closed row using the normal lifecycle
metadata. An open legacy position remains active only as a sell target and is
automatically archived after its quantity reaches zero. Transaction use cases,
Asset Conversion, Quick Add, and transaction editing enforce the same sell-only
rule. Historical transaction snapshots and portfolio fallback remain intact;
no transaction relinking or schema migration is involved.
