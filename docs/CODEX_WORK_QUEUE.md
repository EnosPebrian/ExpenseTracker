# Pilgrim Tracker — Codex Work Queue

**Queue protocol:** `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`
**Last architect seed:** 2026-09-09
**Last reconciled:** 2026-09-11

## Queue rules

Codex must:

1. resume `IN_PROGRESS` before taking new work;
2. take the highest-priority `READY` item;
3. never invent financial/product semantics;
4. fix implementation-level regressions autonomously;
5. commit and push each validated sprint;
6. update this file and `docs/ENGINEERING_HANDOFF.md`.

---

## RECENTLY COMPLETED

### PT-BETA-08M-R1 — Category-commit compatibility repair

**Priority:** P0
**State:** COMPLETE
**Type:** regression repair / completion of existing BETA-08M
**Scope expansion:** prohibited

### Known starting state

The BETA-08M implementation is preserved.

Last known clean pushed baseline before the unfinished BETA-08M work:

```text
branch: main
remote: origin
commit: f2924fba5d4b7fdc54acbb81ec05f48ecc5647c4
message: feat: complete BETA-08M0 transaction metadata foundation
```

Verified BETA-08M engineering state before Git completion:

```text
SQLite: 27
backup format: v6
BETA-08M SQL/Supabase schema changes: none
focused and historical corpus: 294/294 PASS
full Flutter suite: 954/954 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
git diff --check: PASS
remaining failures: 0
```

Repaired compatibility area:

```text
_prepareCategoryCommit
```

Previous behavior:

`_prepareCategoryCommit` incorrectly requires `ImportRuleCategory` for valid legacy/source-neutral category assignments.

Verified affected regression groups:

- BETA-08B: 9/9 PASS
- BETA-08L0: 15/15 PASS

Git completion:

```text
branch: main
implementation commit: 1e5a97c0d3c458f4519ec7528494a3a80e438a77
push: origin/main succeeded
HEAD == origin/main: yes
post-push worktree: clean
```

### Objective

Repair the compatibility regression so valid legacy/source-neutral category assignments continue to work without incorrectly requiring `ImportRuleCategory`, while preserving the intended BETA-08M category/taxonomy safety rules.

### Hard constraints

- Do not discard the existing BETA-08M implementation.
- Do not restart BETA-08M from scratch.
- Do not broaden the sprint.
- Do not weaken valid category/taxonomy validation.
- Do not remove or rewrite historical regression tests merely to make them pass.
- Do not add SQL/Supabase changes unless existing accepted BETA-08M documentation explicitly requires them.
- Preserve SQLite version 27 and backup v6 unless an existing accepted BETA-08M requirement proves otherwise.
- Preserve local-first financial behavior.
- Preserve import-review-before-commit behavior.
- Preserve deterministic identity/duplicate behavior.

### Required diagnosis

Codex must first identify:

1. why `_prepareCategoryCommit` treats legacy/source-neutral assignments as rule-backed assignments;
2. the smallest distinction needed between:
   - category chosen/retained from legacy or source-neutral review data; and
   - category assignment that genuinely depends on an `ImportRuleCategory`;
3. whether the bug is in validation, normalization, commit preparation, or an overly broad invariant.

### Acceptance criteria

At minimum:

- the 22/22 new BETA-08M focused tests continue to pass;
- all 122 historical focused regression tests pass;
- the 3 BETA-08B regressions pass;
- the 1 BETA-08L0 regression passes;
- no valid BETA-08M taxonomy protection is weakened;
- `flutter analyze` passes;
- full Flutter suite passes;
- applicable build checks from the current BETA-08M sprint pass;
- `git diff --check` passes;
- BETA-08M docs/checkpoint are updated truthfully;
- no owner runtime acceptance is falsely marked complete;
- intended changes are committed and pushed;
- final worktree is clean.

### Completion report

Record in `docs/ENGINEERING_HANDOFF.md`:

- root cause;
- repair approach;
- files changed;
- focused test result;
- historical regression result;
- full suite result;
- analyzer result;
- build result;
- SQLite version;
- backup version;
- SQL/Supabase change status;
- branch;
- commit hash;
- push result;
- final `git status --short`.

---

## ACTIVE

### PT-AUTO-NEXT — Derive the next accepted milestone

**Priority:** P1
**State:** COMPLETE

After BETA-08M is fully complete:

1. read the latest project progress/checkpoint/roadmap documents;
2. identify the next unfinished milestone that is already accepted and sufficiently specified;
3. create a concrete queue item above this section;
4. give it explicit scope, non-goals, architecture references, and acceptance criteria;
5. mark it `READY`;
6. execute it under the autonomous protocol.

Do not select a milestone merely because it appears in an obsolete historical roadmap.

Prefer the newest accepted checkpoint/progress state.

If multiple roadmaps conflict, create `BLOCKED_ARCHITECT` instead of guessing.

### Resolution

`ARCH-20260910-01` selected Option B on 2026-09-10. BETA-08M is complete;
Portable CSV moved to neutral future backlog; BETA-08N0 and BETA-08N1 are the
accepted investment/brokerage sequence.

---

### PT-BETA-08N0 — Investment / Brokerage Ledger Foundation

**Priority:** P0
**State:** COMPLETE
**Type:** product foundation / additive local-first financial subledger
**Architecture contract:** `docs/BETA08N_INVESTMENT_BROKERAGE_CONTRACT.md`

#### Scope

Implement the N0 persistence/domain foundation, manual brokerage activities,
reuse of existing asset accounting, brokerage cash and positions, investment
performance, net-worth integration, encrypted backup/restore/clone, ordinary
sync/bootstrap, read-only Health Check diagnostics, and responsive
Windows/Android/web-preview UI.

#### Non-goals

No broker CSV import, extraction/AI, brokerage API or order placement, quote
provider expansion, tax-law calculation, options/futures/margin/shorts,
security transfers, unsupported corporate actions, or hosted deployment.

#### Required first step

Complete the N0 engineering analysis in the architecture contract before schema
design. Reuse D10–D13 authority. If the contract would require two competing
accounting truths, create `BLOCKED_ARCHITECT` before implementation.

#### Completion gate

All N0 required tests and applicable D10–D13, transfer, reporting/net-worth,
Tithe, backup/recovery, sync/bootstrap, Health Check, migration, pgTAP, analyzer,
full-suite, platform-build, diff-review, commit, and push gates in the contract
must pass. Owner acceptance is prepared but remains **NOT RUN**.

---

### PT-BETA-08N1 — Brokerage Statement CSV Import

**Priority:** P1
**State:** COMPLETE
**Depends on:** PT-BETA-08N0 COMPLETE
**Architecture contract:** `docs/BETA08N_INVESTMENT_BROKERAGE_CONTRACT.md`

Implement explicit mapped/reviewed/idempotent brokerage-activity CSV import
only after N0 completes. Preserve source identity, explicit unresolved activity
and instrument review, atomic authoritative postings, and local-first sync.
Do not implement any N1 out-of-scope provider, extraction, AI, trading, tax, or
advanced instrument behavior.

#### Completion

Implemented reviewed UTF-8 CSV mapping for all eight N0 activities, explicit
unresolved activity/instrument resolution, deterministic UUIDv5 event/child
identity, indexed duplicate review, broker-P&L comparison, and atomic
definition/transaction/transfer/outbox persistence. SQLite remains v28, backup
remains v7, and no N1 migration was added. Focused tests passed 14/14; full
Flutter passed 983/983; analyzer and Web/Windows/Android debug builds passed.
Owner acceptance remains **NOT RUN**.

### PT-FEATURE-FREEZE — Accepted roadmap exhausted

**State:** COMPLETE

BETA-08N0 and BETA-08N1 are complete. No further item is `READY`. Feature
freeze is active; Portable CSV, Receivables/Advances, Account Reconciliation,
additional investment work, and hosted deployment require a new accepted
contract or explicit owner/architect authority.

---

## ACCEPTED PRODUCT BACKLOG — NOT AUTOMATICALLY READY

The following capabilities are within the reopened product-development scope but must not be invented from this queue alone:

- Receivables / Advances
- Account Reconciliation
- Human-editable Portable CSV

They may become autonomous work items only after the repository contains enough accepted domain behavior and acceptance criteria to implement them safely.

---

## OWNER GATES

Owner/runtime acceptance from earlier BETA milestones may remain pending.

Codex must not mark a pending owner gate complete without actual owner execution.

Owner gates do not prevent Codex from continuing independent engineering work unless the next milestone explicitly depends on that acceptance.
