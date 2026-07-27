# Controlled Initial Synchronization

BETA-04B initializes a remotely linked household exactly once before the
incremental BETA-04A protocol may run. SQLite remains the operational source
of truth.

## Primary upload

An authenticated active owner confirms that the current device contains the
primary records. Flutter captures `books`, household members, categories,
projects, accounts, asset definitions, and transactions in one SQLite read
transaction. The same transaction records the outbox row boundary and a
manifest of entity counts. Upload uses batches of at most 100 records.

The server atomically claims one upload session, requires an empty financial
mirror, validates book scope and allowed fields, and deduplicates each row by
session, entity type, and UUID. Completion validates counts and references,
applies the snapshot atomically, marks initialization complete, and returns the
server sequence. Local mutations created after the captured boundary remain in
the normal outbox.

## Secondary download

Any authenticated active member may download only after the remote
initialization is complete. The server captures a stable, authorized snapshot
at a server-sequence boundary and pages it deterministically by entity type and
UUID. Flutter writes batches to durable staging; partial rows are never exposed
as a ready household.

Before activation, the client verifies counts, book scope, unique IDs,
versions, financial amounts, ownership, attribution, project, relation, and
asset references. Activation is one SQLite transaction, produces no outbox
operations, maps the authenticated member, advances the cursor, and switches
the active book only after success. An unrelated local book remains untouched.
A populated target with the same remote UUID is rejected; independent local
history is never merged or deleted.

## Recovery and handoff

Initialization states are `notInitialized`, `primaryUploadRequired`,
`secondaryDownloadRequired`, `uploading`, `downloading`, `ready`, and `failed`.
The session, manifest, timestamps, entity/cursor progress, counts, snapshot
boundary, and safe error are durable in SQLite v15. Idempotent batches allow
resume after interruption. Cancellation clears local staging and cancels the
server session without activating or marking the remote upload complete.

Only successful finalization writes `ready`. Primary completion advances to
the returned server cursor and immediately runs normal synchronization for
post-snapshot outbox rows. Secondary activation advances to the stable snapshot
sequence and immediately runs a normal pull to close the download race.

## Deployment and verification

Apply Supabase migrations in order through
`202607260003_beta04b_initial_sync.sql`, then run `supabase db reset` and
`supabase test db` in the linked test environment. Configure only the public
Supabase URL/publishable key in Flutter. Never mark a book `ready` manually and
never use production household data for protocol tests.

