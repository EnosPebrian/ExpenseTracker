# BETA-08M Completion Checkpoint

**Engineering status:** PASS
**Owner acceptance:** NOT RUN

BETA-08M adds explicit unknown-category resolution to the existing CSV review
pipeline. Exact normalized matches map safely; unknown values require Map,
Create, or Ignore. Create is durable review intent only and becomes a Category
row solely inside the final category + transaction + transfer + outbox atomic
commit. Cancellation and Save for later do not create categories.

The existing Import Inbox stores all four resolution states and the planned
creation identity without source bytes. Manual row overrides win over grouped
source resolution. Canonical System Tithe identity, deterministic transaction
UUIDs, duplicate protection, and transfer authority are preserved. Linked
offline commits and new-device bootstrap use the existing synchronization
protocol. Committed results use existing encrypted backup v6.

The `_prepareCategoryCommit` compatibility regression is repaired: only an
explicit user-confirmed Map choice requires `ImportRuleCategory` stable-ID
revalidation. Valid legacy, source-neutral, and manual assignments retain their
existing validation path. Source-neutral Tithe still resolves to the canonical
System Tithe identity.

Versions remain SQLite 27 and backup v6. No SQL, Supabase migration, hosted
change, or deployment was needed. Focused coverage passed 294/294, the full
Flutter suite passed 954/954, analyzer passed, and Web, Windows debug, and
Android debug APK builds passed. Owner runtime acceptance remains **NOT RUN**.
