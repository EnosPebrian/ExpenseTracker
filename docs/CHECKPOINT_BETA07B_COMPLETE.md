# BETA-07B Engineering Checkpoint — Copy Monthly Budgets

**Date:** 2026-08-03  
**Verdict:** Engineering complete; unreleased pending owner acceptance.

## Delivered behavior

- Users can open **Copy budgets** from any displayed target month and select a
  different source month.
- Preview reports source plans, missing target plans to add, plans already
  present, unavailable categories, warnings, and the expected target total.
- Copying preserves category, positive integer amount, household base currency,
  and optional note while creating a new target-month budget identity.
- Spending, progress, percentages, and other derived values are never copied.
- The only mode is add-missing-only. Existing target plans are neither
  overwritten nor duplicated; repeated/no-op copies create no outbox noise.
- Archived or soft-deleted categories are shown and skipped; genuinely missing
  categories are warned and skipped; cross-household references are rejected.
- A compact planning summary shows budgeted-category count, planned total, and
  the latest copy count when applicable.

## Architecture and safety

`MonthlyBudgetCopyService` owns pure classification and candidate creation.
`MonthlyBudgetController` coordinates preview, busy/error state, copying, and
immediate refresh. `LocalMonthlyBudgetRepository` adapts the domain service to
native/web stores. On native SQLite, all copied rows and their ordinary budget
outbox entries commit in one transaction; any failure rolls the batch back.
Local-only copying creates no outbox entries. Web retains atomic snapshot
rollback parity.

No new entity, remote bulk-copy RPC, schema field, persisted derived total, or
rollover/carryover model was introduced. Existing budget synchronization,
conflict resolution, encrypted backup v2/v1 compatibility, restore, and CSV
behavior remain unchanged.

## Verification

- `dart format` completed for the eight changed BETA-07B Dart files.
- Focused BETA-07B tests: **10 passed**.
- `flutter analyze`: **No issues found**.
- Complete Flutter suite: **616 passed**.
- `flutter build web`: passed; Wasm dry run also succeeded.
- `flutter build windows --debug`: passed;
  `build\windows\x64\runner\Debug\pilgrim_tracker.exe` produced.
- `flutter build apk --debug`: passed;
  `build\app\outputs\flutter-apk\app-debug.apk` produced.
- Android emitted only the known forward-looking `file_picker` Kotlin Gradle
  Plugin compatibility warning.
- No Supabase reset or pgTAP run was needed because no SQL changed.

## Persistence and compatibility

- SQLite remains version **21**; no local migration was added.
- No Supabase migration or synchronization-protocol change was added.
- Encrypted backup format remains **v2**, with existing v1 compatibility.
- D14 remains historically complete and unchanged in scope.
- Existing uncommitted BETA-07A work was preserved.

## Owner acceptance steps

1. On Windows, create source-month budgets with distinct limits and notes.
2. In a later target month, create one different target budget for a source
   category, then open **Copy budgets**.
3. Select the source month and confirm source/target labels, add count,
   already-present count, unavailable-category status, and expected total.
4. Cancel and confirm no target rows or sync activity changed.
5. Reopen the preview, confirm, and verify only missing active-category plans
   appear immediately with limits and notes preserved.
6. Confirm the pre-existing target plan retained its original value and note.
7. Repeat the same copy and confirm the result reports zero additions and does
   not create duplicate target rows or synchronization operations.
8. Record source- and target-month expenses and confirm each month's spending,
   progress, and unbudgeted spending remain transaction-derived independently.
9. Synchronize to Android and confirm copied plans arrive as ordinary budgets;
   close/reopen both clients and confirm persistence.
10. Repeat a local-only copy and confirm it works without cloud configuration.

## Remaining limitations

- Copy is explicit and add-missing-only; there is no overwrite mode.
- There is no automatic monthly copy, rollover, overspending carryover,
  forecasting, suggestions, notifications, weekly/yearly planning,
  per-member/account budgets, goals, or debt planning.
- Web persistence remains an in-memory development preview.
- BETA-07A/B remain unreleased until owner acceptance is recorded.

Recommended next milestone after acceptance: **BETA-07C — Budget owner
acceptance and release-readiness closure**, without expanding budget scope.
