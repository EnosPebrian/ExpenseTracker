# Pilgrim Tracker — Engineering Handoff

This file is the durable resume point for Codex.

Update it whenever an engineering session materially changes state, especially before stopping, after validation, and after Git push.

---

## Current active work item

`PT-BETA-08N-RC — BETA-08N Hosted Rollout & Owner Acceptance Preparation`

## Current state

`BLOCKED_OWNER`

## Latest pushed engineering baseline

```text
branch: main
remote: origin
commit: 4e3e5384a2d37d7c44099a42af04aa1597acea47
message: docs: close BETA-08N hosted rollout
push: origin/main succeeded
HEAD == origin/main: yes
post-push worktree: clean
```

## Latest completed engineering state

```text
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

Owner runs `BETA08N_OWNER_ACCEPTANCE.md` on physical Windows and Android using
disposable data and records each PASS/FAIL field. Hosted rollout is complete;
do not add product features or mark owner acceptance PASS automatically.

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

Replace this section during active work:

```text
timestamp:
work item:
state:
branch:
HEAD:
dirty files intentionally belonging to task:
last completed substep:
tests already run:
current failing tests:
root cause known?:
next exact command/action:
architecture escalation needed?:
owner action needed?:
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
