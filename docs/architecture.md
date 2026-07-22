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
```

New records must not depend on title/account parsing.

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
    asset_portfolio_calculator.dart
  presentation/screens/
    asset_conversion_screen.dart
    assets_dashboard_screen.dart
  presentation/widgets/
```

Responsibilities:

- `AssetConversionController`: form state, validation, explicit buy/sell transaction creation
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

Native uses versioned SQLite. Web exposes the same method surface but is currently in-memory.

## 10. Environment configuration

```dart
String.fromEnvironment('ALPHA_VANTAGE_API_KEY')
```

The key is for private/local development only. Public builds need a secure backend proxy.

## 11. Testing

Current verified suite: 93 tests.

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
