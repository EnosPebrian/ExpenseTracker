# Pilgrim Tracker — Engineering Handoff

This file is the durable resume point for Codex.

Update it whenever an engineering session materially changes state, especially before stopping, after validation, and after Git push.

---

## Current active work item

`PT-BETA-08N1-R3 — Durable Settlement Reconciliation Evidence`

## Current state

`IN_PROGRESS` — settlement semantics resolved by owner on 2026-09-15: durable
reconciliation evidence only, with zero independent financial effect. Interest
remains a separate repair. No hosted deployment is authorized in this work item.

## Latest pushed engineering baseline

```text
branch: main
remote: origin
commit: b4f954db39a78045c2bd271386508283343086b1
message: feat: automate trusted brokerage CSV review
push: origin/main succeeded
HEAD == origin/main: yes
post-push worktree: clean
```

## Latest completed engineering state

```text
BETA-08N1-R2 date/instrument review: VALIDATED / PUSHED
focused Flutter: 25/25 PASS
full Flutter suite: 1002/1002 PASS
analyzer: PASS
diff checks: PASS
builds: not required/rerun for this bounded item
remaining scope: settlement/interest posting BLOCKED_ARCHITECT
owner runtime acceptance: NOT RUN
BETA-08N1 brokerage CSV compatibility repair: VALIDATED / PUSHED
repair commit: 2684254c814d1bef781ffe707ab3e625c08c2f60
focused Flutter: CSV parser 27/27; brokerage import 15/15 PASS
full Flutter suite: 992/992 PASS
analyzer/builds/diff: PASS
push: origin/main succeeded on 2026-09-14 (included in R2 publication)
BETA-08N Investments UI navigation: COMPLETE
first-class destination: after Assets on desktop and mobile
sections: Overview, Brokerage Accounts, Holdings, Trades, Statements, Performance
focused Flutter: 33/33 PASS
full Flutter suite: 989/989 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
git diff --check: PASS
SQLite: 28
backup format: v7
SQL/Supabase change: none
owner visual acceptance: PENDING / NOT RUN
feature freeze: active
BETA-08N hosted rollout: PASS
BETA-08M0 migration 20260908124412: DEPLOYED
BETA-08N0 migration 20260910054452: DEPLOYED
local focused pgTAP: M0 23/23; N0 24/24 PASS
local full pgTAP: 314/314 PASS
hosted business counts preserved: yes
new severe advisor finding: no
owner acceptance: PENDING / NOT RUN
feature freeze: active
BETA-08N1 implementation: COMPLETE
SQLite: 28
backup format: v7
BETA-08N1 Supabase migration: none
focused N1 tests: 14/14 PASS
focused N0 regression: 14/14 PASS
affected import/investment tranche: 120/120 PASS
full Flutter suite: 983/983 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
git diff --check: PASS
remaining failures: 0
```

## Exact next action

R3 implementation is preserved and undergoing validation. Starting main/origin:
6dd013c283bece6a903bf9a9d7570d618bbec49e. SQLite 29, backup v8;
new migration 20260915004307 remains UNDEPLOYED.
Domain evidence tests 5/5, brokerage focused group 30/30, enhanced native/web
persistence/migration/backup/remote-apply tests 3/3 passed. Earlier affected
persistence/N0/Health Check group passed 34/34. Local clean Supabase replay
passed, focused pgTAP 12/12 and full pgTAP 326/326 passed.
Final focused brokerage/settlement group: 33/33 PASS. Analyzer: PASS after
13 missing-braces style fixes, with no suppression or test weakening.
Full Flutter suite: 1010/1010 PASS. Web, Windows debug and Android debug
builds PASS (unchanged file_picker Kotlin compatibility warning).
Local security advisor: no errors; two historical mutable-search-path warnings
for prevent_book_id_change / prevent_book_identity_change (unchanged).
Latest review explicitly prevents silently removing unavailable historical
trade links; user must confirm removal or cancel. Changed Dart files formatted.
Next: final diff check and validated Git completion. No hosted operation,
commit or push yet. Owner acceptance remains NOT RUN.

Date/instrument review changes are published under the owner's 2026-09-14
commit/push instruction. This documentation-only follow-up records the verified
implementation push and clean post-push status. Settlement semantics are resolved;
Interest remains separate in ARCH-20260914-01; do not reinterpret these
labels as trades, dividends or fees. Owner runtime acceptance remains NOT RUN.

## PT-BETA-08N-RC rollout result

```text
project: pilgrim-tracker-dev (jylclfebdeaywfdwabph)
authorized deployed chain: 20260908124412 -> 20260910054452
clean local replay: PASS
focused pgTAP: M0 23/23; N0 24/24 PASS
full pgTAP: 314/314 PASS across 15 files
recovery point: pre-beta08nrc-20260911-172323 (five non-empty hashed artifacts)
hosted deployment: PASS
hosted migration history: exact through 20260910054452
business row preservation: PASS
RLS/ACL/sync verification: PASS
new severe advisor finding: no
owner acceptance: PENDING / NOT RUN
state: BLOCKED_OWNER
branch: main
documentation commit: 4e3e5384a2d37d7c44099a42af04aa1597acea47
push result: origin/main succeeded
post-push git status: clean
```

---

## Completed sprint records

### PT-BETA-08N-UI-R1 — Investment / Brokerage UI Navigation Gap

```text
work item: PT-BETA-08N-UI-R1
verdict: COMPLETE
root cause / implementation: the complete N0/N1 ledger was buried behind the desktop overflow/mobile More route and rendered as one undifferentiated page; Investments is now first-class after Assets with six responsive sections over existing authorities
files changed: application destination/router/shell/navigation composition, Investments presentation widgets, account-editor initial type support, focused navigation/investment regressions, and targeted architecture/progress/limitations/checkpoint/handoff docs
schema/version changes: none; SQLite 28; backup v7; no SQL/Supabase migration
focused tests: 33/33 PASS
historical regressions: included app navigation, BETA-08H destination index, and BETA-08N0 investment coverage
full suite: 989/989 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged non-blocking file_picker warning
server/pgTAP if applicable: not applicable; no SQL/Supabase change
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: fd5c03d42c4949eb8db9818ab01cd605da073eec
status/documentation commit if any: this durable-state record is included in the sprint Git completion
push result: pending explicit external push authorization; local main is ahead of origin/main
final git status: clean at implementation commit before PT-BETA-08N1-R1 repair began
remaining limitations: UTF-8 CSV statements only; no broker institution metadata, APIs, advanced return metrics, or cross-currency aggregation; owner visual/runtime acceptance pending
next READY item: none; PT-BETA-08N-RC remains BLOCKED_OWNER and feature freeze is active
```

### PT-BETA-08N1 — Brokerage Statement CSV Import

```text
work item: PT-BETA-08N1
verdict: COMPLETE
root cause / implementation: added a brokerage-specific reviewed CSV adapter over the authoritative N0 ledger; explicit mapping and unresolved activity/instrument review feed deterministic event/child identities and one atomic definition/transaction/transfer/outbox commit
files changed: brokerage import domain/planner/posting/commit/controller/UI, native/web atomic repositories, Investments entry point, focused tests, and targeted architecture/import/schema/sync/checkpoint/roadmap documentation
schema/version changes: none; SQLite 28; backup v7; no N1 Supabase migration
focused tests: 14/14 PASS
historical regressions: focused N0 14/14 PASS; affected import/investment tranche 120/120 PASS; final full suite 983/983 PASS
full suite: 983/983 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged non-blocking file_picker warning
server/pgTAP if applicable: not applicable; N1 adds no SQL; no hosted action
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: 23a5e453c1856376b1b601859918134397d407e4
status/documentation commit if any: follow-up durable-state commit containing this record
push result: origin/main succeeded
final git status: clean after implementation push; durable-state update pending its follow-up commit
remaining limitations: CSV only; explicit exact instrument mapping; no cross-currency conversion; review state is in-memory; N0 hosted migration remains undeployed; owner acceptance pending
next READY item: none; accepted roadmap exhausted and feature freeze active
```

### PT-BETA-08N0 — Investment / Brokerage Ledger Foundation

```text
work item: PT-BETA-08N0
verdict: COMPLETE
root cause / implementation: added nullable brokerage attribution to the authoritative transaction ledger; reused existing asset, account, canonical-transfer, budget, Tithe, backup, and sync authorities
files changed: brokerage domain/service/UI, transaction/account/asset/reporting/backup/sync/health integration, SQLite v28 migration, one undeployed Supabase migration, focused Flutter/pgTAP tests, and targeted docs
schema/version changes: SQLite 27 -> 28; backup v6 -> v7; one additive Supabase migration remains undeployed
focused tests: 14/14 PASS
historical regressions: affected tranche 203/203 PASS
full suite: 969/969 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS
server/pgTAP if applicable: local reset PASS; focused 24/24 PASS; full 314/314 PASS; hosted deployment NOT RUN
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: 403dde8383f9e9d6e49ed7faa5e360f172527cf9
status/documentation commit if any: follow-up durable-state commit containing this record
push result: origin/main succeeded; HEAD == origin/main after implementation push
final git status: clean after implementation push; durable-state update pending its follow-up commit
remaining limitations: hosted migration undeployed; no broker CSV/API/extraction/trading/tax/advanced instruments; no cross-currency total; owner runtime acceptance pending
next READY item: PT-BETA-08N1, moved to IN_PROGRESS
```

### PT-BETA-08M-R1 — Category-commit compatibility repair

```text
work item: PT-BETA-08M-R1
verdict: COMPLETE
root cause / implementation: _prepareCategoryCommit treated every category ID as rule-backed; explicit Map provenance is now durable and only that path requires ImportRuleCategory stable-ID revalidation
files changed: BETA-08M category review/domain/controller/UI, native/web atomic repositories, focused tests, architecture/import/sync/checkpoint docs, and autonomy protocol docs
schema/version changes: none; SQLite 27; backup v6
focused tests: 294/294 PASS
historical regressions: included in 294/294; BETA-08B 9/9 and BETA-08L0 15/15 PASS
full suite: 954/954 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS
server/pgTAP if applicable: not applicable; no SQL/Supabase change
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: 1e5a97c0d3c458f4519ec7528494a3a80e438a77
status/documentation commit if any: follow-up durable-state commit containing this record
push result: origin/main succeeded
final git status: clean after implementation push; durable-state update pending its follow-up commit
remaining limitations: exact category matching only; pending Inbox state remains excluded from backup; owner runtime acceptance pending
next READY item: none; PT-AUTO-NEXT is BLOCKED_ARCHITECT by ARCH-20260910-01
```

---

## Codex session update template

```text
timestamp: 2026-09-14
work item: PT-BETA-08N1-R2
state: BLOCKED_ARCHITECT (posting behavior only; independent review work validated)
branch: main
prior implementation commit: 2684254c814d1bef781ffe707ab3e625c08c2f60
current branch tip: follow-up durable-state commit containing this record; origin/main remains 83274479a3e00bda92d8e700a6fd983fbee736b9
dirty files intentionally belonging to task: brokerage review date/model/planner/posting/commit/controller/UI, focused tests and targeted documentation
last completed substep: focused 25/25, analyzer and full suite 1002/1002 PASS; diff review complete
tests already run: brokerage automation 10/10; existing N1 15/15; full Flutter 1002/1002 PASS
current failing tests: none
root cause known?: date analysis was per-row with an epoch fallback; instrument creation required repeated row actions
next exact command/action: commit and push validated review changes; resolve ARCH-20260914-01 before new posting semantics
architecture escalation needed?: ARCH-20260914-01 for settlement/interest posting only
owner action needed?: accounting decision and runtime acceptance; Git push is authorized
```

---

## Sprint completion template

Append one record per completed work item:

```text
work item:
verdict:
root cause / implementation:
files changed:
schema/version changes:
focused tests:
historical regressions:
full suite:
analyzer:
builds:
server/pgTAP if applicable:
git diff --check:
owner acceptance status:
branch:
implementation commit:
status/documentation commit if any:
push result:
final git status:
remaining limitations:
next READY item:
```
