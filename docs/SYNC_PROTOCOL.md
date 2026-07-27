# Pilgrim Tracker Incremental Sync Protocol

## Source of truth

SQLite remains the operational source of truth. A local financial action
commits its canonical record and durable outbox operation in one SQLite
transaction, refreshes local UI immediately, and never waits for Supabase.
Remote application writes directly to the local canonical tables in one
transaction without producing another outbox operation.

## Initialization guard

Each linked book has one of seven durable local states:

```text
notInitialized
primaryUploadRequired
secondaryDownloadRequired
uploading
downloading
ready
failed
```

Only `ready` permits incremental push/pull. The v13-to-v14 migration marks
already-linked books `primaryUploadRequired`, uses cursor zero, and creates no
historical outbox operations. SQLite v15 adds durable initialization progress
and staging. BETA-04B now owns the guarded transition to `ready`; see
`INITIAL_SYNC_PROTOCOL.md`.

## Outbox and operation identity

Every local mutation receives a stable UUID `operation_id`. Retrying reuses
that row and operation ID. An operation contains book/entity identity, upsert
or delete intent, canonical base version, payload snapshot, timestamps,
attempt metadata, safe error metadata, and status. Linked multi-record actions,
including managed asset-fee changes, enqueue every related record atomically.

Statuses are `pending`, `sending`, `retry`, `conflict`, and `completed`.
Interrupted `sending` rows return to `retry` on the next run. Network failures
use bounded exponential delay (5 seconds through 15 minutes). Authentication
waits for sign-in; authorization and validation failures become terminal
attention states rather than spinning.

## Push ordering and canonical versions

`push_book_changes(book, operations)` accepts up to 50 operations after
deriving `auth.uid()` and verifying active membership. It validates supported
entities and fields, operation/payload IDs, book scope, and base version.
Accepted changes increment the canonical version, retain deletions as
tombstones, emit exactly one server `app_changes` row through database
triggers, and record the result in `processed_sync_operations`.

A repeated operation ID returns its stored result and never duplicates the
canonical record or change event. Reusing an operation ID with different
book/entity identity is rejected. Stale base versions return the server
snapshot and are stored locally in `sync_conflicts`; no last-write-wins policy
is used.

## Pull ordering and cursor commit

`pull_book_changes(book, afterSequence, limit)` verifies membership, enforces a
1-to-200 batch size, and returns only that book's changes ordered by the
server-generated `app_changes.sequence`. Each item contains entity identity,
canonical version, upsert/delete intent, sequence, and current snapshot or
tombstone.

The client applies an entire batch and advances `sync_cursors` in one SQLite
transaction. A failed apply rolls back records and cursor together. Repeating
a batch safely replaces the same stable entity IDs. Client timestamps are
never authoritative cursors.

## Triggers and user status

When initialization is ready, synchronization may run after restored startup,
application resume, manual **Sync now**, or a short debounce after local
mutation. Runs are single-flight; there is no continuous polling or platform
background service. The UI distinguishes local-only, unconfigured, signed-out,
initialization-required, pending, syncing, offline/retry, conflict, and error
states without claiming that BETA-04A uploaded existing financial history.

## Deferred

- BETA-04C: conflict review/resolution and any approved Realtime wake-up layer.
- BETA-05: Enos/Grace two-device acceptance and recovery proof.
