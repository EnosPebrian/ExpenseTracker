# BETA-08N Distinct Brokerage Interest — Engineering Checkpoint

**Date:** 2026-09-21

**Work item:** PT-BETA-08N1-R4

**Engineering verdict:** COMPLETE

**Owner acceptance:** PENDING / NOT RUN

**Feature freeze:** ACTIVE

## Implemented contract

`BrokerageActivityType.interest` is a distinct positive brokerage/RDN cash
activity. It requires no instrument and increases brokerage cash, net worth and
the separately reported Interest Income component. It does not alter quantity,
cost basis, average cost, realized or unrealized trading P&L, ordinary household
income/expense, Projects, budgets, or Tithe Due/Paid.

Explicit TAX remains a separate activity, so Interest 10,000 plus TAX 2,000
produces a net brokerage-cash increase of 8,000 without fabricating withholding.
Zero or negative Interest preserves its source sign in review and blocks commit;
it is never converted to a positive value, Dividend or Fee.

Exact `INTEREST` CSV activity resolves without symbol, quantity, price or split
metadata. Deterministic source/event identity and exact-reimport protection are
unchanged. Interest persists through native/web storage, restart, ordinary sync,
new-device bootstrap, encrypted backup/restore and clone. Settlement evidence
semantics remain unchanged.

## Persistence and server state

- SQLite schema: 29 (unchanged)
- encrypted backup format: v8 (unchanged)
- new Supabase migration: `20260916000331_beta08n_interest_activity.sql`
- migration scope: additive activity constraint/validation only
- local clean migration replay: PASS
- hosted deployment: NOT RUN / UNDEPLOYED
- no historical migration was edited
- no table, column, RLS-policy or client privilege change was introduced

## Verified gates

- focused Flutter tranche: 123/123 PASS
- full Flutter suite: 1014/1014 PASS
- `flutter analyze`: PASS
- Web build: PASS
- Windows debug build: PASS
- Android debug APK build: PASS
- focused pgTAP: 13/13 PASS
- full pgTAP: 339/339 PASS across 17 files
- `git diff --check`: PASS

The Android build retained the existing non-blocking `file_picker` Kotlin
compatibility warning. Local database lint also retains a historical dynamic-SQL
false positive in `begin_initial_download`; clean replay and the complete pgTAP
corpus pass.

## Remaining gates

The settlement and Interest migrations require separately authorized hosted
rollout. The owner must then execute the Windows/Android acceptance matrix in
`docs/BETA08N_OWNER_ACCEPTANCE.md`. Neither hosted deployment nor owner runtime
acceptance is implied by this engineering checkpoint.
