# Pilgrim Tracker Development Roadmap

**Snapshot date:** 2026-07-21  
**Current milestone:** Asset portfolio and online-price foundation  
**Quality baseline:** Clean analyzer, 93 passing tests

Status: ✅ complete, 🟡 partial/transitional, ⬜ planned, 🔒 guardrail.

## 1. Delivery rules

Every milestone ends with a working build, migration when needed, focused tests, full tests, clean analysis, and updated documentation.

## 2. Foundation

### Application shell and navigation — ✅

- Android/Windows targets
- Chrome preview
- responsive navigation
- Overview and Assets as separate destinations
- shared theme and page layout

### Local storage — ✅ / 🟡

Complete:

- native versioned SQLite
- UUIDs, soft deletion, project and sync metadata
- web method parity

Transitional:

- direct SQLite instead of Drift
- in-memory web fallback

### Feature extraction — 🟡

Complete:

- transaction repository/use cases/controller/presentation
- asset domain/data/controller/presentation boundaries
- dashboard/asset separation

Remaining:

- Riverpod
- GoRouter
- Drift
- remaining legacy master-data extraction

## 3. Core transactions

### Income, expense, transfer — ✅

- create, edit, duplicate, soft delete
- period summaries
- Quick Add and transaction screens

### Full accounting model — ⬜

- double-entry entries
- split transactions
- refunds/adjustments
- revision history
- restore and reconciliation

🔒 Transfers stay excluded from income and expenses.

## 4. Master data and projects

### Current master data — ✅ / 🟡

- accounts, categories, projects
- seed data
- add/rename persistence

Remaining:

- full books
- business units
- contacts
- archive/reference protection
- opening balances

### Project reports — ⬜

- income, expenses, profit, cash flow, tithe, asset activity

## 5. Dashboard

### Overview cleanup — ✅

- period balance
- income
- expenses
- tithe due
- cash flow
- category spending
- recent activity

### Multi-month visualization — ⬜

- monthly expense trend
- income/expense comparison
- selectable range
- drill-down
- accessibility

🔒 Detailed asset controls remain in Assets.

## 6. Quantity-based assets

### Explicit asset transactions — ✅

- buy/sell action
- asset name
- ticker
- quantity, unit, unit price
- SQLite through version 5

### Portfolio calculator — ✅

- weighted-average cost
- partial-sale cost removal
- realized/unrealized gains
- market value
- stock shares/lots
- gold grams
- legacy compatibility
- cost-basis fallback

### Market prices — ✅ / 🟡

Complete:

- repository abstraction
- Alpha Vantage implementation
- stock quote and symbol-search service
- gold spot to IDR/gram
- manual prices
- latest native cache
- provider errors and quote status

Remaining:

- search UI
- secure proxy
- provider-specific symbol configuration
- currency/FX
- refresh policy
- price history/charts

### Portfolio screen — ✅ / 🟡

Complete:

- value, cost basis, realized/unrealized gain
- holdings, quantities, lots
- average/current prices
- manual/online actions

Remaining:

- persistent asset definitions
- configurable lot size/currency/exchange
- allocation chart
- complete net worth with cash/liabilities
- asset edit/configuration

### Asset transaction safety — ⬜ NEXT

- prevent overselling before save
- persist fee amount/treatment
- capitalize or expense fees correctly
- safe edit of asset identity/ticker
- sale acceptance tests

## 7. Immediate safe sequence

### Milestone A — Persistent asset definitions and currency safety

Deliver:

- `AssetDefinition`
- repository and controller
- SQLite migration from v5
- kind, display name, symbol, provider symbol
- exchange, currency, unit, lot size
- online-pricing flag
- management UI
- Asset Conversion integration
- quote-currency validation

Acceptance:

- BBCA uses 100 shares/lot
- AAPL can use USD and is not treated as IDR
- display name differs from provider symbol
- old transactions remain readable

### Milestone B — Sale validation and fees

- available-quantity validation
- oversell prevention
- fee persistence
- capitalized and expensed fee behavior
- full/partial sale tests

### Milestone C — Quote hardening

- symbol search UI
- currency verification
- throttling/cache age
- retry policy
- backend proxy design

### Milestone D — Allocation and net worth

- allocation by market value
- cash integration
- liability persistence
- net worth and drill-down

### Milestone E — Overview chart

- multi-month expense chart
- income/expense series
- period controls
- category drill-down

## 8. Tithe — 🟡 / ⬜

Current effective-date policy and summary calculations exist.

Planned:

- persisted rules
- eligible categories
- obligations
- payments/allocations
- advance balances
- recalculation history

🔒 Asset conversion does not create tithe by itself.

## 9. Desktop manager — ⬜

Spreadsheet grid, keyboard navigation, inline/bulk editing, copy/paste, saved views, revisions.

## 10. Import/export/backup — ⬜

CSV, XLSX, JSON/ZIP backup, preview, duplicates, rollback, restore logs.

## 11. Synchronization — ⬜

Authentication, devices, queue, push/pull, tombstones, conflicts, attachments.

🔒 Financial conflicts are never silently overwritten.

## 12. Recurring transactions — ⬜

Templates, recurrence rules, draft/automatic/reminder modes, duplicate protection.

## 13. Receipt scanning — ⬜

Capture, OCR, confidence, draft review, attachments.

## 14. Security/release — ⬜

PIN/biometric, secure tokens, quote proxy, backup verification, integrity, accessibility, privacy, release testing.

## 15. Next checkpoint definition

The next checkpoint is complete when asset definitions are persisted, lot size and currency are configurable, IDR/non-IDR stocks cannot be confused, database v5 upgrades safely, quote/manual cache still works, analysis is clean, tests pass, and docs are updated.
