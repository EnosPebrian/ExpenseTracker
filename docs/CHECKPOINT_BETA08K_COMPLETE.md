# BETA-08K Engineering Checkpoint

Closure date: 2026-09-04

Verdict: BETA-08K Engineering PASS. Owner runtime acceptance remains NOT RUN.

## Delivered

- Existing authenticated active-membership discovery presents every
  initialized additional hosted household instead of silently binding the
  first membership.
- The selected household's role/member context and protected manifest remain
  bound to that selection through initial download.
- Initial download continues to use durable staging, validation, atomic
  activation, stable member/financial identities, an independent device ID,
  and no-echo remote apply.
- Sync requests arriving during an active run are retained as one coalesced
  follow-up. Startup, foreground, mutation, Realtime wake-up, manual sync, and
  successful initialization continue through the existing coordinator.
- Sync status and BETA-08J Health Check expose pending, failed, conflict, and
  last-success state without treating cloud availability as local corruption.
- Existing import-rule semantics are unchanged; evaluation now normalizes each
  draft input once so the preserved 500-rules/5,000-drafts regression remains
  practical under the required single-concurrency full-suite gate.
- No SQLite file synchronization, alternate transport, background service,
  database migration, backup-format change, or hosted deployment was added.

## Version and deployment state

- SQLite: 25 (unchanged)
- Encrypted backup: v4 (unchanged)
- Supabase migrations: none added; pending BETA-08E/F0/G/G1/H migrations remain
  undeployed
- Edge Functions: unchanged and not deployed by this milestone
- BETA-08L, BETA-08M, and BETA-08N: not implemented

## Verification scope

Focused coverage includes coordinator single-flight/coalescing, initial upload
guards, empty-device staged download, all-entity integrity fixtures,
interruption/restart/idempotency, populated-target rejection, membership/RLS
classification, multiple-household selection, Health Check sync state, and a
5,000-transaction activation without a fragile time threshold. Final command
counts and build results are recorded in `progress.md`.

Final verification: 82 focused durability/bootstrap tests and 832 full-suite
tests passed. Flutter analysis reported no issues. Web (including the
WebAssembly dry run), Windows debug, and Android debug builds passed. The
Android build retained the known forward-looking `file_picker` Kotlin Gradle
Plugin compatibility warning.
