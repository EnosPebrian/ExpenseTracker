# BETA-08L0 Engineering Checkpoint — Complete

Date: 2026-09-07

Verdict: **ENGINEERING PASS** for Transaction Category Identity Foundation.
Owner/runtime acceptance remains deferred. No hosted migration was deployed.

## Delivered contract

- SQLite 26 adds nullable `transactions.category_id`.
- Backup v5 stores category snapshot plus nullable authoritative identity and
  still reads v1–v4.
- `categoryId` is authoritative when known; `category` is historical display /
  unresolved fallback. Null identity is valid.
- The v25→v26 backfill selects exactly one normalized same-book/type category,
  including archived categories; ambiguous and unmatched rows remain null.
- Non-null identity is validated against category existence, household, and type.
- Manual entry/edit and source-neutral import/rules persist coherent ID+snapshot.
- Category rename retains historical snapshot and stable ID.
- Push/pull, initial sync, snapshots and conflicts preserve the nullable field.
  Old-client changed category/type clears a stale ID; unchanged values preserve it.
- Backup clone remaps known IDs. Selective recovery never guesses identity from a
  matching label and never leaks foreign-household IDs.
- Health Check accepts null and diagnoses dangling/foreign/incompatible IDs.

Detailed semantics and limitations are in `TRANSACTION_CATEGORY_IDENTITY.md`.

## Database status

- New migration:
  `20260904141514_beta08l0_transaction_category_identity.sql`
- `supabase db reset --local`: PASS.
- `supabase test db --local`: PASS, 192/192 pgTAP assertions across 11 files.
- Safe search paths, restricted helper execution, and existing RLS are retained.
- Hosted deployment: **NOT RUN / NOT AUTHORIZED**.

## Verification

- Dart format: PASS for changed Dart files.
- Focused final migration/category regression: 61/61 PASS.
- Broader category/bootstrap/backup/health/transfer focus before the migration
  compatibility correction: 84/84 PASS.
- `flutter analyze`: PASS, no issues (rerun after final production correction).
- Full Flutter regression: 849/849 PASS with concurrency 1 and two-minute per-test
  timeout. The first full run exposed ten historical partial-schema migration
  fixtures; v26 was corrected to traverse those fixtures safely, all ten were
  covered in the focused 61-test rerun, and the final full run passed.
- `flutter build web`: PASS.
- `flutter build windows --debug`: PASS.
- `flutter build apk --debug`: PASS. `file_picker` emitted its existing
  forward-looking Kotlin compatibility warning.
- `git diff --check`: PASS; only line-ending conversion notices were emitted.

## Scope confirmation

BETA-08L tithe tracking, BETA-08M category resolution, future Portable CSV, and
BETA-08N0/N1 investment/brokerage work were not implemented. Monetary reports,
deterministic transaction UUID derivation, Supabase deployment, and release
signing are unchanged. The future requirement for machine-safe plus
human-readable/editable CSV is documented but remains a separately contracted
backlog capability.

BETA-08L may resume after the separately authorized hosted migration rollout and
the milestone's intentionally deferred owner/runtime acceptance as applicable.
