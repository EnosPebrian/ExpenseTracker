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
