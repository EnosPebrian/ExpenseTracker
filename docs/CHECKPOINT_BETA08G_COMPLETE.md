# BETA-08G Engineering Checkpoint

Date: 2026-08-29

Status: **Engineering PASS**. BETA-08A1 through BETA-08G owner/runtime
acceptance is **NOT RUN**.

- Phase 0 Windows and Android debug gates passed, closing BETA-08F1 and
  consolidated BETA-08F as Engineering PASS.
- SQLite is v24 with additive session/draft tables and native/web parity.
- Backup remains v4 and excludes uncommitted inbox workflow state.
- Stable session, draft, source-row, and deterministic transaction identities
  survive restart and synchronization.
- Current rules, duplicates, transfers, account/category availability, and
  stable-ID conflicts are recalculated on resume without erasing manual edits.
- Discard is workflow-only; commit is explicit; crash reconciliation prevents
  duplicate re-import.
- CSV, receipt/invoice, and bank statement flows can save normalized drafts for
  later. Source bytes and provider payloads are not retained.
- One local, undeployed migration adds RLS, validation, change-feed, push, pull,
  conflict, and initial-snapshot coverage.
- Telegram remains documentation-only future work.

## Engineering verification

- Phase 0 Windows debug build: PASS.
- Phase 0 Android debug APK build: PASS.
- Focused BETA-08G Flutter tests: 22/22 PASS.
- Full Flutter suite: 777/777 PASS.
- Flutter analyzer: PASS, no issues.
- Web compilation: PASS, including the Wasm dry run.
- Local Supabase reset: PASS; every local migration applied.
- Local pgTAP suite: 134/134 PASS across 8 files; BETA-08G contributes
  20 assertions.
- Final Windows debug build: PASS.
- Final Android debug APK build: PASS with the existing non-blocking
  `file_picker` forward-looking Kotlin compatibility warning.
- `git diff --check`: PASS.

No hosted migration or Edge Function was deployed, and no owner/device
acceptance was performed by engineering.
