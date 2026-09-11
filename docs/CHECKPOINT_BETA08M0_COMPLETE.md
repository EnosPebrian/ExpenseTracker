# BETA-08M0 Completion Checkpoint

**Milestone:** Durable Transaction Note & Reference Foundation
**Date:** 2026-09-08
**Engineering status:** PASS; hosted migration deployed
**Owner acceptance:** NOT RUN

## Implemented boundary

Pilgrim transactions now carry nullable durable `note` and `reference` through
the existing entity, SQLite 27/web stores, full edit UI, shared import
finalization, sync/conflict/bootstrap protocol, encrypted backup v6, clone, and
selective recovery. Metadata remains outside deterministic transaction identity
and financial calculations. Legacy omitted sync properties preserve existing
values; explicit null clears them.

One ordered Supabase migration is present:
`20260908124412_beta08m0_transaction_note_reference.sql`.

## Verification record

- Focused Flutter: 8/8 PASS.
- Analyzer: PASS.
- Full Flutter: 928/928 PASS.
- Web/Windows/Android debug builds: PASS. Android required a temporary
  one-worker Gradle retry after an environment-only DartWorker thread failure.
- Local Supabase full migration replay: PASS.
- BETA-08M0 pgTAP: 23/23 PASS.
- Full local pgTAP: 290/290 PASS across 14 files.
- External logical recovery point: PASS; see
  `CHECKPOINT_BETA08N_RC_COMPLETE.md`.
- Hosted dry-run / ordered deployment / verification: PASS on 2026-09-11.
- Hosted migration history records `20260908124412` exactly once.
- Git engineering finalization was completed before this rollout; rollout
  documentation is recorded by PT-BETA-08N-RC.

Owner runtime acceptance remains deferred. Feature additions outside the
accepted BETA-08N work remain frozen.
