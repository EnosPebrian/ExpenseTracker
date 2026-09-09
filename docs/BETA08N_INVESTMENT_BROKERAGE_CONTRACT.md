# BETA-08N Investment / Brokerage Contract

**Accepted:** 2026-09-10
**Authority:** ARCH-20260910-01, Option B
**Sequence:** BETA-08N0 Ledger Foundation, then BETA-08N1 Statement CSV Import

## Product boundary

Investment/Brokerage is a dedicated financial subledger. It is not an ordinary
daily expense category, Project, Budget, fake bank-statement transaction type,
or second copy of Pilgrim's existing asset accounting engine. D10–D13
instrument, quantity, price, fee, and weighted-average accounting semantics
remain authoritative wherever they already provide the required behavior.

Investment UI may be separate, but it must not create a competing stock
cost-basis engine or accounting truth.

## Core concepts

The domain supports brokerage accounts, existing Asset Definitions as
investment instruments, brokerage activities, derived positions, brokerage
cash, realized and unrealized P&L, investment income, and investment costs. A
brokerage account belongs to one household and has an explicit settlement
currency. Monetary values in different currencies must never be silently
combined.

## Authoritative economic events

BETA-08N0 supports exactly:

- `BUY`
- `SELL`
- `DIVIDEND`
- `FEE`
- `TAX`
- `DEPOSIT`
- `WITHDRAWAL`
- `SPLIT`

No other corporate-action semantics may be invented. Unsupported actions stay
unsupported.

### BUY

A BUY decreases brokerage cash, increases asset quantity, and increases cost
basis. Principal invested is not an ordinary expense and must not appear in
category spending, budgets, or Tithe Due. Existing asset quantity, precision,
lot-size, weighted-average, and fee-capitalization rules remain authoritative.
FIFO/LIFO must not be invented.

### SELL

A SELL decreases asset quantity and increases brokerage cash. Realized gain or
loss uses existing weighted-average basis. Gross proceeds are not household
income. Overselling remains prohibited. Fees and taxes reduce net proceeds or
realized result exactly once.

### Realized P&L

Authoritative realized P&L is net sale proceeds minus the cost basis of quantity
sold, using existing integer and precision rules. It is investment performance,
not ordinary salary/income or expense. Binary floating point must not be the
authority for financial values.

### Unrealized P&L

Unrealized P&L is current market value minus remaining cost basis and uses the
existing asset pricing/valuation architecture. Missing or stale prices retain
the existing unavailable/stale semantics. Market prices must not be fabricated,
and unrealized P&L is never cash income.

### DIVIDEND

A DIVIDEND increases brokerage cash, is investment income, and contributes to
investment performance separately from trade proceeds. It does not
automatically affect Tithe Due in BETA-08N.

### FEE

A standalone FEE decreases brokerage cash and investment performance. It is not
an ordinary household budget expense. A fee already incorporated in BUY/SELL
accounting must not also be recorded as a standalone investment cost.

### TAX

Statement/user-provided investment TAX or withholding decreases brokerage cash
and net investment performance where applicable. It is not an ordinary daily
expense. BETA-08N does not calculate tax law.

### DEPOSIT and WITHDRAWAL

Funding is not investment profit or loss. Funding from or to an owned Pilgrim
cash/bank account uses existing canonical internal-transfer semantics wherever
applicable:

- DEPOSIT: owned cash account → brokerage cash.
- WITHDRAWAL: brokerage cash → owned cash account.

Neither event counts as income, expense, investment return, or Tithe Due. No
fake funding category may be invented.

### SPLIT

A stock split or reverse split changes quantity and per-unit basis consistently
while preserving total cost basis. It creates no cash income/expense and no
realized P&L. Fractional cash-in-lieu policy is outside scope; such rows remain
unresolved.

## One economic event, one authoritative effect

If existing Pilgrim asset transactions are authoritative for BUY/SELL,
brokerage records may reference or group them but must not independently double
cash, holdings, P&L, or net worth. Canonical transfers likewise remain
authoritative for owned-account funding. Brokerage metadata may link those
records but may not duplicate their financial effect.

## Positions

Positions are derived, not independently mutable. At minimum they expose:

- instrument;
- quantity held;
- remaining cost basis;
- average cost;
- current price when available;
- market value;
- unrealized P&L.

There is no separate editable current-quantity truth.

## Investment performance

Brokerage-account and household investment views expose separately:

- realized gain/loss;
- dividend income;
- investment fees/taxes;
- unrealized gain/loss.

Funding deposits/withdrawals and BUY/SELL principal are excluded. BETA-08N does
not claim time-weighted return, money-weighted return, IRR, CAGR, or tax-adjusted
performance.

## Net worth

Household net worth includes brokerage cash plus current market value of
positions. Existing asset/net-worth representation must be inspected and reused
so the same holdings are never counted twice.

## Budgets, projects, and Tithe

Investment activities do not participate in ordinary category budgets and are
not Projects. Trading must not be routed through ordinary spending categories.

BETA-08N does not change `TithePolicy`. BUY, SELL proceeds, realized/unrealized
gain, dividends, deposits, withdrawals, brokerage fees, and tax have no new
automatic Tithe Due effect. Any investment-specific Tithe policy needs a
separate owner/architect decision.

## Multi-currency

Each brokerage account has an explicit settlement currency. Native/source
currency values are preserved. Existing FX architecture is used only where a
compatible household-base valuation path already exists. Trade execution
amounts must not be silently converted, and incompatible currencies must not be
summed.

## Local-first, sync, and authorization

All investment writes follow:

```text
user action
→ local atomic commit
→ ordinary outbox
→ existing sync
```

Offline manual operation remains possible when required local reference data
exists. Existing household/member authorization, outbox, change-feed, and
conflict principles apply. Brokerage data cannot cross household boundaries,
and no new service-role client authority is allowed.

If a synchronized entity is required, an additive SQLite and Supabase migration
is allowed, with RLS and pgTAP coverage. Hosted deployment remains deferred
unless explicitly authorized.

## Identity

Stable persisted investment entities use stable UUID identity and never mutable
display names. Existing Asset Definition identity remains authoritative.
BETA-08N0 must not change existing transaction UUID/fingerprint rules.
Brokerage statement identity is defined only by BETA-08N1.

## Backup, recovery, and bootstrap

Every new authoritative brokerage entity participates in encrypted backup,
exact restore, household clone remapping, selective recovery where applicable,
reconnect-existing/cloud-authoritative lifecycle, and new-device bootstrap. A
backup-format bump is authorized when genuinely required. Brokerage financial
history must not be omitted merely to avoid a version change.

## Health Check

Extend BETA-08J narrowly for structural brokerage integrity when persistent
relations are added. Genuine findings include missing household/account/
instrument references, missing authoritative linked trades, broken position
relations, cross-household references, and impossible BUY/SELL links. Health
Check remains read-only and never auto-repairs.

## BETA-08N0 — Ledger Foundation

### Scope

- persistence and domain foundation;
- brokerage account;
- manual brokerage activities;
- existing asset-accounting integration;
- brokerage cash integration;
- positions;
- realized/unrealized P&L;
- investment performance screen;
- net-worth integration;
- encrypted backup/restore/clone;
- sync/reconnect/bootstrap;
- Health Check;
- responsive Windows, Android, and web-preview UI.

### Non-goals

- broker CSV import;
- PDF/image extraction or AI broker parsing;
- brokerage API connection, trading, or order placement;
- automatic quote-provider expansion;
- tax calculation;
- options, futures, margin, or short selling;
- security transfer between brokers;
- unsupported corporate actions.

### Required engineering analysis before schema design

Inspect D10–D13 and explicitly determine:

1. which existing entity owns BUY/SELL accounting;
2. which service owns weighted-average cost basis;
3. which service owns realized/unrealized calculations;
4. how cash settlement is represented;
5. whether existing `Account` safely represents brokerage cash;
6. how D12 fees are represented;
7. how net worth includes asset positions;
8. whether brokerage attribution needs new entity fields or relations.

Reuse those authoritative components. If this contract cannot be represented
without two competing accounting truths, create `BLOCKED_ARCHITECT` and stop
before implementation.

### Required tests

At minimum verify:

- brokerage-account creation and household isolation;
- BUY cash/position/cost-basis effects and no expense effect;
- SELL cash/position effects, weighted-average realized P&L, and oversell block;
- BUY/SELL fee exactly-once behavior;
- dividend, standalone fee, and tax behavior;
- canonical-transfer deposit/withdrawal and P&L exclusion;
- split total-basis preservation;
- position derivation and unrealized P&L;
- missing/stale price behavior;
- multi-currency separation;
- no ordinary budget or Tithe Due effect;
- no net-worth double count;
- offline local write and outbox behavior;
- reconnect and second-device/bootstrap convergence;
- encrypted backup/restore and household clone/recovery;
- read-only Health Check integrity;
- migration upgrade paths and native/web parity;
- 5,000-activity performance sanity without O(N²).

Owner acceptance is prepared but **NOT RUN**.

### Validation gates

Use progressive validation:

1. `dart format`;
2. focused N0 tests;
3. affected D10–D13 regressions;
4. transfer regressions;
5. report/net-worth regressions;
6. Tithe regressions;
7. backup/recovery regressions;
8. sync/bootstrap regressions;
9. Health Check regressions;
10. `flutter analyze`;
11. full Flutter suite;
12. Web, Windows debug, and Android debug builds;
13. local Supabase reset/replay and focused/full pgTAP when SQL is added;
14. `git diff --check` and whole-diff review.

No hosted deployment is authorized. After validation, commit and push N0,
update durable state, and continue automatically to N1.

## BETA-08N1 — Brokerage Statement CSV Import

N1 begins only after N0 is complete. It imports broker/export CSV into reviewed
investment activities and must not route brokerage rows through ordinary bank
CSV when that loses investment semantics.

The pipeline is:

```text
source
→ normalized brokerage drafts
→ validation
→ duplicate/idempotency analysis
→ explicit review
→ atomic commit
→ ordinary sync
```

### Source and mapping

Support UTF-8 CSV with explicit source-column mapping for date, activity type,
symbol/instrument, quantity, execution price, gross amount, fee, tax, currency,
reference, and note. Do not assume one broker's headers globally. A
broker-specific preset is allowed only when deterministic and tested. Fuzzy or
AI interpretation is prohibited.

Activity values resolve explicitly to the eight N0 types. Unknown activity is
visible as `UNRESOLVED` and blocks commit for an included row; it never silently
becomes income/expense.

An existing compatible Asset Definition may be mapped explicitly. An unknown
instrument requires review with **Map to existing** or **Create compatible asset
definition**. A typo must never silently create a security. Reuse D13 duplicate
and integrity rules.

### Identity and reimport

Deterministic source identity uses household, brokerage account, source-file
fingerprint, stable source-row identity, and normalized authoritative row
fingerprint. Exact statement reimport creates no duplicate financial effects.
Review edits must not manufacture a second source identity. Do not blindly
reuse ordinary CSV transaction UUID semantics when brokerage activity is a
distinct authoritative entity.

### Source P&L evidence

Broker-provided P&L may be retained as source evidence/comparison but is not
authoritative when Pilgrim can calculate realized P&L from its accepted
weighted-average ledger. Material disagreement produces a review/reconciliation
warning and never silently overwrites Pilgrim cost basis.

### Atomicity

For an included batch, approved instrument definitions, brokerage activities,
authoritative asset/cash postings, required transfer links, and ordinary outbox
must commit atomically with no partial financial state.

### Non-goals

No brokerage API/login, trading/orders, scraping, PDF/image extraction, AI
classification, options, futures, margin, short selling, automatic tax
calculation, or unsupported corporate action is included. Broker-statement
image/PDF extraction requires a later separately accepted milestone.

### Required tests

At minimum verify canonical and externally mapped CSV; every supported activity;
unknown-activity blocking; unknown-instrument review and explicit creation; no
silent instrument/category creation; exact-reimport zero effects; source
identity stability across edits; broker-P&L mismatch warning; atomic rollback;
transfer funding; multi-currency; offline import; outbox/reconnect; new-device
bootstrap; backup/restore; and large-statement performance. Run all affected N0
and historical asset/import regressions. Owner acceptance is prepared but
**NOT RUN**.

## Post-N1 feature freeze

After N1 Engineering PASS and Git completion, feature freeze resumes. Do not
autonomously begin Portable CSV, Receivables/Advances, Account Reconciliation,
another investment feature, or hosted deployment without a current `READY`
queue item backed by an accepted contract.
