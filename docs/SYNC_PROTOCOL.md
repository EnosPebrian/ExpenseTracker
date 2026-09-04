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
Monthly category-budget create, update, restore, and soft-delete operations use
the same atomic canonical-row/outbox transaction and stable operation IDs.

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
application resume, manual **Sync now**, Realtime wake-up, successful
link/bootstrap, or a short debounce after local mutation. Runs are
single-flight; requests received during an active run coalesce into one
follow-up instead of being discarded. There is no continuous polling or
platform background service. The UI distinguishes local-only, unconfigured, signed-out,
initialization-required, pending, syncing, offline/retry, conflict, and error
states without claiming that BETA-04A uploaded existing financial history.

For a linked household, Pending 0 means the synchronized cloud copy can
bootstrap another authorized device. A positive pending count is explicitly
device-local until a successful push. Pilgrim retries when the app next starts
or becomes active; it does not promise execution while the process is suspended
or killed.

After replacement restore, incremental sync stays disabled because remote
identity and the authoritative cursor are intentionally cleared. BETA-07C1
exposes an explicit download-first reconnect. Successful activation restores
the hosted identity, mapped member, snapshot cursor, ready state, empty outbox,
and completion timestamp before normal pull/push or Realtime wake-up resumes.

## Conflict resolution and wake-up

BETA-04C classifies and durably retains conflicts until explicit successful
resolution. Keep shared applies no new local outbox mutation; device/manual
choices use a new idempotent operation against the latest server version.
Realtime is only a debounced wake-up for this cursor protocol and never applies
its payload or advances a cursor.

`monthly_category_budgets` is a normal synchronized entity. Initial manifests,
primary upload, secondary download, incremental push/pull, tombstones, and
`app_changes` include it. RLS uses active book membership; category/book scope,
base currency, positive limits, and active category-month uniqueness are
validated remotely. Realtime remains wake-up only.

## Selective recovery

Recovery preflight uses authenticated RLS-protected reads and creates no remote
session or financial write. A linked book must be ready and remotely verified.
Commit preserves linkage, initialization state, member mapping, and cursor.
Recovered rows are current local mutations with ordinary durable outbox entries;
they are never marked remotely applied and no recovery channel or RPC exists.

## Deferred

- BETA-05: Enos/Grace two-device acceptance and recovery proof.

## Restored-household cloud bootstrap

Full Restore creates no outbox and starts local-only. Create new shared
household first makes an atomically validated fresh-identity clone, then reuses
controlled initial upload. Incremental synchronization begins only after that
upload reaches ready. Reconnect remains an authoritative protected download;
it never uploads the restored local snapshot.
# CSV import synchronization

CSV import adds no transport or server endpoint. A confirmed batch uses normal
transaction upserts and existing outbox operations in the same local database
transaction. It does not alter links, initialization state, cursors, member
mapping, or conflict policy. Offline linked imports warn that duplicate analysis
uses current local data, then queue ordinary local-first mutations.
# Imported-document transactions

Receipt and bank-statement extraction is independent of household linking.
Confirmed drafts are ordinary local transactions. A linked household produces
only the existing ordinary outbox mutations; local-only households create no
cloud state. Extraction never reconnects, initializes sync, resets a cursor, or
introduces a document-specific protocol.

## Deterministic import-rule synchronization

`transaction_import_rules` is a normal synchronized household entity. Local
create/edit/enable/disable/tombstone writes share one SQLite transaction with
the durable outbox operation; remote applies do not echo. Initial upload,
secondary download, cursor pull, manifest counts, idempotent retry,
`app_changes`, and Realtime wake-up use the existing protocol. Server RLS and
reference validation reject unrelated households and cross-household category
or account references. Rules never enqueue transactions by themselves.

## Canonical transfer synchronization

`transfer_links` is an ordinary synchronized entity ordered after its accounts
and transaction legs for initial snapshots. Creation/edit/delete use the same
durable outbox as every financial entity; remote applies never echo. Native and
web apply validate the complete active aggregate transactionally, so an invalid
or orphan relation rolls back. Supabase push/pull, manifest, snapshot, change
feed, RLS, and retry paths include the relation without a transfer-specific RPC.

BETA-08F1 candidates and session rejections are transient and never sync.
Confirmation produces only existing transaction and `transfer_links` outbox
mutations. Offline matching uses current device data and later follows the
ordinary synchronization pipeline.

## Import-review entities

`import_review_sessions` and `import_review_drafts` use the ordinary outbox,
push/pull, `app_changes`, cursor, conflict, and initial-snapshot paths. Sessions
precede drafts in upload/download order. Remote apply never echoes an outbox
mutation, and household/member/account/category/session boundaries are
validated locally and by RLS. Local-only sessions enqueue nothing. Terminal
completion/discard state is versioned and cannot silently reopen; unresolved
draft conflicts block financial commit. Realtime remains wake-up only.

## Deferred import identities

Import-review drafts synchronize with nullable
`deterministic_transaction_id`, nullable
`deterministic_transaction_account_id`, and nullable legacy-compatible
`source_row_key`. Downloading an unresolved draft never derives an ID or invents
an account. Final ID and account binding are linked conflict state; unresolved
session/draft conflicts block financial commit, and account resolution is
followed by deterministic recomputation and full duplicate/transfer analysis.
Remote apply remains no-echo and uses the existing outbox/change-feed protocol.

Server-originated Telegram Inbox sessions use the same change feed and initial
sync entity types as BETA-08G/G1. They arrive with null destination account,
null final transaction ID, and null identity binding. Merely downloading them
does not finalize identity or create finance. Telegram operational tables and
events are deliberately outside financial sync.
