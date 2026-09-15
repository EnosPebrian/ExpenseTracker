# Pilgrim Tracker — Architect Escalations

Use this file only for decisions that cross the architecture escalation boundaries in `docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md`.

Ordinary implementation questions do not belong here.

## Open escalations

### ARCH-20260914-01 — Settlement and Interest posting semantics

**Work item:** PT-BETA-08N1-R2
**State:** BLOCKED_ARCHITECT (posting behavior only)

The owner requires no instrument for Interest, Buy Settlement and Sell
Settlement, and no settlement effect on holdings or realized P&L. Those labels
are not persisted activity types in the current eight-type ledger.

Decision needed: should settlement rows be reference-only with zero cash
effect, or cash debits/credits reconciled against trades? Existing BUY/SELL
already affects brokerage cash, so independently posting settlement would
double-count a matched trade. Interest also needs an explicit investment-income
classification rather than relabeling it Dividend. Additional persisted types
would require compatible client/server validation and historical-reader policy.

Evidence: transaction_brokerage_metadata.dart defines eight types;
brokerage_import_posting.dart materializes trade cash effects;
BETA08N_INVESTMENT_BROKERAGE_CONTRACT.md restricts activity interpretation.

Recommendation: retain reference-only settlements alongside actual trade
records; define Interest distinctly in a separately reviewed ledger change.
Date detection, staged instruments, review UX and their tests are independent
and implemented. Settlement rows cannot be converted to holding-changing trades.

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
PT-BETA-08N1-R3; verification pending. Interest is explicitly separate, not a
Dividend alias. This supersedes the earlier settlement choice request below.
