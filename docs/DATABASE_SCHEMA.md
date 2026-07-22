# Pilgrim Tracker Database and Persistence Schema

**Snapshot date:** 2026-07-21  
**Native database version:** 5  
**Native engine:** SQLite through `sqflite_common_ffi`  
**Web preview:** In-memory `LocalStore` fallback

## Migration policy

Every schema change must:

1. increment the database version
2. update fresh-install `onCreate`
3. add an `onUpgrade` branch
4. preserve existing rows
5. update record mapping
6. expose equivalent native and web methods
7. add migration or round-trip tests
8. update this file and `PROGRESS.md`

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
asset_name TEXT
asset_symbol TEXT
asset_action TEXT
created_at INTEGER NOT NULL
updated_at INTEGER NOT NULL
deleted_at INTEGER
version INTEGER NOT NULL DEFAULT 1
device_id TEXT NOT NULL
sync_status TEXT NOT NULL DEFAULT 'local_only'
```

Indexes include:

```text
idx_transactions_date
idx_transactions_sync
idx_transactions_project
idx_transactions_asset(asset_name, asset_action)
```

### `books`

Transitional master-data table with UUID and sync metadata.

### `accounts`

Stores name and `account_type`, plus UUID and sync metadata. It does not yet persist a dedicated asset definition, lot size, currency, exchange, or provider configuration.

### `categories`

Stores name and category type, plus UUID and sync metadata.

### `projects`

Stores name and active status, plus UUID and sync metadata.

### `asset_market_prices`

```text
asset_key TEXT PRIMARY KEY
symbol TEXT
price_minor INTEGER NOT NULL
minor_unit_scale INTEGER NOT NULL DEFAULT 1
currency_code TEXT NOT NULL
unit TEXT NOT NULL
quoted_at INTEGER NOT NULL
source TEXT NOT NULL
is_delayed INTEGER NOT NULL DEFAULT 0
is_manual INTEGER NOT NULL DEFAULT 0
updated_at INTEGER NOT NULL
```

This is a latest-value cache, not historical price storage.

## Version history

- Version 1: initial transaction table
- Version 2: `transactions.project_id`
- Version 3: books, accounts, categories, and projects
- Version 4: `asset_name`, `asset_action`, asset index
- Version 5: `asset_symbol`, `asset_market_prices`

## Web fallback

`local_store_web.dart` currently uses static in-memory lists/maps and must maintain method parity with native storage. Browser reload may reset data.

## Next recommended table

```text
asset_definitions
  id TEXT PRIMARY KEY
  account_id TEXT
  display_name TEXT NOT NULL
  asset_kind TEXT NOT NULL
  symbol TEXT
  exchange_code TEXT
  currency_code TEXT NOT NULL
  unit TEXT NOT NULL
  lot_size INTEGER NOT NULL DEFAULT 1
  online_pricing_enabled INTEGER NOT NULL DEFAULT 0
  provider_code TEXT
  provider_symbol TEXT
  created_at INTEGER NOT NULL
  updated_at INTEGER NOT NULL
  deleted_at INTEGER
  version INTEGER NOT NULL DEFAULT 1
  device_id TEXT NOT NULL
  sync_status TEXT NOT NULL
```

Future persisted additions:

- fee amount and fee treatment
- price history
- ledger entries
- transaction revisions
- synchronization queue
