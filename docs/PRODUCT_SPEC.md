# Pilgrim Tracker Product Specification

Shared households receive conflict review with Keep shared, Keep this device,
and safe field-level merge. Deletion and high-risk financial conflicts always
require explicit confirmation.

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
- Bitcoin Wallet
- Inventory
- US Dollar Cash
- Singapore Dollar Cash

Stocks are created as concrete definitions with their own symbol, exchange,
currency, unit, and lot size. The obsolete generic `asset-stock-portfolio`
definition is retained only for fixed-ID historical close-position
compatibility and is never offered for new purchases.

If that exact legacy definition has an open historical holding, it is clearly
identified as legacy and may only be sold down under the normal oversell, lot,
precision, fee, and execution-reference rules. It is soft-archived after the
holding closes and can never be restored or identity-edited. A user-created
definition with the same display name but a different ID follows normal asset
rules.

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

Native platforms use versioned SQLite, currently version 15.

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

### Asset-definition integrity

- stock symbols are unique per normalized exchange; a missing exchange cannot
  bypass a matching-symbol conflict
- distinct explicit exchanges may use the same stock symbol
- non-stock definitions cannot duplicate their established market-price identity
- online pricing requires provider code and provider symbol
- normalized provider code and symbol pairs are unique across all asset kinds
- archived definitions continue to reserve symbol, market-price, and provider
  identities so historical links remain unambiguous
- disabling online pricing retains optional provider configuration
- validation failures stay in the asset editor with actionable field errors
- archive and restore actions use the definition lifecycle rules below

### Asset-definition lifecycle

- unused definitions and fully closed historical positions may be archived
- definitions with an open quantity cannot be archived
- archive preserves the definition ID, historical transactions, execution
  snapshots, realized gain, and cached market prices
- archived definitions are excluded from new conversions but remain available
  for historical portfolio resolution
- restore reactivates the same definition row and reruns all D13A identity checks
- definitions linked to any historical asset transaction may edit display name
  and provider configuration only
- linked kind, symbol, exchange, valuation currency, unit, and lot size are
  read-only because historical accounting depends on them
- archive/restore does not relink or rewrite transactions

### Asset-definition catalog

- search is immediate, local, case-insensitive, and whitespace-normalized across
  visible asset identity fields
- lifecycle, multi-kind, and pricing filters compose without changing stored
  definitions; clear filters preserves the selected lifecycle
- definitions sort by normalized name, recent update, kind, or symbol with a
  stable definition-ID tie-breaker
- catalog state and preset-selection state are not persisted
- create-form defaults and explicit IDX/FX preset actions never overwrite dirty
  values, enable online pricing, bypass integrity checks, or alter protected
  linked fields
- active, filtered, and archived empty states present only contextually safe
  actions and remain usable on narrow layouts

## 9. Known product gaps

- persistent browser database
- price history and charts
- market-value allocation chart
- stock-symbol search UI
- secure quote proxy
- automatic refresh/rate-limit policy
- Drift, Riverpod, and GoRouter migrations
- full ledger/revisions
- initial synchronization, conflict-resolution UI, import/export, and
  backup/restore
- PIN or biometric application lock
- production Android and Windows signing credentials
- Windows installer and automatic updates
- app-store listing assets

## 10. Release posture

Android and Windows are the primary release targets. Web remains a development
preview whose in-memory data may reset after reload. Version `1.0.0+1` is the
current build metadata, not a declaration that public 1.0 release gates have
passed.

D14C establishes permanent Android ID `com.enospebrian.pilgrimtracker`, Windows
company `Enos Pebrian`, and original cross-platform branding. Android NDK r28c
is repaired and technical APK/AAB artifacts build successfully, but they use an
explicitly opted-in debug certificate and are not Play-ready. Android runtime
and native release database reopen tests remain required, as do the final
branded Windows/web builds and Windows runtime proof. The product is therefore
not yet an approved controlled release candidate.

## 11. BETA-01 account and profile behavior

Accounts are structured local records with stable identity, type, currency,
and an optional dated starting position. Money is stored as signed integer
minor units. A configured zero is valid; disabling the starting position saves
zero and a null effective date. The profile default currency supplies the
initial currency for newly created accounts.

The starting position is immediately before transactions on its effective
local calendar date. Transactions on that date are included; earlier
transactions stay visible but do not affect the account balance. Income and
asset-sale proceeds increase cash; expenses and asset buys decrease it; the
existing fee-treatment rules are applied once. Legacy transfers remain zero in
account balance calculations when direction is ambiguous.

Starting positions are account metadata, never generated transactions. They do
not change income, expenses, cash flow, activity, categories, projects, tithe,
asset quantity, cost basis, or realized/unrealized gains.

First launch collects a display name and default currency for a lightweight
device-local profile. It has no email, password, OAuth, backend, recovery,
biometrics, PIN, or synchronization and must not be presented as secure
authentication. Existing databases receive a safe local default profile during
the version-11 migration.

## 12. BETA-02 household and attribution behavior

A financial book is the household data boundary. Existing data migrates into
one default book, and the device profile becomes its first owner member. Local
members identify people only; they are not passwords, authenticated accounts,
or interchangeable cloud identities. The active member persists on the device;
BETA-03 may map it to an authenticated user without replacing it.

Accounts may be joint or associated with a member. Transactions record who
entered them, defaulting new Quick Add, normal, duplicated, and asset-conversion
records to the active member. Ownership and attribution are descriptive and do
not change balances, reporting, tithe, portfolio quantities, cost basis, fees,
or gains. BETA-03 provides cloud identity, authorization, and invitations.
BETA-04A provides the durable incremental protocol. BETA-04B provides a
confirmed, empty-remote initial upload and stable non-merge secondary download
before incremental sync may run. Conflict UX and real two-device proof remain
BETA-04C/BETA-05.

## 13. Backup, restore, and CSV behavior

Users can create a password-encrypted `.ptbackup` for the active household,
restore it as an independent local household, or perform a strongly confirmed
matching-household recovery after saving a safety backup. Restore is non-merge,
validated before activation, and local-only until cloud relinking. Pilgrim
Tracker cannot recover forgotten backup passwords.

CSV export is a separate filtered, human-readable ZIP with exact integer money,
stable columns, ISO dates, and formula-injection protection. It is not a full
application backup. Normal connected device changes use sign-in and cloud
download; encrypted backup is for offline, emergency, or historical recovery.

## 14. BETA-07A/B monthly category budgets

One active household budget may be set for an expense category and local
calendar month. Limits are positive exact integers in the book base currency.
Qualifying active expense transactions count regardless of owner or entered-by
member; income, transfers, opening balances, asset conversions, deletions, and
other months do not. Existing separate fee-expense rows count as expenses.

Per-category results show spent, remaining, overspent, percentage, and an
accessible status. Monthly totals show total budgeted, budgeted-category spend,
remaining, overspent, and qualifying unbudgeted spend. BETA-07A deliberately
does not include rollover, weekly/yearly/member/account budgets, suggestions,
forecasting, goals, debt plans, notifications, or scheduled jobs.

## 15. BETA-08A selective recovery

Backup & Export exposes `Recover missing records` separately from replacement
restore. It accepts only the active canonical household, previews already
present, recoverable, duplicate, conflicting, remote-deleted, blocked, and
unsupported records, includes safe dependencies, and commits the selected plan
without deleting current data. Linked recovery requires hosted verification and
synchronizes through the normal durable outbox.

## 16. BETA-08A1 restore lifecycle

`Restore entire backup` is an advanced disaster-recovery action and starts
local-only. The resulting household can stay local, reconnect to authoritative
existing hosted data, or create a separate shared household. New sharing uses a
fresh-identity local clone and normal protected initial upload, preserving both
the original restored snapshot and any existing initialized hosted household.

BETA-07B lets a user explicitly copy budget definitions from one month into a
different currently selected month. Preview classifies plans as Will be added,
Already present, or Category unavailable and shows the expected target total.
Only active, missing target-category plans are added; existing target plans are
never overwritten, and archived/missing categories are skipped safely. The
operation copies category, limit, currency, and note—not spending or derived
progress—and does not implement rollover, carryover, or automatic monthly copy.
# CSV transaction entry (BETA-08B)

Windows and Android users can import canonical or mapped bank CSV files from
Transactions. Nothing is saved before review and final confirmation. Stable
source identities make exact-file re-import idempotent; semantic duplicates and
possible deleted matches remain excluded for user review. See `CSV_IMPORT.md`.
# Reviewed receipt and statement ingestion

Pilgrim supports reviewed receipt/invoice images and bank-statement PDF/page
images. Extraction never creates a transaction automatically. The user must
confirm destination account, category, edits, duplicate decisions, and final
atomic import. Sensitive source files are not persisted or made public.

## 17. BETA-08E deterministic import rules

Household members can explicitly create expense or income rules that match a
description, reference, merchant hint, or description-or-reference and suggest
a compatible category during import review. Manual choices and valid explicit
source categories outrank rules. Ambiguous highest-priority matches require a
choice. Rules never create transactions, learn silently, recategorize saved
records, or use AI. See `IMPORT_RULES.md`.

## 18. Canonical internal transfers

All new manual internal transfers are one logical movement backed by a stable
outgoing leg, stable incoming leg, and stable directional link. Users edit the
movement coherently, may Unpair while retaining both rows, or Delete to
tombstone the link and both rows. Active pairs affect account balances but are
not household income, expense, budget spending, or tithe income. Legacy
single-row transfers remain readable and are not automatically migrated.

## 19. Reviewed transfer suggestions

Pilgrim may suggest exact-value movements between owned accounts when they are
same-household, same-currency, opposite-direction ordinary entries posted no
more than two local calendar days apart. Suggestions are explainable and never
automatic. Equal-quality alternatives require manual counterpart selection.

## 20. Import Review Inbox

CSV, receipt, invoice, and bank-statement results may be saved as normalized
pending imports, resumed after restart, renamed, reviewed, discarded, or
committed in the existing editor. Pending and recent-completed views expose
safe counts and source labels; the UI states that original files are not
stored. Linked households synchronize inbox state between devices, but merely
receiving a session never creates transactions. Account/category loss,
conflicts, invalid selected rows, or stale versions block commit for review.

## Telegram ingestion

An authorized member may link one private Telegram identity and send supported
attachments to Import Inbox. Telegram is ingestion-only: it cannot answer
financial queries, select an account, approve a duplicate or transfer, or
create/edit/delete finance. Canonical CSV, receipt images, and unlocked bank
statement PDF/images are normalized for later explicit in-app review.

## Monthly and annual financial statements

Reports provides Monthly and Annual statements for the household or one
account. Household statements separate currencies and show opening/closing,
income, expenses, net cash flow, tithe, transfers, accounts, categories,
budgets, and period activity. Account statements show native-currency opening,
inflow/outflow, transfer movements, running balances, and closing balance.

Users may preview and export an A4 PDF locally. Large annual account histories
may use an explicit month-by-month ledger summary; monthly statements retain
transaction-level detail. Historical year-end net worth is omitted until a
reliable as-of valuation engine exists. Linked households with pending local
state receive a device-data warning.

## Data & Sync Health Check

Users can explicitly run a read-only Health Check covering SQLite version,
household and transaction references, account reconciliation, canonical
transfers, Import Inbox/deferred identity, rules and budgets, local sync/outbox
and conflict state, and encrypted-backup capability. Results use Healthy,
Attention needed, or Critical language with expandable plain-language detail.
Pending imports are informational; cloud unavailability does not imply local
financial corruption. A privacy-safe copied summary excludes finance, raw IDs,
fingerprints, and secrets. There is no automatic repair.

## Cloud durability and a new device

A linked household uses local SQLite for immediate offline work and Supabase as
its durable shared record copy. On a new installation, a signed-in active
member can choose an existing household and download it through protected
initial synchronization; copying a database or restoring a backup is not the
normal device-migration workflow. If sync shows changes waiting, those changes
remain recoverable only on that device until Pending returns to 0. Local-only
households remain optional and depend on encrypted backups for device-loss
recovery.
