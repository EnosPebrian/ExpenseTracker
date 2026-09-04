# Selective backup recovery

`Recover from backup` is additive. It is separate from disaster recovery:
`Restore backup` replaces household state and intentionally returns it to
local-only mode, while recovery preserves every current record, cloud identity,
cursor, readiness state, and member mapping.

## Scope and input

- Only an encrypted `.ptbackup` whose canonical `bookId` equals the active book
  is accepted. Foreign households are blocked with restore-as-new guidance.
- Backup formats v1 and v2 use the existing decryption, password, checksum,
  integrity, and version validation. Failure or cancellation creates no writes.
- Local-only books compare backup with SQLite. Linked ready books must also pass
  an authenticated, RLS-protected, read-only hosted snapshot check. If hosted
  inspection is unavailable, preview may load but commit is blocked.

## Classification and identity

Records are classified as identical, missing, changed/conflict, remote-deleted,
semantic duplicate, possible duplicate, invalid reference, foreign household,
recoverable dependency, or unsupported. Stable IDs and book boundaries are
authoritative. Same-ID equivalent rows produce no write; changed rows keep
current state; hosted tombstones are never resurrected automatically.

The source-neutral `TransactionDuplicateDetector` compares normalized copies
using account, type/direction, exact amount, date, and conservatively normalized
description/reference signals. Different amount or account is new; a nearby
date can only be possible. Stored user text is never rewritten.

## Dependencies and supported entities

Recovery supports accounts, categories, projects, asset definitions, monthly
budgets, and transactions. A safe missing dependency is selected and committed
first. Archived references may satisfy history without reactivation. Missing
member authority blocks dependents; backup auth IDs, roles, and membership
authority are never imported.

Household rows, members, and manual market prices are preview-only in BETA-08A
because they lack a safe additive mutation pathway. Backup v1 has no budgets
and never changes current budgets.

## Commit and sync safety

The confirmed plan commits dependencies, records, and normal outbox operations
atomically. Stable business IDs are preserved, but stale device, sync, cursor,
auth, and initialization metadata is discarded. Linked books use the existing
durable outbox and ordinary sync; local-only books create no cloud work.
Recovery never reconnects, deletes current-only rows, or treats omission as
deletion. Repeating a backup is naturally idempotent.

## Current limitations and future ingestion

BETA-08A does not overwrite conflicts, resurrect remote tombstones, merge
foreign households, restore member authority, or recover manual price history.
The candidate/duplicate/review foundation is source-neutral for BETA-08B CSV,
then reviewed receipt and statement sources. No CSV parsing, OCR, PDF extraction,
Telegram, or automatic categorization is implemented here.

## Owner closure and Restore lifecycle

BETA-08A owner testing is PASS: recovery of 8 budgets and 7 transactions was
followed by a zero-missing re-analysis with no duplicate recovery. BETA-08A1
does not change these semantics. Full Restore destinations are documented in
`RESTORE_LIFECYCLE.md`.

## V3 import-rule recovery

Backup v3 rules are classified by stable identity as identical, missing,
changed/conflict, remotely deleted, invalid reference, or foreign household.
Only a safe missing rule is eligible for additive recovery, using current
mutation/outbox semantics and fresh local sync metadata. Existing rules are not
overwritten, remote tombstones are not resurrected, and category/account
references must resolve within the household. V1/v2 contain no rule section and
leave current rules untouched.

## V4 canonical transfer recovery

Recovery treats a link and its two legs as a dependency-bound aggregate. Safe
missing legs are planned before a safe missing link; identical dependencies
are reused. Changed legs, foreign-household references, missing accounts, or
remote tombstones block the relation. Recovery never invents a leg, merges
financial content heuristically, or resurrects a remotely deleted aggregate.
