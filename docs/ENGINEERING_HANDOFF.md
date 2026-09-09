# Pilgrim Tracker — Engineering Handoff

This file is the durable resume point for Codex.

Update it whenever an engineering session materially changes state, especially before stopping, after validation, and after Git push.

---

## Current active work item

`PT-BETA-08N0 — Investment / Brokerage Ledger Foundation`

## Current state

`READY`

## Latest pushed engineering baseline

```text
branch: main
remote: origin
commit: bf46d2b5cddf1a5d9f4a5e1452c6594c699db2c7
message: docs: record BETA-08M completion and next blocker
push: origin/main succeeded
HEAD == origin/main: yes
post-push worktree: clean
```

## Latest completed engineering state

```text
BETA-08M implementation: preserved
SQLite: 27
backup format: v6
BETA-08M SQL/Supabase changes: none
focused and historical corpus: 294/294 PASS
full Flutter suite: 954/954 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
git diff --check: PASS
remaining failures: 0
```

Repaired compatibility point:

```text
_prepareCategoryCommit
```

Root cause and repair:

`_prepareCategoryCommit` treated all category IDs as if they came from an
explicit source-category Map choice. Explicit Map intent is now persisted and
tracked separately, so only that path requires `ImportRuleCategory` stable-ID
revalidation. Legacy, source-neutral, and manual assignments retain their
existing validation path.

## Exact next action

After the architecture reconciliation commit is pushed, inspect D10–D13 and
explicitly determine the eight N0 reuse questions in
`docs/BETA08N_INVESTMENT_BROKERAGE_CONTRACT.md` before designing schema.
Owner/runtime acceptance for BETA-08M remains **NOT RUN**.

---

## Completed sprint records

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
