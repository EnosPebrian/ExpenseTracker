# Pilgrim Tracker — Architect Escalations

Use this file only for decisions that cross the architecture escalation boundaries in `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`.

Ordinary implementation questions do not belong here.

## Open escalations

### ARCH-20260910-01 — Select the post-BETA-08M milestone

**Work item:** PT-AUTO-NEXT
**State:** BLOCKED_ARCHITECT

**Decision required**

Which repository contract is authoritative for the next autonomous milestone:
the still-described Portable CSV scope, BETA-08N investment/brokerage work, or
another accepted milestone with complete acceptance criteria?

**Why Codex cannot decide autonomously**

This is product-scope selection. Current documents conflict, and BETA-08N has no
executable domain contract or acceptance criteria. Choosing or inventing one
would cross the protocol's architecture boundary.

**Existing repository evidence**

- `docs/ROADMAP_D10_TO_D14.md` opens with BETA-08M unknown-category resolution
  as implemented, but later says BETA-08M must deliver Portable CSV.
- `docs/CSV_IMPORT.md` describes unknown-category resolution as BETA-08M while
  also retaining older text that calls Portable CSV future BETA-08M work.
- `docs/progress.md` records unknown-category resolution as implemented while
  its BETA-08M0 entry still points to Portable CSV as future BETA-08M.
- BETA-08N is named as investment/brokerage work, but no dedicated accepted
  specification defines its accounting, identity, persistence, or acceptance
  behavior.

**Option A**

- Define Portable CSV as the next separately named milestone.
- Reconcile BETA-08M naming and provide its authoritative file contract and
  acceptance criteria.

**Option B**

- Declare BETA-08M engineering scope complete and define BETA-08N next.
- Supply the investment/brokerage domain contract and acceptance criteria before
  implementation begins.

**Codex recommendation**

Resolve the naming conflict first, then add exactly one fully specified `READY`
queue item. Do not infer investment accounting or portable interchange policy
from historical roadmap mentions.

**Work that can continue independently**

none

## Escalation template

```markdown
### ARCH-YYYYMMDD-NN — Short title

**Work item:**
**State:** BLOCKED_ARCHITECT

**Decision required**
One precise question.

**Why Codex cannot decide autonomously**
Identify the architecture/domain/security boundary.

**Existing repository evidence**
- document / section
- document / section

**Option A**
- behavior
- benefits
- risks

**Option B**
- behavior
- benefits
- risks

**Codex recommendation**
A recommendation is allowed, but Codex must not implement across the boundary before an accepted decision exists.

**Work that can continue independently**
List any safe independent work, or `none`.
```

## Resolved escalations

Move resolved items here with:

- decision;
- date;
- resulting ADR/document update;
- affected work item.
