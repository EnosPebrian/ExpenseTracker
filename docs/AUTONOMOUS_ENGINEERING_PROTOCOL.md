# Pilgrim Tracker — Autonomous Engineering Protocol

**Protocol version:** 1.0
**Adopted:** 2026-09-09
**Project:** Pilgrim Tracker
**Repository:** `D:\ExpenseTracker`
**Default integration branch:** `main`

## 1. Purpose

This protocol changes the development model from a human relay loop into a repository-driven engineering loop.

The owner is no longer expected to copy messages between the Architect and Codex after every sprint.

The operating model is:

```text
OWNER
  ↓ product intent / owner-only decisions
ARCHITECTURE CONTRACTS IN REPOSITORY
  ↓
CODEX ENGINEER
  ↓
implementation → validation → documentation → commit → push
  ↓
next READY work item
```

Codex must continue through independently executable engineering work without requesting a new prompt after each completed sprint.

This protocol does **not** authorize Codex to invent product scope, financial semantics, security rules, or destructive migrations.

---

## 2. Roles and authority

### Owner

The owner retains final authority over:

- product intent where the repository does not already define it;
- owner/runtime acceptance on real devices;
- real credentials, secrets, paid providers, and production accounts;
- production/hosted deployment when an explicit owner gate exists;
- irreversible or destructive data decisions;
- release acceptance.

The owner is **not** the normal messenger between architecture and engineering.

### Lead Architect

The Lead Architect owns:

- product architecture;
- domain boundaries;
- financial/accounting semantics;
- local-first and offline-first guarantees;
- persistence and synchronization invariants;
- security boundaries;
- milestone definitions;
- acceptance criteria;
- decisions about whether a requested change is architectural or implementation-only.

The repository is the durable communication channel for architectural decisions.

Codex must treat the current repository documentation as the Architect's executable contract.

### Codex Engineer

Codex owns:

- repository inspection;
- bounded implementation;
- implementation-level design choices that do not change accepted architecture;
- tests;
- regression repair caused by the active work;
- formatting and analysis;
- platform/build validation required by the work item;
- documentation updates;
- Git diff review;
- commit and push after successful validation;
- maintaining the work queue and engineering handoff state.

Codex may work continuously through READY items without asking the owner for a new prompt.

---

## 3. Source-of-truth hierarchy

When instructions conflict, use this precedence:

1. explicit owner decision recorded in the repository;
2. `docs/AGENTS.md`;
3. accepted architecture/security/domain decision records;
4. `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`;
5. current work item in `docs/CODEX_WORK_QUEUE.md`;
6. current checkpoint/progress documents;
7. roadmap/backlog;
8. implementation convenience.

A lower source may never silently override a higher source.

If two higher-authority sources conflict materially, create an architectural escalation and stop the affected task.

---

## 4. Mandatory startup sequence

At the start of every Codex session, including after a usage-limit interruption:

1. enter `D:\ExpenseTracker`;
2. inspect `git status --short`;
3. inspect branch and remote;
4. fetch remote state when network/authentication permits;
5. read `docs/AGENTS.md`;
6. read this protocol;
7. read `docs/CODEX_WORK_QUEUE.md`;
8. read `docs/ENGINEERING_HANDOFF.md`;
9. read architecture/domain/security documents relevant to the active item;
10. resume an existing `IN_PROGRESS` item before taking new work.

A usage-limit interruption does **not** cancel the active work item.

On the next available Codex session, resume from repository state without asking the owner to restate the task.

Never discard a dirty worktree merely because the previous Codex session ended.

---

## 5. Work-item states

Allowed states:

- `READY`
- `IN_PROGRESS`
- `VALIDATING`
- `BLOCKED_ENGINEERING`
- `BLOCKED_ARCHITECT`
- `BLOCKED_OWNER`
- `COMPLETE`
- `SUPERSEDED`

Rules:

- There may be only one primary `IN_PROGRESS` work item unless the queue explicitly marks items as independent.
- Resume `IN_PROGRESS` before selecting `READY`.
- Select the highest-priority `READY` item.
- `BLOCKED_ENGINEERING` means Codex should continue diagnosing/fixing without asking the owner, unless the blocker crosses an escalation boundary.
- `BLOCKED_ARCHITECT` requires an architecture decision.
- `BLOCKED_OWNER` requires real-world owner action or a product decision unavailable from the repository.
- `COMPLETE` requires the validation and Git completion gates below.

---

## 6. Decisions Codex may make autonomously

Codex may decide and implement without escalation when the change:

- preserves observable financial semantics;
- preserves stored-data meaning;
- preserves public contracts unless the active item explicitly changes them;
- preserves local-first/offline-first behavior;
- preserves native/web parity requirements;
- preserves accepted synchronization identity;
- is a bounded bug fix;
- is a refactor with no material behavior change;
- adds or strengthens tests;
- improves error handling without changing accepted policy;
- improves performance without weakening correctness;
- repairs compatibility regressions introduced by active work;
- updates documentation to match verified behavior.

When multiple implementation choices are valid, prefer:

1. the smallest change;
2. reuse of existing domain/repository/service abstractions;
3. deterministic behavior;
4. explicit validation;
5. backward compatibility;
6. testability;
7. minimal token and diff size.

---

## 7. Mandatory architecture escalation

Codex must not guess when a task requires any of the following:

- new or changed accounting/financial semantics;
- reinterpretation of historical transactions;
- new transaction identity semantics;
- a change to deterministic IDs, fingerprints, or duplicate identity;
- destructive or lossy migration;
- changes to conflict-resolution policy;
- changes to sync authority or household/member authorization;
- weakening of local-first behavior;
- bypassing explicit user review before financial commit;
- new security/trust boundaries;
- new external system with write authority over financial records;
- framework migration with broad architectural effect;
- product-scope addition/removal not already approved;
- contradictory architecture documents.

When blocked, write a concise entry to `docs/ARCHITECT_ESCALATIONS.md`.

Do not use the owner as a relay for ordinary implementation questions.

---

## 8. Owner-only gates

Codex must use `BLOCKED_OWNER` only when the remaining step genuinely requires the owner, such as:

- real Android/Windows/device acceptance;
- signing keys or upload keystore;
- production secrets or credentials;
- real provider account access;
- production deployment approval where explicitly gated;
- destructive production data action;
- a subjective product choice with no architectural rule.

Automated tests are not a substitute for owner runtime acceptance, and owner runtime acceptance must never be marked complete unless actually performed.

---

## 9. Engineering execution loop

For each work item:

### A. Establish baseline

- inspect status and diff;
- identify whether unfinished changes belong to the active item;
- read the relevant checkpoint and architecture;
- identify exact acceptance criteria.

### B. Implement bounded scope

- edit only necessary files;
- avoid unrelated cleanup;
- preserve accepted abstractions;
- add tests with the implementation;
- keep migration/native/web/sync parity when applicable.

### C. Validate progressively

Run the smallest relevant validation first, then expand.

Typical progression:

1. formatter;
2. focused tests;
3. affected historical regression tests;
4. analyzer;
5. full Flutter suite when the item can affect shared behavior;
6. web/Windows/Android builds when required by the work item or architecture;
7. pgTAP/Edge Function tests when Supabase/server changes are involved;
8. `git diff --check`.

If a test fails:

- determine whether the active work caused or exposed it;
- if implementation-level, fix it autonomously;
- do not weaken/delete a valid regression test merely to obtain green status;
- escalate only if the fix requires a prohibited architectural decision.

### D. Review the diff

Before completion:

- inspect `git diff`;
- inspect `git diff --check`;
- remove accidental changes;
- confirm no secrets or generated junk were added;
- confirm migration/schema versions match the intended scope;
- confirm docs match actual verified behavior.

### E. Update durable state

Update:

- the relevant checkpoint/progress document;
- `docs/CODEX_WORK_QUEUE.md`;
- `docs/ENGINEERING_HANDOFF.md`;
- architecture/schema/security docs only when their facts changed.

### F. Git completion

After the sprint is validated:

1. review intended files;
2. commit intended changes;
3. push to the configured remote/current branch;
4. record branch, commit hash, push result, and final status in the engineering handoff.

If authentication, remote configuration, or branch protection prevents push, do not pretend the sprint is fully Git-complete. Record the exact blocker.

---

## 10. Completion gate

A work item is `COMPLETE` only when all applicable criteria are satisfied:

- implementation finished;
- required focused tests pass;
- required historical regressions pass;
- analyzer passes;
- required full suite passes;
- required builds pass;
- required database/server tests pass;
- `git diff --check` passes;
- documentation is current;
- no unintended diff remains;
- intended changes are committed;
- push succeeds, unless the queue explicitly defines a local-only milestone.

Engineering completion and owner acceptance are separate.

---

## 11. Automatic continuation

After a work item becomes `COMPLETE`:

1. refresh repository state;
2. read the queue again;
3. take the highest-priority `READY` item;
4. continue without requesting a new owner prompt.

If no `READY` item exists:

- inspect the accepted roadmap/progress/checkpoint documents;
- create the next queue item **only if** the next milestone is already explicitly specified with enough acceptance criteria to execute safely;
- do not invent a new feature merely to stay busy.

If the roadmap is exhausted, mark:

```text
ENGINEERING ROADMAP COMPLETE
```

and stop.

If only owner gates remain, mark:

```text
ENGINEERING COMPLETE — OWNER ACCEPTANCE PENDING
```

and stop.

---

## 12. Handling interruption and Codex usage limits

Before a session ends unexpectedly or because of a usage limit, when possible Codex should update `docs/ENGINEERING_HANDOFF.md` with:

- active work item;
- current substep;
- files intentionally modified;
- tests already run and results;
- failing tests/blocker;
- exact next action.

If the limit ends before that update is possible, the next Codex session must reconstruct state from:

- Git status;
- diff;
- queue;
- latest checkpoint;
- test output available in the workspace.

The owner must not need to rewrite the implementation prompt.

This protocol provides **automatic context recovery**. It does not claim that a quota-limited Codex process can wake itself without a product/session trigger.

---

## 13. Safety invariants for Pilgrim Tracker

The following remain mandatory unless an explicit accepted architecture decision changes them:

- normal financial use remains local-first;
- money/accounting behavior must be deterministic;
- historical financial data must not be silently reinterpreted;
- transfers are not ordinary income/expense;
- asset conversions are not ordinary income/expense;
- unrealized gains are not cash income;
- financial imports require review before commit;
- external ingestion must not directly create committed transactions;
- persistence changes are versioned and tested;
- native/web behavior must remain compatible where the architecture requires parity;
- synchronization identity must remain deterministic;
- owner acceptance cannot be fabricated.

---

## 14. Definition of “software finished”

For autonomous engineering purposes, Pilgrim Tracker is engineering-finished when:

- all accepted roadmap engineering milestones are `COMPLETE`;
- no `READY`, `IN_PROGRESS`, `VALIDATING`, or `BLOCKED_ENGINEERING` work remains;
- all applicable automated validation passes;
- release artifacts/builds required by the roadmap succeed;
- documentation reflects the final engineering state;
- all intended work is committed and pushed.

Owner runtime acceptance, credentials, signing, production deployment, and release approval may remain separate owner gates.
