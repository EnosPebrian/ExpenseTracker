# D12D Complete - Asset Quantity Precision and Deterministic Rounding

Date: 2026-07-24

## Numeric policy

- Added one pure `AssetNumericPolicy` for validation, unit-price derivation,
  comparison tolerance, and measurable-quantity normalization.
- New/edit precision defaults are: stock 0, foreign currency 2, gold 4,
  cryptocurrency 8, inventory 3, and other measured assets 4 decimals.
- Stock quantities require whole shares; D12D does not enforce lot-size
  multiples.
- Unit price remains integer IDR and uses `(amount / quantity).round()` for
  both buys and sells. Fees never alter the derived unit price.
- Tolerance is six guard digits beyond each asset kind's supported precision.
  Near-zero balances and harmless supported-precision artifacts normalize at
  sequence/portfolio boundaries; materially negative quantities remain intact
  and invalid.

## Validation and presentation

- Asset Conversion, Quick Add, and transaction create/edit validation reject
  non-positive, non-finite, and over-precision quantities without changing the
  entered text.
- Forms show the supported precision and use whole-number keyboard hints for
  stocks while retaining decimal input for measured assets.
- One `AssetQuantityFormatter` now serves dashboard holdings, conversion
  summaries, sale availability, and transaction detail quantities.
- Historical over-precision records are not rewritten or rejected during load;
  they remain displayable and continue participating in portfolio calculations.

## Persistence

- SQLite remains version 9.
- No migration or persisted precision field was added.
- Existing `REAL` quantities remain unchanged.

## Verification

- Focused D12D tests: 113 passing, followed by 53 passing after the final
  normalization adjustment.
- `flutter analyze`: clean (`No issues found`).
- Full `flutter test`: 248 passing.
- `flutter build web`: successful, including the WebAssembly dry run.

## Deferred D12 work

- D12E stock lot-size validation and odd-lot rules.
- D12F spread and execution-price presentation.
- Configurable definition-level precision remains a future extension.
