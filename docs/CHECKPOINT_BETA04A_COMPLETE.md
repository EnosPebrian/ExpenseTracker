# BETA-04A Completion Checkpoint

Completed on 2026-07-26.

## Delivered

- SQLite version 14 adds durable `sync_outbox`, `sync_cursors`, and
  `sync_conflicts` storage without enqueuing or uploading historical rows.
- New linked-book mutations for books, household members, accounts,
  categories, projects, transactions, and asset definitions atomically commit
  the local record and outbox operation.
- Supabase push/pull RPCs enforce active membership, book scope, field and
  identity validation, canonical versions, tombstones, operation idempotency,
  and monotonic `app_changes` cursors.
- The Flutter coordinator supports bounded batches, single-flight execution,
  durable conflicts, interrupted-send recovery, bounded network retry, and
  safe local operation while cloud services are unavailable.
- Incremental synchronization is explicitly blocked until BETA-04B completes
  either primary upload or secondary download initialization.
- Household Settings shows calm sync status, pending count, initialization
  warnings, and a guarded **Sync now** action.

## Verification

- Focused Flutter tests: 29 passed.
- Full Flutter suite: 484 passed.
- `flutter analyze`: no issues found.
- `flutter build web`: passed; Wasm dry run passed.
- Supabase pgTAP: 16 assertions authored but not executed because the Supabase
  CLI is unavailable on this machine.
- `git diff --check`: recorded in the final milestone report.

## Persistence and release boundary

- SQLite version: 14.
- Migration: additive v13-to-v14; all financial values and history remain
  unchanged.
- No initial financial upload/download, Realtime, OS background service, or
  conflict-resolution UI is included.
- BETA-04, BETA-05, and D14 remain open.

