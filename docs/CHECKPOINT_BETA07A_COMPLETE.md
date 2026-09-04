# BETA-07A Engineering Checkpoint

**Date:** 2026-08-02

**Verdict:** Implementation complete; unreleased pending owner acceptance.

BETA-07A adds monthly household expense-category budgets with exact integer
limits, derived spending/progress/unbudgeted totals, soft deletion and safe
identity reuse, SQLite v21 native persistence and web-preview parity, existing
Supabase synchronization and explicit conflict handling, encrypted backup
format v2 with safe format-v1 compatibility, atomic restore, and CSV export.

No default budget is seeded. Transactions and financial calculations outside
budget reporting are unchanged. D14 remains the completed historical baseline
for controlled private deployment.

## Deferred by scope

Rollover, weekly/yearly/member/account budgets, suggestions, forecasting,
savings goals, debt plans, notifications, scheduled jobs, and public-release
work remain deferred.

## Acceptance gate

Engineering tests/builds establish implementation readiness only. Enos and
Grace should complete the exact acceptance sequence in `BUDGETS.md` before the
milestone is marked released.

## Engineering validation

- `dart format`: changed Dart files formatted.
- Focused Flutter tests: 38 passed.
- Complete Flutter suite: 606 passed.
- `flutter analyze`: passed with no issues.
- Flutter web compilation: passed.
- Local Supabase database reset: passed through all migrations, including
  `202608020001_beta07a_monthly_category_budgets.sql`.
- Complete local pgTAP suite: 81 passed across 5 files; the BETA-07A focused
  file contributed 20 checks.
- Windows debug compilation: passed; unsigned debug executable produced.
- Android debug APK compilation: passed; the existing forward-looking
  `file_picker` Kotlin compatibility warning remains non-blocking.
- Release-signing and production Supabase gates were intentionally not run for
  this unreleased engineering checkpoint.
