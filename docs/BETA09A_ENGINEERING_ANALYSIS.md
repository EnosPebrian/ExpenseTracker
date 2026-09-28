# BETA-09A — pre-repair sync investigation

2026-09-27. Baseline main `35ee692429499a25bf2cd6e0213e24ddbdbdf0c3`.
This analysis precedes production repair. Owner symptoms are not a captured
device trace; the following are independently reproducible code defects.

## Actual pipeline

LocalStore mutations/atomic imports persist financial rows and immutable
sync_outbox snapshots together. LocalSyncRepository selects eligible operations;
SyncCoordinator marks sending and SupabaseSyncTransport calls push_book_changes.
The authenticated RPC checks membership, payload fields and base version, applies
the canonical row and records processed_sync_operations. app_changes records
server sequence; applied acknowledgements complete outbox records (retained as
completed history). pull_book_changes returns ordered sequences with current
canonical snapshots. LocalStore applies a batch and its cursor transactionally.
SyncController calls AppShell._refreshSyncedData after remote application.
Realtime only schedules that same durable pull path; it does not apply rows.

Version conflict responses persist sync_conflicts and retain the outbox snapshot.
ConflictReviewScreen already renders field choices inline; its Merge button opens
a confirmation dialog, not a separate field editor. Confirmation reaches
SyncConflictController -> ConflictResolutionService -> resolve_sync_conflict.
The service checks resolved/alreadyResolved and canonical snapshot, then the store
applies the row and marks the conflict/outbox completed in one transaction.
AppShell's post-resolution callback only invokes syncNow.

## Confirmed defects and risks

1. completeSyncConflictResolution advances the global cursor to the individual
   resolution sequence without consuming intervening changes (native and web).
   Unrelated records can therefore be permanently skipped on that device.
2. SyncCoordinator refuses all push/pull whenever inspect reports conflict.
   A single review item prevents unrelated imports/remote records converging.
3. Only one 50-operation push batch runs per cycle; eligibility is creation order,
   with no explicit dependency ordering. Large imports need multiple wakeups.
4. Remote apply replaces rows regardless of outstanding local mutations. A pull
   can overwrite local unsent data, including conflict state. It also does not
   reject older snapshots after a newer authoritative resolution.
5. Retry generates a new resolution UUID; interrupted resolving states cannot
   restart. A network loss after server acceptance cannot safely resume the same
   intent. Stale server response is discarded instead of updating review context.
6. Transaction category_id is absent from the transport allowlist although the
   accepted server contract supports it. Identity can be lost on sync.
7. UI displays arbitrary changed/internal fields, defaults all choices to shared,
   and permits hybrids based only on conflict classification. Linked semantics
   need payload-based protection. Failed choices are cleared by the screen.
8. Sync inspect reports synced from zero queue count alone. Cursor timestamp is
   displayed as successful sync even though initialization also writes it.
9. Server resolve/push checks version before write without a serialization lock.
   Simultaneous writers may both pass the same base-version check. A bounded
   additive function migration is justified to serialize per-household RPCs;
   historical migrations must remain unchanged. Deployment has separate gates.

## Repair boundaries

Only a consumed ordered pull batch advances the cursor. Continue independent
work during conflict, protecting unsent rows and retaining canonical conflict
snapshots. Drain eligible dependency-ordered batches with no busy retry loop.
Persist/reuse resolution intent in existing conflict fields; server response and
local apply must both succeed before clearing. Refresh UI after canonical apply.
Expose honest pending/failed/conflict counts and session push/pull evidence.
Keep coordinated financial records whole; ordinary fields have explicit choices.
SQLite 29 / backup v8 unchanged unless testing proves a new field necessary.
No accounting changes. Google Sheets is not required as primary storage for
multi-device durability.

## Verification plan

Native/web cursor and dirty-row guards; durable interrupted/ambiguous retries;
two-device imported rows plus manual conflict, offline catchup and no echo;
dependency ordering; failed/rejected/stale resolutions; UI explicit choice and
errors; existing sync, import, transfer, asset, metadata, Health Check regressions.
Full Flutter/analyzer/platform gates and SQL replay/pgTAP if migration added.
Owner physical Windows/Android acceptance remains pending.
