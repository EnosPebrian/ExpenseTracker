# Checkpoint — BETA-04B Complete Locally

## Completed behavior

- Owner-confirmed, remote-empty, one-time primary snapshot upload.
- Stable SQLite snapshot and outbox boundary with bounded idempotent batches.
- Authorized stable secondary download into durable staging.
- Non-merge target protection and atomic manifest/reference validation.
- Durable interruption, retry/resume, cancellation, progress, and safe errors.
- Cursor handoff to BETA-04A incremental push/pull only after `ready`.
- Focused Cloud Sharing initialization UI with strong owner confirmation.
- Server authorization/idempotency pgTAP coverage added.

## Persistence

- SQLite schema version: 15.
- Additive v14-to-v15 migration expands `sync_cursors` and adds
  `initial_sync_staging`; existing records and cursors are preserved.
- Supabase migration:
  `202607260003_beta04b_initial_sync.sql`.

## Verification

- Focused BETA-04B and adjacent regression tests: 35 passed.
- Full Flutter suite: 493 passed.
- Flutter analyzer: no issues.
- Web release build and Wasm dry run: succeeded.
- Supabase CLI/pgTAP execution: unavailable locally; the 17-assertion suite is
  ready for the owner environment with the CLI and local Docker runtime.

## Remaining BETA-04C scope

Conflict review/resolution UX, optional Realtime wake-up, and remaining
incremental synchronization polish. BETA-05 still owns real Enos/Grace
two-device acceptance and recovery proof.
