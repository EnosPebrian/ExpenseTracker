# D12B Complete — Persisted Trade Fees and Asset Accounting

## Behavior completed

- Asset trades persist integer `feeAmount` and stable `AssetFeeTreatment` values.
- Buy fees may be capitalized into weighted-average cost basis.
- Sell fees may be deducted from gross proceeds before realized-gain calculation.
- Gross trade `amount`, quantity, and the existing `(amount / quantity).round()`
  unit-price rule remain unchanged.
- Zero fees normalize to `none`; invalid action/treatment combinations, negative
  fees, and sell fees greater than or equal to gross proceeds are rejected.
- Fee validation does not bypass D12A chronological oversell prevention.

## Persistence

- SQLite upgraded from version 7 to version 8.
- Added `transactions.fee_amount INTEGER NOT NULL DEFAULT 0`.
- Added `transactions.fee_treatment TEXT NOT NULL DEFAULT 'none'`.
- The v7-to-v8 migration preserves transactions, asset snapshots/definition
  links, asset definitions, and cached market prices.
- Legacy rows load as fee-free; unknown treatment values safely fall back to
  `none`.
- Native SQLite and the web in-memory record path use the same entity mapping.

## UI and controller

- Asset Conversion and Quick Add accept an optional formatted fee amount.
- Buy mode offers `No fee` and `Add fee to cost basis`.
- Sell mode offers `No fee` and `Deduct fee from proceeds`.
- Incompatible handling resets when the trade action changes.
- Summaries show asset value/gross proceeds, fee, total paid/net received.
- Transaction detail shows persisted fee and settlement totals.
- Failed validation preserves entered values.

## Verification

- Focused D12B and D12A-regression tests: 96 passed.
- Full test suite: 213 passed.
- `flutter analyze`: no issues.
- `flutter build web`: successful, including Wasm dry run.
- SQLite schema: version 8.

## Deferred D12 work

- Recording fees as separate linked expenses
- Fee categories and percentage/broker fee calculators
- FX and broker spread modeling
- Generalized precision and rounding policies
- Stock lot-size enforcement
