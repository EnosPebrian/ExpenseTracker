# D12C Complete - Linked Asset Fee Expense

Date: 2026-07-24

## Completed behavior

- Added `recordAsSeparateExpense` for asset buy and sell fees.
- Added explicit transaction relationship metadata for generated fee expenses.
- Added the stable `Asset Fees` default expense category.
- Parent asset conversions preserve the gross trade amount and portfolio
  accounting; one linked ordinary expense records the fee for reports.
- Create, edit, treatment switching, duplicate, and parent delete maintain one
  managed child through the transaction use-case layer.
- Managed fee expenses cannot be independently edited, duplicated, or deleted.
- Conversion and transaction-detail UI distinguish fee expense, cost basis,
  gross proceeds, and net cash effect.

## Persistence

- SQLite version: 9.
- Migration 8 -> 9 adds `related_transaction_id`, `relation_type`, and the
  composite relation lookup index.
- Native writes use one SQLite transaction; web in-memory writes use a
  rollback-capable atomic change set.
- Existing fee fields, asset snapshots, definitions, and cached prices are
  preserved by migration tests.

## Verification

- Focused D12C tests: 103 passing.
- `flutter analyze`: clean (`No issues found`).
- Full `flutter test`: 227 passing.
- `flutter build web`: successful; Wasm dry run also succeeded.

## Deferred D12 work

- Spread modeling.
- Percentage-fee calculators and broker schedules.
- Generalized currency precision and rounding policy.
- Stock-lot enforcement and remaining D12 hardening.
