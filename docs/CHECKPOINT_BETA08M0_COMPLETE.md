# BETA-08M0 Completion Checkpoint

**Milestone:** Durable Transaction Note & Reference Foundation
**Date:** 2026-09-08
**Engineering status:** Local engineering PASS; hosted rollout pending
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
- External logical recovery point: pending.
- Hosted dry-run / deployment / verification: pending.
- Git finalization: pending.

Future Portable CSV, BETA-08M category resolution, and BETA-08N0/N1 were not
implemented. Owner runtime acceptance remains deferred until after engineering
completion.
