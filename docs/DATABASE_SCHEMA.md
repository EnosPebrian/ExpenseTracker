# Pilgrim Tracker Database and Persistence Schema

Fresh schema creation inserts no user financial rows.

Current SQLite schema version: **20**. Version 20 changes
`asset_market_prices` identity from global `asset_key` to the household-scoped
composite primary key `(book_id, asset_key)`. Existing rows and values are
preserved. This permits restored households to retain identical asset keys
without colliding; no calculation or transaction field changes.

Version 19 adds nullable
`sync_cursors.initial_sync_diagnostic_json` structural per-entity counters for
initial download. The counters contain no financial values or credentials, and
the migration preserves every existing cursor and financial row.
It also resets only non-ready download progress that older clients incorrectly
counted while rows were still staged; no user-owned records are changed.

Version 18 conservatively replaces a
legacy name-derived `transactions.project_id` with the matching project UUID
only when it identifies exactly one active project in the same book. Matching
durable sync payloads receive the same repair; ambiguous and unmatched values
remain untouched.

Version 17 replaces only the five stable
built-in asset-definition IDs with deterministic UUIDs required by the hosted
sync schema. It preserves transaction references and rewrites matching durable
outbox, conflict, and in-progress initial-sync payloads. It does not identify or
delete records by display name.

Version 16 additively extends
`sync_conflicts` with classification, changed fields, resolution lifecycle, and
resolution operation identity. Supabase adds `resolve_sync_conflict`.

**Snapshot date:** 2026-07-26

**Native database version:** 20

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
book_id TEXT
entered_by_member_id TEXT
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

Stores `book_id`, concrete asset identity, kind, display/market symbols, provider and
exchange metadata, valuation currency, unit, lot size, online-pricing status,
soft deletion, and sync/version metadata.

### `asset_market_prices`

Stores the latest validated or manual price under composite primary key
`(book_id, asset_key)`, including symbol,
integer price and scale, currency, unit, quote time, source, delay/manual flags,
and update time. This is a latest-value cache, not price history.

### Master-data tables

`books`, `accounts`, `categories`, and `projects` retain UUID, version, soft
deletion, and sync metadata. Books persist `base_currency_code` and nullable
`remote_linked_at`. Accounts
additionally persist nullable `owner_member_id`, `currency_code`
(`IDR` by default), signed integer `opening_balance`, and nullable
`opening_balance_date`. A null date means no starting position is configured;
zero with a date is a configured zero balance.

### `household_members`

Stores local people within a financial book: stable ID, `book_id`, display
name, nullable `auth_user_id`, `owner`/`member` role, timestamps, tombstone,
version, device, and sync status. Active names are unique case-insensitively
within one book. The Auth-user mapping does not replace local member identity.

### `local_profiles` and `local_session`

`local_profiles` stores the device-local display name and default currency.
`local_session` is a single-row record containing `active_profile_id`,
`active_book_id`, `active_member_id`, and the onboarding-completed flag. These
tables do not represent online or secure authentication. A local member is a
household person, not an authenticated application user.

### Sync protocol tables

`sync_outbox` durably stores stable operation IDs, book/entity identity,
upsert/delete intent, base version, JSON payload, attempt/backoff metadata,
safe error details, and pending/sending/retry/conflict/completed status.

`sync_cursors` stores one monotonic server sequence and initialization state
per book. `sync_conflicts` preserves local/server payloads and both versions
until later resolution. These protocol tables are never synchronized.

Current indexes cover transaction date, sync, project, asset snapshot,
asset-definition link, and managed relation lookup; asset-definition name,
symbol, and sync status; account name; category type; and project name. D14A
confirmed that fresh creation and every supported migration path produce this
same index set.

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
- Version 11: structured account currency/opening-balance fields plus local
  profile and session tables
- Version 12: authoritative financial-book scope, household members, account
  owner, transaction attribution, scoped assets/prices, and active book/member
  session references. Legacy rows are attached to one migrated book and the
  current profile becomes its owner member.
- Version 13: nullable `books.remote_linked_at` and
  `household_members.auth_user_id` for remote authorization linkage. The
  migration is additive and does not upload or rewrite financial rows.
- Version 14: durable outbox, monotonic per-book cursor, initialization guard,
  and minimal durable conflict records. Existing linked books become
  `primaryUploadRequired`; migration creates no historical operations and
  performs no upload.
- Version 15: expanded durable initialization state/progress metadata and
  `initial_sync_staging` for consistent primary snapshots and isolated
  secondary downloads. The v14 cursor and server sequence are preserved.

## Web fallback

`local_store_web.dart` stores the same transaction, structured-account,
local-profile, and session record maps in memory. Fee, relation, and
execution-reference fields round-trip through the shared entity mapping. Its
managed fee change set snapshots and restores the record list on failure.
Transaction and definition soft deletion update the same deletion, update,
version, and sync metadata as native storage. Browser reload may reset this
preview data.

## D14A historical verification

- At D14A, the fresh version-10 schema contained all then-current tables,
  transaction columns, and indexes.
- At D14A, versions 1, 3, 5, 7, 8, and 9 upgraded to version 10.
- Native close/reopen: transactions, definitions, prices, relationships,
  soft deletion, execution references, portfolio results, and summaries.
- Repeated bootstrap before and after reopen: no duplicate defaults or seed
  transactions and no restoration/overwrite of user-modified definitions.
- Native/web atomic linked-fee behavior and current record-field parity.

The D14A checks now also run against later additive schemas. BETA-03 adds the
v12-to-v13 link-metadata migration without rewriting financial values or
history.

## Supabase authorization schema

The versioned Supabase migration creates `user_profiles`, `books`,
`book_memberships`, `book_invitations`, financial mirror tables, and a
monotonic `app_changes` sequence. RLS uses active membership as the `book_id`
boundary. BETA-04A adds the household-member mirror, processed operation
ledger, secured push/pull RPCs, canonical version checks, and tombstone/cursor
exchange. BETA-04B adds initialization claims/sessions/items plus secured,
bounded upload/download RPCs. The server enforces owner-only empty-remote
upload and authorized stable download before incremental transfer is enabled.

## Deferred persistence

- historical bid/ask spread and quote-history modeling
- generalized precision policy
- price history
- ledger entries and transaction revisions
- conflict-resolution workflow
