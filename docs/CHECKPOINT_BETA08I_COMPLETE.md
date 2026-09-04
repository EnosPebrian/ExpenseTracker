# BETA-08I Checkpoint — Monthly & Annual Financial Statements

Date: 2026-08-31

## Status

**BETA-08I Engineering PASS.** Implementation and required engineering gates
are complete. Owner runtime acceptance remains NOT RUN.

## Delivered boundary

- Monthly and Annual statements for Household and Account scopes.
- Pure `FinancialStatementGenerator` over existing financial primitives.
- Immutable statement models and deterministic account running balances.
- Local/offline PDF rendering and existing cross-platform save abstraction.
- Canonical transfer, legacy transfer, budget, tithe, deleted-record, and
  multi-currency safeguards.
- Responsive Reports > Financial Statements UI and empty-period handling.
- Explicit omission of unsupported historical year-end net worth.

## Versions and remote boundary

- SQLite: 25 (unchanged by BETA-08I).
- Encrypted backup: v4 (unchanged by BETA-08I).
- Supabase/SQL: no BETA-08I changes.
- Hosted Supabase and BETA-08H1 deployment: untouched.
- Statements: generated on demand; no table, sync entity, or backup record.

## Verification record

- Focused BETA-08I tests: 13/13 PASS; the 5,000-transaction annual generation
  and PDF case completed in approximately three seconds.
- Analyzer: PASS, no issues.
- Full Flutter suite: 810/810 PASS at concurrency 2.
- Web build: PASS, including Wasm dry run.
- Windows debug build: PASS.
- Android debug APK build: PASS; the existing forward-looking `file_picker`
  Kotlin compatibility warning remains non-blocking.
- `git diff --check`: PASS.

See `BETA08I_OWNER_ACCEPTANCE.md` for deferred runtime acceptance.
