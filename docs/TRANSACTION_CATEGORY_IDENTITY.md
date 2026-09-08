# Transaction Category Identity — BETA-08L0

## Contract

`Transaction.categoryId` (`category_id` in storage) is the authoritative category
identity when known. `Transaction.category` remains a human-readable historical
snapshot / unresolved fallback. Null identity is valid, not corruption.
Identity-sensitive features must use the ID, never a label such as “Tithe”.

Manual category selection and shared import finalization persist ID and snapshot
together. A category edit selects a new pair. A master-data rename does not rewrite
historical transactions. Archived categories remain valid historical references.
Copying a transaction with changed category/type but without an explicit identity
clears the old ID. Available name-based UI choices resolve only an unambiguous
entity; duplicate labels never authorize arbitrary identity selection.

## Persistence and migration

SQLite 26 adds nullable `transactions.category_id` and its lookup index. The
25-to-26 migration preserves transaction IDs, amounts, snapshots, lifecycle fields
and outbox rows. Backfill requires exactly one same-book, same-financial-type
category matching `lower(trim(name))`; archived rows participate. Zero matches
or normalized collisions remain null. No categories are created. SQLite's built-in
case folding is conservative for non-ASCII names; unsupported case equivalences
can remain unresolved rather than guessing an identity.

Native and web mutation, restore, recovery, remote-apply and conflict paths validate
non-null references against the same book and category type. Null remains valid.
Health Check diagnoses missing/foreign identities without repairing records.

## Ingestion

The existing shared import controller resolves a valid persisted review category,
the winning rule's category, or a unique available selected category. Manual
precedence is unchanged. Unresolved text keeps null identity; no new master data
or deterministic transaction UUID algorithm is introduced. CSV, receipts,
statements and inbox sources use this same final transaction creation boundary.

## Synchronization and conflicts

The existing push/pull, snapshots and initial-sync pathways carry nullable
`category_id`. Download does not generate identities or enqueue echoed mutations.
A legacy payload missing the field preserves an existing ID only while the
snapshot and financial type remain unchanged; changed category/type clears it.
Explicit null remains null. Manual conflict review selects snapshot and identity
as one pair, never a name from one device with the other device's ID.

`20260904141514_beta08l0_transaction_category_identity.sql` is the only new
migration. It adds the nullable reference/index, same-book/type validation,
conservative backfill and extensions to existing sync/initial-sync RPCs. Helpers
use fixed search paths and restricted execution. RLS is retained. Migration is
validated locally only: hosted deployment is NOT authorized or performed.
Deploy this migration before using category-ID-aware clients against hosted sync.

## Backup and recovery

Encrypted backup v5 includes category snapshot and nullable identity; encryption
and password derivation are unchanged. v1–v4 remain readable with null transaction
category IDs, without guessing identities from labels. Clone remaps known IDs
through the source-to-cloned-category map. Selective recovery uses an existing
same-ID category or an explicitly selected recoverable category dependency. If
there is no safe identity relationship, it retains the snapshot and clears ID;
matching names alone do not create a relationship. Foreign households still
require clone rather than selective recovery.

## Boundaries

No hosted deployment or owner-runtime acceptance is claimed. Monetary reporting,
tithe calculations, CSV format and investment behavior are unchanged. BETA-08L,
BETA-08M and BETA-08N/N1 remain separate future milestones. Owner approved that
future Portable CSV must be machine-safe AND human-readable/human-editable, with
export → spreadsheet edits → import review → commit; that feature is not built here.
