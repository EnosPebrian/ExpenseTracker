# Pilgrim Tracker Product Specification

**Snapshot date:** 2026-07-21  
**Product:** Pilgrim Tracker  
**Primary platforms:** Android and Windows  
**Development preview:** Web/Chrome  
**Core model:** Local-first personal, project, asset, and tithe finance manager

## 1. Product definition

Pilgrim Tracker is a premium-looking but familiar expense manager with a reliable financial core. It supports daily income and expense entry, transfers, project tracking, quantity-based assets, asset conversions, tithe calculations, reporting, and future cross-device synchronization.

The interface should remain understandable to a normal expense-manager user. Accounting complexity belongs in domain services and persistence, not in the everyday interface.

## 2. Product principles

### Local-first

- Normal financial entry must not require internet.
- A write is committed locally before future synchronization.
- Cached asset prices remain available when the online provider fails.
- Failure to refresh a quote must never delete the last valid quote.
- Manual prices remain available without a provider or API key.

### Reliable money behavior

- Money is stored as integers.
- Quantity may use `double` only for measurable non-money units.
- Transfers do not count as income or expense.
- Asset conversion does not count as ordinary income or expense.
- Unrealized gains do not count as cash income.
- Realized and unrealized gains are reported separately.
- Soft-deleted transactions do not affect summaries or holdings.

### Shared business logic

Android, Windows, and preview clients share transaction entities, validation, financial summaries, tithe policies, portfolio calculations, market-price models, and repository contracts.

## 3. Current navigation

1. Overview
2. Assets
3. Transactions
4. Accounts
5. Categories
6. Asset Conversion
7. Projects
8. Tithe
9. Reports

### Overview

Overview is a period-based expense dashboard. It shows monthly/selected-period balance, income, expenses, tithe due, cash flow, category spending, recent transactions, and activity.

Detailed asset controls do not belong here.

### Assets

Assets is the portfolio workspace. It supports:

- gold quantity in grams
- stock quantity in shares
- stock lots using each concrete stock definition's configured lot size
- weighted-average cost
- remaining cost basis
- latest cached or manual market price
- market value
- unrealized gain/loss and return
- realized gain from recorded sales
- quote source, delay/manual status, and date

Top metrics are portfolio value, cost basis, unrealized gain, and realized gain.

### Asset Conversion

Asset Conversion supports buying and selling concrete measured assets,
quantity, unit, calculated unit price, and date/time.

Current default groups:

- Gold Holdings
- Stock Portfolio
- Bitcoin Wallet
- Inventory

Stock quantity is stored as shares. Lots are derived as:

```text
lots = shares / lot_size
```

Stock quantities remain persisted as shares. New buys and normal sales must be
whole multiples of the selected definition's `lotSize`. Definitions with lot
size 1 accept any whole-share quantity. Historical odd-lot holdings are not
rewritten: a sale may sell whole lots, remove the odd residue so the remainder
is a whole-lot quantity, or fully close the holding. Validation uses shares
available at the transaction date and excludes the original record during an
edit.

## 4. Transaction model

Current transaction types:

- expense
- income
- transfer
- assetConversion

Asset fields:

```text
quantity
unit
unitPrice
assetName
assetSymbol
assetAction: buy | sell
```

Shared metadata includes:

```text
id
projectId
title
category
account
date
amount
type
createdAt
updatedAt
deletedAt
version
deviceId
syncStatus
```

Legacy inference of asset identity/action is compatibility only. New records persist explicit fields.

## 5. Portfolio calculation rules

Purchase:

```text
new_quantity = old_quantity + purchased_quantity
new_cost_basis = old_cost_basis + cash_amount
average_cost = new_cost_basis / new_quantity
```

Partial sale:

```text
removed_cost_basis = average_cost_before_sale × matched_quantity
realized_gain = matched_proceeds - removed_cost_basis
remaining_cost_basis = old_cost_basis - removed_cost_basis
remaining_quantity = old_quantity - matched_quantity
```

Market valuation:

```text
market_value = quantity × current_price
unrealized_gain = market_value - cost_basis
unrealized_return = unrealized_gain / cost_basis
```

Without a market price, displayed market value falls back to cost basis and the UI states that no current price is available.

A future save-time validation must prevent selling more than the available quantity.

## 6. Online prices

Current provider contract:

```text
AssetPriceRepository
```

Current implementation:

```text
AlphaVantageAssetPriceRepository
```

Capabilities:

- stock quote
- stock symbol search service
- gold spot price
- USD/IDR conversion
- provider error/rate-limit detection

Gold IDR per gram:

```text
IDR_per_gram = USD_per_troy_ounce × USD_IDR / 31.1034768
```

API key:

```text
--dart-define=ALPHA_VANTAGE_API_KEY=...
```

The key must never be committed. Public distribution requires a backend proxy.

Current quote limitations:

- stock quotes may be delayed/end-of-day
- stock refresh currently assumes an IDR-denominated quote
- non-IDR equities are unsafe until currency and FX are modeled
- only the latest quote is cached

## 7. Persistence

Native platforms use versioned SQLite, currently version 10.

Current persisted asset additions:

- `transactions.asset_name`
- `transactions.asset_symbol`
- `transactions.asset_action`
- optional `transactions.market_reference_*` execution snapshot fields
- `asset_market_prices`

An asset trade may explicitly snapshot a manual or compatible cached IDR-per-
unit reference quote. The UI compares the gross execution price with this saved
reference using direction-aware wording. This is informational execution
analysis, not a verified historical bid/ask spread. It never changes amount,
cost basis, gains, fees, financial summaries, or tithe.

Web preview uses in-memory collections and may reset after browser reload.

Every persisted change requires a version increment, `onCreate`, `onUpgrade`, native/web parity, record mapping, and tests.

## 8. Current acceptance criteria

- gold purchase records quantity, cost, and action
- stock purchase requires and stores a ticker
- 1,000 shares displays as 10 lots at lot size 100
- multiple purchases produce weighted-average cost
- partial sale reduces quantity and cost basis
- realized gain equals proceeds minus removed cost
- manual and online prices are cached
- provider failure does not remove the previous quote
- no API key leaves manual pricing usable
- asset conversions do not affect ordinary income/expense
- static analysis and tests pass

## 9. Known product gaps

- persistent asset definitions
- configurable lot size, currency, exchange, and provider symbol
- persistent browser database
- fee amount/treatment persistence
- oversell prevention before save
- multi-currency and FX
- price history and charts
- market-value allocation chart
- cash/liabilities integrated into net worth
- asset identity/ticker edit flow
- stock-symbol search UI
- secure quote proxy
- automatic refresh/rate-limit policy
- first-class additional asset types
- Drift, Riverpod, and GoRouter migrations
- full ledger/revisions
- synchronization, import/export, and backup/restore
