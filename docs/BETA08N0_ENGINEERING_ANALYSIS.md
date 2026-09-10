# BETA-08N0 Engineering Analysis

**Date:** 2026-09-10
**Work item:** PT-BETA-08N0
**Architecture contract:** `docs/BETA08N_INVESTMENT_BROKERAGE_CONTRACT.md`

## Decision

BETA-08N0 can be implemented without creating a competing accounting truth.
The existing `Transaction` entity remains the authoritative economic record,
existing canonical transfer links remain the authority for owned-account
funding, and `AssetPortfolioCalculator` remains the authority for quantity,
weighted-average cost basis, and realized/unrealized gain.

Brokerage support will add stable attribution and the minimum activity metadata
to those records. It will not persist a second editable position, cost basis,
cash balance, or gain total.

## Required D10-D13 reuse answers

### 1. Existing owner of BUY and SELL accounting

`Transaction` with `TransactionType.assetConversion` and an explicit
`AssetAction.buy` or `AssetAction.sell` is the existing authoritative BUY/SELL
record. `AssetDefinition.id` is the concrete instrument identity. New brokerage
trades continue to use this representation and gain stable brokerage-account
attribution; no parallel trade row is introduced.

### 2. Weighted-average cost-basis authority

`AssetPortfolioCalculator` is the single weighted-average authority. It orders
asset transactions with `AssetTransactionIdentity`, adds BUY cost using
`AssetTradeFeeAccounting.buyCostContribution`, removes average cost on SELL,
and preserves the D12/D13 numeric and definition-identity policies.

### 3. Realized and unrealized authority

`AssetPortfolioCalculator` owns realized and unrealized calculations. Brokerage
performance consumes its derived portfolio results. It does not recalculate
trade gain independently. Dividend income and standalone investment costs are
separate cash-performance components and are not folded into trade gain.

### 4. Cash-settlement representation

- BUY/SELL continue using the asset-conversion account route and amount/fee
  fields. `AccountBalanceCalculator` applies their existing cash effects.
- DIVIDEND, standalone FEE, and TAX use one authoritative investment transaction
  whose subtype determines its positive or negative brokerage-cash effect.
- DEPOSIT/WITHDRAWAL between owned accounts use the existing two transaction
  legs plus one authoritative `InternalTransferLink`; linked legs remain
  excluded from household income, expense, budgets, return, and Tithe Due.
- SPLIT has no cash effect.

### 5. Existing Account as brokerage cash

Yes. `Account` already has stable UUID identity, household ownership, explicit
currency, opening balance, lifecycle/version/device metadata, local SQLite/web
parity, outbox synchronization, backup, restore, and bootstrap support. Adding a
`brokerage` enum value does not require a competing cash model or a new account
table. Brokerage transactions persist `brokerageAccountId` so historical
attribution does not depend on the mutable display name.

### 6. D12 fee representation

BUY fees remain capitalized into basis and SELL fees remain deducted from sale
proceeds through `AssetTradeFeeAccounting`. The brokerage workflow does not use
the existing `recordAsSeparateExpense` treatment because that creates an
ordinary budget expense. A standalone broker FEE is instead an investment-cost
transaction. These paths are mutually exclusive so one fee has one effect.

### 7. Net-worth inclusion

Position market value remains derived from the existing asset portfolio and is
therefore already one asset truth. Brokerage cash remains the balance of the
brokerage `Account`. The investment/net-worth projection combines those two
inputs once, grouped by currency. It never adds a second stored position or
includes BUY/SELL principal as income. Values in different currencies are not
summed.

### 8. Required new fields or relations

No new authoritative entity is required. The existing `transactions` row needs
only nullable, stable brokerage metadata:

```text
brokerage_account_id       stable Account.id attribution
brokerage_activity_type    BUY/SELL/DIVIDEND/FEE/TAX/DEPOSIT/WITHDRAWAL/SPLIT
split_numerator            positive integer for SPLIT only
split_denominator          positive integer for SPLIT only
```

`AccountType.brokerage` identifies brokerage cash accounts using the existing
`accounts.account_type` text column. The transaction metadata is nullable for
all historical/non-brokerage transactions. New brokerage activities require
the metadata to be internally coherent and same-household at domain, local
integrity, Health Check, and hosted-database validation boundaries.

## Activity mapping

| Brokerage activity | Authoritative representation | Ordinary reporting |
| --- | --- | --- |
| BUY | asset-conversion transaction, BUY | excluded |
| SELL | asset-conversion transaction, SELL | excluded |
| DIVIDEND | investment transaction, positive cash effect | excluded |
| FEE | investment transaction, negative cash effect | excluded |
| TAX | investment transaction, negative cash effect | excluded |
| DEPOSIT | canonical internal transfer into brokerage account | excluded |
| WITHDRAWAL | canonical internal transfer out of brokerage account | excluded |
| SPLIT | asset-conversion transaction, ratio metadata, zero cash | excluded |

## Persistence and compatibility plan

- SQLite advances from v27 to v28 with additive nullable transaction columns
  and an index on `brokerage_account_id`; all existing rows remain unchanged.
- The in-memory web store round-trips the same record fields.
- One additive Supabase migration extends `public.transactions`, its reference
  validation, sync/change-feed column allowlists, and initial-sync projection.
  Existing transaction RLS and grants remain authoritative.
- Encrypted backup advances from v6 to v7 because transaction rows gain
  authoritative brokerage metadata. v1-v6 decoding remains supported; absent
  brokerage fields resolve to null.
- Clone remaps `brokerage_account_id`; exact restore preserves it; invalid or
  cross-household references are rejected.
- Existing transaction UUID and import fingerprint rules are unchanged.

## Split semantics

`SPLIT` extends the existing asset history rather than creating an editable
position. A positive integer numerator/denominator multiplies the then-current
quantity while total cost basis and realized gain remain unchanged. The
chronological sequence validator applies the same transformation before later
SELL validation. Cash-in-lieu and fractional disposal remain unsupported.

## Multi-currency and performance

A brokerage account and its instruments must share the account settlement
currency for N0 manual activities. Performance and net worth are returned as
separate currency buckets. No FX conversion or cross-currency total is
fabricated. Current price compatibility and unavailable/stale presentation
continue to use existing asset-price metadata.

## Architecture gate result

**PASS — implementation may proceed.** The design reuses the existing asset,
account, transfer, transaction, outbox, backup, and sync authorities and does
not create two competing accounting truths.
