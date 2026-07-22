# Pilgrim Tracker Documentation Manifest

**Snapshot date:** 2026-07-21  
**Verified project state:** `flutter analyze` clean; `flutter test` passes with 93 tests

## Mandatory read order

1. `PRODUCT_SPEC.md`
2. `ARCHITECTURE.md`
3. `ARCHITECTURE_DECISIONS.md`
4. `DATABASE_SCHEMA.md`
5. `ROADMAP.md`
6. `PROGRESS.md`
7. `NEXT_STEP_PLAN.md`
8. `CONTINUATION_PROMPT.md`

Do not begin a database, transaction, asset, dashboard, tithe, or synchronization change before reading these files.

## Update rule

Every feature batch must update:

- `PROGRESS.md`
- `ROADMAP.md`
- `ARCHITECTURE.md` when boundaries or dependencies change
- `DATABASE_SCHEMA.md` when storage changes
- automated tests
- database migration when persisted data changes

A feature is not complete until formatting, analysis, tests, and documentation are updated.
