# D12F Complete - Execution Reference and Price Presentation

Date: 2026-07-24

## Behavior

- Parent asset conversions may optionally save an immutable market-reference
  snapshot: integer IDR price per asset unit, unit, currency, source, and quote
  timestamp.
- Users can enter a manual reference offline or explicitly copy the latest
  compatible cached price. No reference is attached or fetched automatically.
- Create, Quick Add, and edit share the same controller/domain validation path.
  Edits preserve the snapshot until replaced or cleared; duplicates and linked
  fee expenses start without one.
- Detail and conversion forms show gross execution price, saved reference,
  direction-aware estimated difference, source, and timestamp. Fee-adjusted
  cash rates remain separately labeled.

## Architecture and accounting

- `AssetExecutionAnalysis` is a pure service. Buy difference is execution minus
  reference; sell difference is reference minus execution. Positive is
  unfavorable, negative favorable, and integer total impact uses deterministic
  nearest-money rounding.
- Reference analysis is informational only. It does not affect amount,
  quantity, unit price, cost basis, gains, availability, lot validation, fees,
  linked expenses, financial summaries, or tithe.
- The comparison is against a saved reference quote and is not a verified
  historical bid/ask spread. Price history and live bid/ask data remain deferred.

## Persistence

- SQLite is version 10.
- The v9-to-v10 migration adds five nullable transaction columns without
  rewriting existing rows. Fresh-install and web record-map parity are updated.
- Migration coverage preserves legacy fee/relation metadata, asset definitions,
  and the latest-price cache.

## Verification

- Focused D12F and affected regression tests: 67 passing; the final targeted
  controller extraction regression set passed 57 tests.
- `flutter analyze`: clean (`No issues found`).
- Full `flutter test`: 297 passing.
- `flutter build web`: successful, including the WebAssembly dry run.

## Deferred

- True historical bid/ask spreads, order books, quote history, broker
  integrations, and automatic execution remain out of scope.
- D12 remains open pending final engineering review.
