# Import Review Inbox

BETA-08G adds a durable household-scoped queue for uncommitted transaction
imports. CSV, receipt, invoice, and bank-statement sources all resume in the
existing shared review editor; Telegram is not implemented.

## Privacy and persisted data

Pilgrim persists only safe source metadata, a source fingerprint, normalized
draft values, review inclusion, warnings, and explicit edit provenance. It does
not persist CSV/PDF/image bytes, public URLs, extraction prompts, provider
responses, or authentication material. A secondary device can review the
normalized result without the original source file.

## Identity and lifecycle

Sessions and drafts have stable UUIDs. Each draft separately retains its source
row identity and, once an account is known, deterministic final transaction ID.
Draft identity is not final financial identity. Destination account is part of
final transaction identity, so an unresolved draft stores a null final ID and
null identity-account binding without becoming an invalid workflow record. The durable state machine
is `pendingReview → readyToCommit → completed` or `pendingReview → discarded`;
terminal states cannot reopen. Completed sessions and normalized drafts are
retained for cross-device reconciliation and idempotent audit history. Pending
views exclude completed sessions.

Discard tombstones the session and child drafts using the ordinary synchronized
entity path. It never creates or modifies a financial transaction. Completed
history deletion is deferred.

## Reanalysis and precedence

On resume, Pilgrim reloads current household data and recalculates validation,
rule suggestions, duplicate status, and possible transfers. Stored analysis is
never authoritative. Explicit manual values survive restart and sync. Category
precedence remains manual > valid source category > current deterministic rule
suggestion > unresolved. A deleted account/category blocks commit and requires
review rather than silent remapping.

## Commit and synchronization safety

Inbox records use the existing outbox, push/pull, change feed, cursor, conflict,
initial upload/download, and RLS architecture. Local-only inboxes create no
cloud outbox. Linked offline edits use current device data and synchronize later.
Unresolved sync conflicts block import commit.

Commit rechecks the local durable session version. Stable final transaction IDs
prevent duplicate creation if two devices attempt the same import. If a crash
occurs after financial rows commit but before the completion marker, reopening
compares the stable IDs and meaningful financial values: exact rows reconcile
the session to completed, while different values become a blocking conflict.

## Storage and backup

SQLite v24 added `import_review_sessions` and `import_review_drafts`. SQLite v25
makes final transaction identity nullable, persists the canonical source-row
key, and adds `deterministic_transaction_account_id`. Supabase
migration `202608210001_beta08g_import_review_inbox.sql` adds equivalent RLS
entities and existing sync-protocol coverage; it remains undeployed.

Encrypted backup stays at v4 and deliberately excludes Import Inbox data.
Restore and Recover missing records remain committed-financial-data operations.
For a local-only household, inbox data is device-persistent but not portable
disaster-recovery data.

## Future Telegram contract

A future authenticated server ingestion may create a normalized session and
drafts, synchronize them to Pilgrim, and request explicit review. It must not
create financial transactions directly. No bot, token, webhook, chat identity,
or Telegram command exists in BETA-08G.

BETA-08H stopped at the account-dependent identity safety gate. BETA-08G1
removes only that blocker; it does not implement Telegram. See
`DEFERRED_IMPORT_IDENTITY.md`.

## BETA-08H remote delivery

BETA-08H now creates the existing session/draft records atomically through a
server-only RPC after private Telegram authentication and membership checks.
Rows retain stable workflow/source identity and remain account/final-ID
unresolved. Devices reopen them through the shared editor; selection of an
account triggers existing G1 reanalysis. Telegram never bypasses user review.
