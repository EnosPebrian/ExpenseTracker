# BETA-08N0 Completion Checkpoint

**Engineering status:** PASS
**Owner acceptance:** NOT RUN
**Date:** 2026-09-10

BETA-08N0 adds a brokerage ledger foundation without creating a second
financial truth. Existing `Transaction`, canonical internal-transfer, `Account`,
`AssetDefinition`, `AssetPortfolioCalculator`, and ordinary outbox/sync paths
remain authoritative. Brokerage attribution is nullable metadata on the
authoritative transaction row; positions, cash, cost basis, realized gain, and
unrealized gain remain derived.

The supported manual activities are BUY, SELL, DIVIDEND, FEE, TAX, DEPOSIT,
WITHDRAWAL, and SPLIT. Trades reuse weighted-average asset accounting and its
fee rules. Funding reuses canonical transfers. Investment principal,
performance, dividends, fees, taxes, and funding do not enter ordinary category
budgets or `TithePolicy`. Currency totals remain separated.

SQLite advances from 27 to 28 with four nullable transaction fields:
`brokerage_account_id`, `brokerage_activity_type`, `split_numerator`, and
`split_denominator`. Encrypted backup advances from v6 to v7; v1-v6 remain
readable. One additive, locally verified Supabase migration was created but was
not deployed. Existing transaction RLS and the frozen sync architecture remain
in force.

The responsive Investments page shows per-currency investment net worth,
brokerage cash, position value, realized/unrealized performance, account
positions, and recent activity. Health Check validates attribution and
household boundaries without mutation. Exact restore, household clone,
reconnect, initial sync, old-client payloads, and conflict review preserve the
new metadata safely.

Validation completed:

- focused BETA-08N0 tests: 14/14 PASS;
- affected regression tranche: 203/203 PASS;
- focused BETA-08N0 pgTAP: 24/24 PASS;
- full Flutter suite: 969/969 PASS;
- full pgTAP suite: 314/314 PASS across 15 files;
- `flutter analyze`: PASS;
- Web build: PASS;
- Windows debug build: PASS;
- Android debug APK build: PASS;
- `git diff --check`: PASS.

No hosted migration, Edge Function, secret, broker API, trading/order flow,
broker CSV import, AI extraction, tax calculation, margin, short, option,
future, or unsupported corporate-action feature was added. BETA-08N1 is the
separate accepted statement CSV milestone. Owner/runtime acceptance remains
**NOT RUN**.
