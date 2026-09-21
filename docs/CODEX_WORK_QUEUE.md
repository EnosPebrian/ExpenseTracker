# Pilgrim Tracker — Codex Work Queue

**Queue protocol:** `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`
**Last architect seed:** 2026-09-09
**Last reconciled:** 2026-09-21

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

### PT-BETA-08N-R5 — Settlement + Interest Hosted Rollout

**Priority:** P0
**State:** BLOCKED_OWNER
**Authority:** Lead Architect / owner hosted-rollout authorization, 2026-09-21
**Scope:** release/acceptance rollout only; feature freeze remains active

Validate and deploy only the ordered migrations
`20260915004307_brokerage_settlement_evidence.sql` and
`20260916000331_beta08n_interest_activity.sql` to the existing linked Pilgrim
Tracker project after clean local replay, focused/full pgTAP, privacy-safe hosted
baseline checks, a fresh verified logical recovery point, advisor comparison and
exact migration-history review. Reconcile documentation after hosted PASS, leave
owner acceptance PENDING / NOT RUN, create no feature READY item, and stop as
`BLOCKED_OWNER`.

The two feature migrations and the separately authorized additive ACL migration
`20260921144802` deployed successfully. Existing business counts were preserved.
Authenticated settlement privileges are now SELECT/INSERT/UPDATE with no direct
DELETE; versioned tombstone sync, reconciliation, RLS, household isolation and
zero-financial-effect checks passed locally and hosted. Full local pgTAP passed
352/352 and hosted focused checks passed 38/38. Owner acceptance remains NOT RUN;
the next owner action is the real 125-row RDN CSV on Windows. Feature freeze
remains active and no feature item is READY.

### PT-BETA-08N1-R4 — Distinct Brokerage Interest Activity

**Priority:** P0
**State:** COMPLETE
**Authority:** ARCH-20260914-01 Interest portion, 2026-09-16
**Scope:** bounded BETA-08N owner-acceptance repair; feature freeze remains active

Implement `INTEREST` as positive brokerage/RDN cash interest: a distinct
investment activity with no instrument, no asset/cost-basis/trading-P&L effect,
no ordinary household income/expense, no budget/Project/Tithe effect, and a
separate Interest Income performance component. Negative or zero Interest stays
reviewable but blocks commit without absolute-value coercion or Fee conversion.
Preserve deterministic import identity, exact reimport, local-first persistence,
sync/bootstrap, backup/recovery and settlement evidence. Add only the minimum
Supabase constraint/validation migration; do not deploy hosted changes.

Validate focused Interest, N0/N1, settlement, performance, Tithe, budget/report,
sync/bootstrap, backup/restore and Health Check regressions, then analyzer, full
Flutter suite, Web/Windows/Android debug builds, local replay/pgTAP, diff review,
commit and normal push. Owner acceptance remains NOT RUN.

Engineering validation completed: focused Flutter 123/123, full Flutter
1014/1014, analyzer, Web/Windows/Android debug builds, clean local Supabase
replay, focused pgTAP 13/13, full pgTAP 339/339, and diff checks passed. SQLite
remains 29 and backup remains v8. Migration `20260916000331` is locally verified
and was deployed by R5 on 2026-09-21. The follow-up settlement ACL hardening also
passed. Owner acceptance remains PENDING / NOT RUN and feature freeze remains
active.

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

### PT-BETA-08N1-R3 — Durable Settlement Reconciliation Evidence

**State:** COMPLETE
**Authority:** Lead Architect / owner settlement decision, 2026-09-15.

BUY_SETTLEMENT and SELL_SETTLEMENT are reviewed, durable non-financial evidence.
Preserve source identity/date/amount/type/reference/note. Support unmatched and
explicitly reconciled evidence with many-to-many trade relationships. Never
post cash, holdings, basis, P&L, income/expense, budget, net-worth or Tithe effects.
BUY/SELL stay authoritative. Preserve local-first atomicity, duplicate protection,
native/web persistence, sync and recovery compatibility. No hosted deployment.
Interest remains a separate real-activity repair, never a dividend alias.
Validate focused regressions, analyzer, full Flutter and applicable local SQL gates
before Git publication; owner runtime acceptance remains NOT RUN.

Validated and pushed: 8ac408b155ae5e3d3db7dd71152e5fa4c067effb.
Focused Flutter 33/33; full 1010/1010; analyzer and Web/Windows/Android debug
builds PASS. Local replay and pgTAP 326/326 PASS. SQLite 29, backup v8.
Hosted migration and settlement DELETE-ACL hardening passed under R5 on
2026-09-21. Owner acceptance NOT RUN.

### PT-BETA-08N1-R2 — Trusted Brokerage Review Automation

**State:** COMPLETE (Interest policy implemented in R4; hosted ACL blocker is tracked in R5)
**Authority:** owner request, 2026-09-14, including normal commit/push.

Implement whole-column date detection, nullable unresolved review dates,
case-insensitive catalog matching, statement-level trusted IDX staging,
activity-dependent instrument requirements and clear review states. Preserve
atomic creation, offline operation and deterministic duplicate protection.
Focused tests: 25/25 PASS. Analyzer PASS; full suite 1002/1002 PASS.
Date/instrument review implementation is validated and pushed to origin/main:
`b4f954db39a78045c2bd271386508283343086b1`; post-push worktree clean.
No platform builds were required or rerun for this bounded item.
No schema or hosted changes. Settlement/Interest posting semantics remain an
open decision in ARCH-20260914-01; all independent review work may continue.

---

### PT-BETA-08N1-R1 — Brokerage CSV Exact-Money/Header Compatibility

**Priority:** P0
**State:** BLOCKED_OWNER
**Type:** bounded owner-reported import compatibility repair
**Authority:** explicit owner instruction, 2026-09-12

Accept lossless trailing-zero decimal notation for zero-decimal currencies and
recognize Pilgrim's own human-readable brokerage header labels. Preserve exact
integer accounting, the eight accepted brokerage activity types, explicit
unknown activity/instrument review, and all existing atomic/idempotent commit
behavior. Do not infer rounding or map settlement/interest activity to a
different financial meaning.

Local engineering validation:

```text
focused Flutter: CSV parser 27/27; brokerage import 15/15 PASS
full Flutter: 992/992 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
SQLite: 28
backup: v7
SQL/Supabase change: none
git diff --check: PASS
owner runtime re-test: NOT RUN
Git completion: pending explicit external push authorization
```

---

### PT-BETA-08N-UI-R1 — Investment / Brokerage UI Navigation Gap

**Priority:** P0
**State:** COMPLETE
**Type:** bounded navigation / presentation repair
**Authority:** explicit owner sprint contract, 2026-09-11

Expose the already-complete BETA-08N0/N1 brokerage ledger as a first-class
`Investments` destination immediately after `Assets`, with responsive internal
Overview, Brokerage Accounts, Holdings, Trades, Statements, and Performance
tabs. Reuse the existing account editor, brokerage activity service,
performance calculator, and reviewed brokerage CSV importer. Do not introduce
new financial calculations, persistence, migrations, price APIs, parsers, or a
second investment ledger. Validate navigation order/selection, zero-data and
existing-data states, responsive behavior, focused/full Flutter tests,
analyzer, required platform builds, and Git diff before commit/push. Owner
visual acceptance remains **NOT RUN**.

Completion:

```text
focused Flutter: 33/33 PASS
full Flutter: 989/989 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
SQLite: 28
backup: v7
SQL/Supabase change: none
owner visual acceptance: NOT RUN
next READY item: none; feature freeze active
```

---

### PT-BETA-08N-RC — BETA-08N Hosted Rollout & Owner Acceptance Preparation

**Priority:** P0
**State:** BLOCKED_OWNER
**Type:** release engineering / hosted rollout / owner-acceptance preparation
**Feature scope:** frozen; no new product features

Deploy only the explicitly authorized ordered BETA-08M0 prerequisite and
BETA-08N0 Supabase migrations after clean local replay, focused/full pgTAP,
privacy-safe hosted baseline checks, a verified logical recovery point,
migration-history/dry-run review, destructive-operation review, and project-
identity confirmation. After deployment, verify schema, RLS, ACLs, household
isolation, ordinary sync compatibility, hosted row preservation, and security
advisors. Prepare one practical Windows/Android BETA-08N acceptance checklist
without marking owner acceptance as run.

Stop as `BLOCKED_OWNER` after successful rollout and Git completion because
physical-device/runtime acceptance remains owner-only. Preserve the feature
freeze and do not create another product `READY` item.

#### Current blocker

Hosted rollout is complete: the exact ordered BETA-08M0 then BETA-08N0 chain
passed clean replay, focused/full pgTAP, recovery, dry-run, deployment, hosted
schema/data/RLS/ACL/sync checks, and advisor comparison. BETA-08N owner runtime
acceptance is now the only remaining step and is **PENDING / NOT RUN**. Execute
`BETA08N_OWNER_ACCEPTANCE.md` on physical Windows and Android devices; feature
freeze remains active.

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

BETA-08N0 and BETA-08N1 are complete. Feature freeze remains active while the
non-feature PT-BETA-08N-RC item awaits owner runtime acceptance. Portable CSV,
Receivables/Advances, Account Reconciliation, and additional investment work
still require a new accepted contract or explicit owner/architect authority.

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
