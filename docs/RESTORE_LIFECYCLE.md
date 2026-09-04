# Restore Lifecycle

## Recover and Restore are different operations

`Recover missing records` is additive. It compares a same-household backup with
the current shared household, preserves current data and cloud identity, and
commits only selected missing records as ordinary synchronized mutations.

`Restore entire backup` is replacement disaster recovery. It activates the
backup snapshot locally, clears historical cloud authority, and starts the
restored household as `local_only`. It never merges independent histories.

## Destinations after Restore

A completed Restore exposes a persistent status panel immediately and in
Household > Cloud Sharing:

- **Keep local only** leaves the restored household fully usable offline. No
  warning loop requires cloud setup.
- **Reconnect existing shared household** reuses the BETA-07C2 protected
  authoritative download. A required encrypted safety backup is created first.
  Local-only restore records are not uploaded; use Recover missing records when
  they need to be added to the hosted household.
- **Create new shared household** clones the restored snapshot to a fresh local
  household identity, links the authenticated active owner, and runs the normal
  controlled initial-upload protocol.

## New shared-household identity

Pilgrim Tracker uses the non-destructive clone strategy. The original restored
household remains local-only. The cloud recovery clone receives:

- a fresh household/book ID;
- fresh globally unique IDs for members, accounts, categories, projects,
  transactions, asset definitions, and budgets;
- remapped member, project, related-transaction, asset-definition, budget
  category, account-owner, and definition-backed manual-price references;
- no historical `auth_user_id`, remote link, device authority, cursor, conflict,
  staging, or outbox state.

Historical name snapshots in ledger rows remain historical snapshots. The clone
is validated structurally and financially before atomic activation. The source
snapshot is never mutated or deleted.

## Hosted-household protection

Create new shared household never uses the historical restored book ID. The new
ID is linked through the existing `link_local_household` owner flow, then the
existing initial-upload manifest and empty-hosted-state checks run. An initialized
hosted household is therefore never treated as the destination of this action.

Existing hosted state is reached only through Reconnect. Selective additions to
that hosted history use Recover missing records.

## Failure behavior

Authentication, clone validation, activation, membership, manifest, upload, or
network failure cannot modify the original restored household. A locally
activated clone may remain available for safe diagnosis/retry, and a linked but
incomplete clone follows the existing resumable initial-upload convention. The
UI never reports successful synchronization until initial upload completes.

## Owner acceptance sequence

1. Restore a valid v2 backup with Restore entire backup and confirm it starts
   local-only with the three destination actions.
2. Choose Keep local only, close/reopen, and confirm local use and backup/export
   remain available without a setup loop.
3. Restore again, sign in as the intended owner, choose Create new shared
   household, review name/currency/counts, rename if desired, and confirm.
4. Confirm the new household reaches Synced, Pending 0, and shows a current last
   successful time; close/reopen and confirm it remains Synced.
5. Create a normal transaction, synchronize it, and confirm a second authorized
   device receives it.
6. Confirm the historical hosted household was not changed.
7. Restore again and choose Reconnect existing; confirm the safety backup is
   created and authoritative hosted data replaces the restored local snapshot.
8. Use Recover missing records for any backup-only rows that should be added to
   the existing shared household.
9. Repeat the supported v1 restore/new-share case and confirm current budget
   compatibility behavior is preserved.
