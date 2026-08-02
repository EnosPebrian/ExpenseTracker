# Multi-Device Sync Architecture

BETA-04C adds durable explicit conflict resolution and optional filtered
Realtime wake-up. Cursor synchronization remains authoritative; linked
financial conflicts cannot be partially merged.

## Current local model

SQLite is the source of truth. `FinancialBook` is the household boundary;
`HouseholdMember` is a local person, not an authenticated user. Records retain
stable IDs, book IDs, timestamps, tombstones, versions, device IDs, and sync
status. BETA-04A keeps these local records authoritative while adding delayed
incremental synchronization.

## BETA-03 authorization backend

Use Supabase PostgreSQL, Supabase Auth, Row Level Security, and the Flutter
client. Keep three concepts distinct:

```text
local household member/person
authenticated application user
membership connecting a user to a financial book
```

Authorization must follow:

```text
authenticated user
→ household membership
→ permitted book IDs
→ RLS restricts every financial row to those books
```

This authorization layer is implemented in BETA-03. Email OTP establishes the
Auth user; authenticated RPCs link a local book UUID, create/discover/accept
invitations, and create memberships. RLS protects every application-owned
table by active membership. SQLite version 13 stores only the remote-link
instant and optional Auth-user mapping. No financial records are transferred.

## BETA-04A incremental synchronization protocol

The implemented sync engine preserves local-first writes and uses:

- a durable SQLite outbox;
- a server-assigned monotonic change sequence/cursor;
- push then cursor-based pull, with each remote batch and cursor committed in
  one local transaction;
- idempotent server processing keyed by stable operation IDs and entity IDs;
- tombstone propagation and retention;
- canonical version conflicts persisted locally without last-write-wins;
- retry, interruption, duplicate-delivery, partial-failure, and recovery tests.

Realtime subscriptions may prompt a pull but must never become the source of
truth. Sensitive access is enforced by server-side membership and RLS, not by
client filtering.

Incremental synchronization is blocked by every state except `ready`. BETA-04B
implements owner-confirmed, remote-empty primary upload and authorized stable
secondary download. SQLite v15 persists snapshot staging, session/progress,
manifest, safe errors, and cursor handoff. Download activation is atomic and
never merges or deletes an independently populated local household.
See `SYNC_PROTOCOL.md` for the operation, retry, cursor, and interruption
contract.

## Acceptance boundary

BETA-05 proves two-device behavior with Enos and Grace, including offline
edits, reconnect, conflicts, deletion propagation, and recovery. Until then,
the application must not claim financial synchronization is available.
