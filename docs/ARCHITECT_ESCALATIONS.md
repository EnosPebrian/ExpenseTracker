# Pilgrim Tracker — Architect Escalations

Use this file only for decisions that cross the architecture escalation boundaries in `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`.

Ordinary implementation questions do not belong here.

## Open escalations

None.

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

### ARCH-20260921-01 — Settlement hosted DELETE ACL hardening

**Resolved:** 2026-09-21
**Decision:** authenticated clients retain SELECT, INSERT and UPDATE but have no
direct DELETE privilege on `public.brokerage_settlements`.
**Affected work item:** PT-BETA-08N-R5

The owner authorized one additive migration after the deployed settlement and
Interest migrations. `20260921144802_beta08n_settlement_delete_acl.sql` revokes
only authenticated DELETE. Local clean replay, focused/full pgTAP, verified
recovery point, exact hosted preflight, normal deployment and hosted
transaction-wrapped checks passed. Versioned UPDATE/deleted-at tombstones remain
the authoritative deletion path; no settlement, Interest or financial semantics
changed.

### ARCH-20260914-01 — Settlement and Interest accounting

**Resolved:** 2026-09-16
**Decision:** Settlement is zero-effect reconciliation evidence; Interest is
distinct positive brokerage cash investment income.
**Affected work items:** PT-BETA-08N1-R3 and PT-BETA-08N1-R4

The settlement portion was implemented in R3. The final Interest decision adds
instrument-free positive Interest as a separate activity and performance
component. It raises brokerage cash and net worth naturally, but changes no
position/basis/trading P&L, ordinary income/expense, budget, Project or Tithe.
Explicit TAX stays separate. Zero/negative Interest is unsupported, preserves
its source sign in review, and blocks without Fee/Dividend coercion.

### ARCH-20260911-01 — Ordered hosted chain includes undeployed BETA-08M0

**Resolved:** 2026-09-11
**Decision:** Deploy BETA-08M0 then BETA-08N0 in exact repository order
**Affected work item:** PT-BETA-08N-RC

The owner/architect explicitly authorized the two-migration chain
`20260908124412` then `20260910054452`, with no history manipulation, skipping,
or later migration. Preflight confirmed that these were the only two pending
versions. After Docker became available, local and hosted gates passed and the
ordered deployment completed on 2026-09-11.

### ARCH-20260910-01 — Select the post-BETA-08M milestone

**Resolved:** 2026-09-10
**Decision:** Option B
**Affected work item:** PT-AUTO-NEXT

BETA-08M is complete and means CSV Unknown-Category Resolution. Human-editable
Portable CSV is a neutral future backlog capability, is not BETA-08M, and needs
its own contract before implementation. The accepted next sequence is:

1. BETA-08N0 — Investment / Brokerage Ledger Foundation.
2. BETA-08N1 — Brokerage Statement CSV Import, dependent on N0.

Feature freeze resumes after BETA-08N1 engineering completion unless another
explicit decision changes the roadmap. The resulting authoritative contract is
`docs/BETA08N_INVESTMENT_BROKERAGE_CONTRACT.md`.
# Resolution 2026-09-15 — ARCH-20260914-01 settlement portion

Owner/Lead Architect selected durable reconciliation evidence with zero
independent financial effect. One-to-one, one-to-many and many-to-one reviewed
links are permitted. Unmatched rows are valid imports. Underlying BUY/SELL
identities and financial authority remain unchanged. Implemented in active
PT-BETA-08N1-R3; verification PASS and implementation pushed as 8ac408b.
Interest is explicitly separate, not a Dividend alias. This supersedes the
earlier settlement choice request; no additional settlement decision is needed.
