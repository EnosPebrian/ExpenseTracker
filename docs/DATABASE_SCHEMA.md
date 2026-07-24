# Pilgrim Tracker Database and Persistence Schema

**Snapshot date:** 2026-07-24

**Native database version:** 10

**Native engine:** SQLite through `sqflite_common_ffi`

**Web preview:** In-memory `LocalStore` fallback

## Migration policy

Every schema change must increment the database version, update fresh-install
creation, provide a safe upgrade path, preserve existing rows, maintain native
and web mapping behavior, add migration/round-trip tests, and update this file.

## Current tables

### `transactions`

```text
id TEXT PRIMARY KEY
project_id TEXT
title TEXT NOT NULL
category TEXT NOT NULL
account TEXT NOT NULL
transaction_date INTEGER NOT NULL
amount INTEGER NOT NULL
transaction_type TEXT NOT NULL
quantity REAL
unit TEXT
unit_price INTEGER
asset_definition_id TEXT
asset_name TEXT
asset_symbol TEXT
asset_action TEXT
fee_amount INTEGER NOT NULL DEFAULT 0
fee_treatment TEXT NOT NULL DEFAULT 'none'
related_transaction_id TEXT
relation_type TEXT NOT NULL DEFAULT 'none'
market_reference_unit_price INTEGER
market_reference_currency_code TEXT
market_reference_unit TEXT
market_reference_source TEXT
market_reference_quoted_at INTEGER
created_at INTEGER NOT NULL
updated_at INTEGER NOT NULL
deleted_at INTEGER
version INTEGER NOT NULL DEFAULT 1
device_id TEXT NOT NULL
sync_status TEXT NOT NULL DEFAULT 'local_only'
```

`amount` remains the gross IDR trade amount. Supported persisted fee treatments
are `none`, `capitalizeIntoCostBasis`, `deductFromSaleProceeds`, and
`recordAsSeparateExpense`. Legacy or unknown treatments safely map to `none`
in the domain entity.

Generated asset-fee expenses use `related_transaction_id` to reference their
parent asset conversion and persist `relation_type = assetFeeExpense`. Legacy
rows default to no relationship. The parent and managed child are written in a
single repository change set and native SQLite transaction.

Indexes include transaction date, sync status, project, asset snapshot, and
`asset_definition_id` indexes. The managed-fee lookup uses the composite
`related_transaction_id, relation_type` index.

The five nullable market-reference columns hold an immutable analytical
snapshot selected explicitly for a parent asset conversion. The price is
integer IDR per transaction unit; source values are `manual`, `cached_quote`,
and the forward-compatible `unknown`. No calculated difference is persisted,
and generated fee expenses keep these columns null.

### `asset_definitions`

Stores concrete asset identity, kind, display/market symbols, provider and
exchange metadata, valuation currency, unit, lot size, online-pricing status,
soft deletion, and sync/version metadata.

### `asset_market_prices`

Stores the latest validated or manual price by asset key, including symbol,
integer price and scale, currency, unit, quote time, source, delay/manual flags,
and update time. This is a latest-value cache, not price history.

### Master-data tables

`books`, `accounts`, `categories`, and `projects` retain UUID, version, soft
deletion, and sync metadata.

## Version history

- Version 1: initial transaction table
- Version 2: `transactions.project_id`
- Version 3: books, accounts, categories, and projects
- Version 4: asset name/action snapshots and asset index
- Version 5: asset symbol snapshot and market-price cache
- Version 6: concrete asset definitions
- Version 7: `transactions.asset_definition_id`
- Version 8: persisted `fee_amount` and `fee_treatment`
- Version 9: managed transaction relation metadata and relation lookup index
- Version 10: optional execution-reference price snapshot on transactions

## Web fallback

`local_store_web.dart` stores the same transaction record maps in memory, so fee,
relation, and execution-reference fields round-trip through the shared entity mapping. Its managed
fee change set snapshots and restores the record list on failure. Browser
reload may reset this preview data.

## Deferred persistence

- historical bid/ask spread and quote-history modeling
- generalized precision policy
- price history
- ledger entries and transaction revisions
- synchronization queue
