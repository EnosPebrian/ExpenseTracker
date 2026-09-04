# Monthly Household Category Budgets

BETA-07A provides one active positive integer limit per household, expense
category, and local calendar month (`YYYY-MM-01`). It uses the book base
currency and optional notes up to 120 characters. Removing a budget creates a
tombstone; safely re-adding the same category/month reuses that identity.

BETA-07B adds an explicit **Copy budgets** workflow. The selected source and
target are distinct normalized local months. Copying preserves each active
source budget's category, positive integer limit, base currency, and optional
note while assigning a new target-month record identity. It copies plan
definitions only: spending, progress, and derived percentages are never copied.

Copy mode is add-missing-only. An active budget already present for a target
category is reported as already present and is never overwritten. A repeated
copy therefore creates no duplicate rows or outbox operations. Archived or
soft-deleted categories remain visible in preview but are skipped with an
explanation; genuinely missing categories are warned and skipped. Cross-book
references are fatal integrity errors.

## Spending semantics

The calculation includes active expense transactions dated in the selected
local month. Separate linked fee-expense rows count because existing reporting
classifies them as expenses. It excludes income, transfers, opening balances,
asset conversions, deleted rows, and other months. Household totals do not vary
by account owner or entered-by member. No exchange rate is invented.

For each budget, `remaining = max(limit - spent, 0)` and
`overspent = max(spent - limit, 0)`. Under 80% is On track, 80% through below
100% is Near limit, and 100% or above is Overspent/Limit reached. Qualifying
expense transactions in categories without an active budget are unbudgeted
spending. Zero totals are safe.

## Lifecycle and portability

Archived category budgets remain readable with a historical label; new budgets
require an active expense category. SQLite v21 and Supabase synchronize stable
IDs, versions, tombstones, and explicit conflicts through the existing
protocol. Backup format v2 includes `budgets.json`; v1 restores safely without
implying budget deletion. CSV ZIP export includes deterministic `budgets.csv`.
For linked households, copied rows and their ordinary budget outbox operations
commit together in one SQLite transaction. Local-only copying uses the same
atomic row path without outbox work. No rollover or carryover is implied.

## Owner acceptance

Deployment automation completed on 2026-08-03: the hosted migration is applied,
local/remote histories agree, 81 pgTAP assertions pass, configured Windows/APK/
AAB releases build, and the APK owner certificate verifies. The owner runtime
checks below are still **NOT RUN**; see `BETA07_ACCEPTANCE_RESULTS.md`.

1. Upgrade an existing Windows database and confirm all prior records remain.
2. Create, edit, remove, and safely re-add budgets on Windows and Android.
3. Verify current/previous/next month navigation and the current-month action.
4. From a target month, preview a source month containing active, already-present,
   archived, and missing-category cases; confirm the displayed classifications
   and expected target total.
5. Cancel once and confirm nothing changes, then copy and confirm only missing
   category plans appear immediately with limits/notes preserved.
6. Repeat the same copy and confirm zero additions, no overwritten target values,
   and no duplicate synchronization activity.
7. Check on-track, near-limit, overspent, no-spending, and unbudgeted totals;
   confirm copied plans did not copy source-month spending.
8. Confirm copied rows synchronize to another device and persist after close/reopen.
9. Exercise a budget edit conflict and review Keep shared/Keep device/manual merge.
10. Create and validate a v2 encrypted backup, restore it locally, and verify totals.
11. Preview/restore a v1 backup and confirm existing replacement budgets survive.
12. Export CSV and inspect `budgets.csv` and budget rows in `summary.csv`.

BETA-07A/B are implemented and deployed at the schema/artifact level, but remain
unreleased until these owner runtime checks are accepted.
