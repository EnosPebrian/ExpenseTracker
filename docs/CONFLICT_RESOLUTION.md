# Conflict Resolution

Synchronization preserves stale local proposals in `sync_conflicts`; it never
uses last-write-wins for financial records. Conflicts are classified as version,
delete/update, update/delete, ownership, opening-balance, linked-transaction,
asset-trade, or general-entity conflicts.

**Keep shared version** replaces the local canonical row with the current server
snapshot, completes the stale outbox operation, and creates no new mutation.
**Keep this device** and **manual merge** call the authenticated
`resolve_sync_conflict` RPC using the current server version and a new operation
ID. Successful server acceptance creates the next canonical version and exactly
one change event; only then are the local row, cursor, outbox, and conflict state
committed. A stale resolution is left open for refresh and review.

Manual merge is field-based for accounts, transactions, projects, categories,
household members, and asset definitions. Linked-transaction and asset-trade
conflicts intentionally do not allow partial field merge. Delete conflicts are
explicit and tombstones are never silently resurrected.

Realtime listens only for authorized active-book `app_changes` notifications.
Events are debounced into the ordinary cursor pull; event payloads never update
records or cursors. Offline use and manual sync remain available if Realtime is
disconnected.

Monthly-budget conflicts display month, category, amount, currency, note, and
deleted state. Keep shared and Keep this device remain available. Manual merge
may select only amount and note when both sides are active; stable identity,
book, category, month, currency, and lifecycle fields cannot be merged.
Delete-versus-update is explicit and never silently resurrects a tombstone.

## Backup-recovery conflicts

Selective recovery never overwrites through the interactive resolver. A stable
ID with different business/lifecycle content is shown as changed and keeps
current state. A hosted tombstone is shown as deleted from the shared household
and is non-recoverable. Different-ID transaction duplicate warnings are skipped
by default; financial records are never heuristically merged.

## Import-rule conflicts

Rule conflicts use stable rule ID and the ordinary Keep shared / Keep this
device / manual merge flow. Human-readable business fields include name,
enabled state, priority, type, field, operator, pattern, account, category, and
deleted state. Manual merge can choose business fields but cannot change rule
identity, household, creation identity, or lifecycle state. Category choices
are never heuristically merged, and delete-versus-update remains explicit.

## Canonical transfer conflicts

Transfer links are not eligible for heuristic or field-by-field merge. A leg
or relation conflict is identified by stable entity ID and explicitly flagged
as linked-transfer state. Keep-shared/keep-local decisions remain in the
existing conflict workflow, followed by aggregate integrity validation. A
relation delete versus leg update cannot silently leave an active half-pair;
validation failure leaves the prior local state and conflict unresolved.

## Import-review conflicts

Inbox conflicts use stable session/draft IDs. Manual resolution may choose
date, description, amount, type, category, reference, note, and inclusion, but
cannot change household, session, source-row, source fingerprint, deterministic
final transaction identity, or terminal lifecycle. Amount/category differences
are never silently merged. A cloud-linked session with an unresolved conflict
cannot commit, and a stale session version must refresh before review/commit.
