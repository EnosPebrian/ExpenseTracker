# PT-BETA-09A — Sync Convergence & Conflict Reliability

## Status

Engineering gates PASS — Git publication in progress. Owner acceptance PENDING / NOT RUN.
Starting main/origin: `35ee692429499a25bf2cd6e0213e24ddbdbdf0c3` (clean).

## Diagnosis and implementation

See `BETA09A_ENGINEERING_ANALYSIS.md` for the pre-repair end-to-end trace and
`SYNC_CONVERGENCE.md` for the resulting contract. The critical cursor defect
advanced a global pull checkpoint from a single conflict resolution response,
potentially skipping unrelated imported rows. Conflict gating also prevented
independent household delivery, and retries lacked durable request identity.

The repair adds dependency-stage draining, dirty/newer-row protection, durable
resolution intent/idempotent retry, explicit merge dialog and confirmation,
canonical-response checks, and truthful local push/pull/cursor diagnostics.
Coordinated financial records remain whole-record resolutions, not unsafe field
hybrids. Existing accounting and financial identities are unchanged.

SQLite **29**, backup **v8**; no local schema migration. One additive server
migration: `20260927100120_beta09a_sync_serialization.sql`, sharing the existing
household transaction advisory lock between push and conflict resolution.
Hosted status: DEPLOYED on 2026-09-28 to pilgrim-tracker-dev
(`jylclfebdeaywfdwabph`).

## Automated evidence

- Focused historical/sync group: 152/152 PASS.
- Final sync/status follow-up: 29/29 PASS.
- Budget-copy fixture correction: 10/10 PASS; acknowledge category creation
  before remote archival, without weakening copy/accounting assertions.
- Final dedicated sync group: 15/15 PASS, including offline conflict review.
- Analyzer: PASS on final frozen source.
- First full suite: 1,036 passed / two budget-fixture failures, diagnosed above.
  Final serial full suite: **1,039/1,039 PASS** after fixture/UI verification.
- Local clean Supabase replay: PASS.
- Focused pgTAP: 17/17 PASS; full pgTAP: 360/360 across 18 files.
- Local/hosted pre-lint: unchanged dynamic-SQL `begin_initial_download` finding;
  not a new 09A error and not represented as a clean lint result.
- Web, Windows debug, Android debug APK: PASS. Android retains the known
  non-blocking file_picker Kotlin compatibility warning.
- Recovery point: `C:\Users\enosp\PilgrimTrackerBackups\pre-beta09a-20260928-140105`;
  roles/schema/data/history schema/history data all non-empty; five SHA-256
  hashes recorded and independently reread/verified.
- Dry-run: exactly one authorized migration; push PASS; remote history aligned.
- All 24 public-table row counts and content fingerprints unchanged. Public
  table RLS/ACL, policy definitions and function ACL/security/search-path
  fingerprints unchanged. Both targeted functions now have the household lock.
- Security advisor details/counts unchanged before/after; no new severe finding.
  Post-hosted lint retains only the same known initial-download dynamic-SQL issue.
- Commit/push: publication in progress; see engineering handoff for hashes.

## Limits and next work

Physical Windows/Android convergence and conflict UI acceptance remains NOT RUN.
Google Sheets is not required as primary storage for multi-device durability.
After all 09A gates and Git publication pass, continue only PT-BETA-09C, then
09B1 and 09B2 under the bounded owner authorization. No new feature is implied.
