# D12 Complete - Final Engineering Closure

Date: 2026-07-24

## Completed scope

- D12A prevents date-specific asset oversells across create, edit, and delete.
- D12B persists trade fees and applies capitalized buy fees or deducted sell
  fees to weighted-average accounting.
- D12C creates one managed linked expense for separate-expense fees and keeps
  parent/child create, edit, duplicate, and delete atomic.
- D12D centralizes quantity precision and deterministic integer-money rounding.
- D12E enforces stock lots while supporting valid historical odd-lot cleanup.
- D12F stores optional immutable execution-reference snapshots and calculates
  direction-aware informational execution differences without changing
  accounting.

## Closure audit

- Fresh databases create the complete version 10 schema.
- Representative v5, v7, v8, and v9 databases upgrade safely to version 10.
  Tests preserve transaction and asset snapshots, definitions, cached prices,
  fee/relation fields, reference snapshots, and soft-delete/sync metadata.
- A combined BBCA scenario verifies capitalized and deducted fees, lot rules,
  weighted-average cost, realized gain, and reference-price isolation.
- Separate-expense fee coverage verifies exactly one metadata-free linked
  expense, edit reuse, independent duplicate linkage, and coordinated deletion.
- Stock oversell, whole-lot, exact-sale, fractional-share, and historical
  odd-lot cleanup behavior remains enforced with fees and references present.
- USD regression coverage verifies two-decimal precision, date-specific
  availability, non-stock lot behavior, fee accounting, reference isolation,
  USD/SGD identity isolation, and realized gain after full sale.

## Verification

- Focused closure audit: 105 tests passing, including four new integration and
  fresh-schema tests.
- No production Dart code or schema changed during the audit.
- Verified pre-audit baseline retained: `flutter analyze` clean, full
  `flutter test` 297 passing, and `flutter build web` successful.
- SQLite remains version 10; no closure migration was required.
- Canonical tracked root architecture document: `docs/ARCHITECTURE.md`.

## Maintainability review

- `asset_conversion_controller.dart`: 610 lines; conversion coordination only.
- `asset_execution_reference_controller.dart`: 92 lines; reference input state.
- `transaction_form.dart`: 454 lines; transaction edit presentation/state.
- `asset_execution_reference_fields.dart`: 213 lines; focused reference UI.
- `transaction_usecases.dart`: 365 lines; transaction lifecycle use cases.
- `save_asset_conversion_with_fee.dart`: 131 lines; atomic fee-child lifecycle.
- `asset_trade_validator.dart`: 112 lines; trade validation coordination.
- `asset_numeric_policy.dart`: 166 lines; precision and rounding policy.

No duplicated business rule or unrelated responsibility warranted production
refactoring during this audit.

## Deferred limitations

- Historical bid/ask feeds, price history, order books, broker integration, and
  automatic execution remain deferred.
- D13 asset-management finalization and D14 release hardening remain unchanged.
