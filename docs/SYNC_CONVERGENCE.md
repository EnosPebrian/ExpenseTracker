# Sync convergence and conflict lifecycle — BETA-09A

SQLite remains immediate local authority; hosted Supabase remains the shared
authority. Google Sheets is not required as primary storage for multi-device
durability. A Sheets bridge is not part of this change.

## Ordered delivery

Financial mutations and immutable outbox payloads remain one local transaction.
The coordinator drains acknowledged dependency stages without sleeps: master
identities precede dependent transactions; transactions precede transfer links
and settlement evidence. A blocked dependency blocks its children, not unrelated
household work. Earlier mutations of one entity precede later mutations.

Pull consumes a complete ordered change-feed prefix and applies reference
entities first in one local transaction. Only that consumed prefix advances the
global cursor. A resolution response's entity sequence must never advance the
cursor past unrelated unseen records. Pending local branches and newer canonical
versions are not overwritten by a remote snapshot. Pending branches subsequently
undergo the normal server version check/conflict path; they are not silently lost.

## Durable resolution

Opening review or selecting an option does not resolve a conflict. A manual
dialog requires an explicit Local/Cloud choice for every differing editable
field. Coordinated transfers, asset/brokerage records and System Tithe cannot
be field-merged into an invalid hybrid. Amount/account remain a coupled choice.

Before RPC, the existing conflict resolution field stores the selected intent
and stable operation UUID. Interrupted or ambiguous-response retries reuse both,
including after restart. Definitive stale/validation rejection retains the
conflict; stale responses refresh the server snapshot for renewed review.
Server-confirmed canonical identity/version is verified before local application.
Canonical application, outbox acknowledgement and conflict completion are atomic.
A newer local mutation is retained as a separate pending branch, not discarded
by completion of an earlier conflict. Completed outbox history is retained but
is no longer eligible for transmission.

The additive server migration serializes existing version-check/write/idempotency
critical sections using the same household transaction advisory lock as initial
sync. Existing authentication, validators, RLS and ACLs remain authoritative.
No schema, financial identity or backup-format change is required.

## Truthful diagnostics

Pending, failed and conflict counts, last successful push/pull in this application
session, and consumed remote cursor are visible. Initialization timestamps are
not sync-success timestamps. Empty outbox alone is insufficient for Synced: this
session must have successfully reconciled the change feed and have no remaining
pending work or conflict. This describes this device, never an unobserved peer.

## Owner checks — NOT RUN

On Windows import a reviewed brokerage statement, then sync; on Android sync and
verify all imported records and references arrive. With both devices editing one
ordinary transaction, inspect the real merge dialog and deliberately choose each
field. Disconnect during resolution: conflict and retry must remain visible.
Reconnect/retry, then sync the other device and verify the chosen result exactly
once. Restart with a pending conflict and repeat. Physical-device acceptance is
PENDING; repository simulations do not substitute for it.
