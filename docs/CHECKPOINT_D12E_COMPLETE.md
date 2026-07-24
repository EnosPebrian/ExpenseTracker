# D12E Complete - Stock Lot-Size and Odd-Lot Rules

Date: 2026-07-24

## Behavior

- Stock quantity remains persisted as shares; lot count and odd-lot status are
  derived from the linked concrete definition's `lotSize`.
- New buys and normal sales require whole-share multiples of `lotSize`.
- Lot size 1 accepts any positive whole-share quantity.
- A historical odd-lot position may sell whole lots, sell its odd residue to
  leave whole lots, or close the position completely. A clean whole-lot
  position cannot create a new odd residue.
- Date-specific validation reuses chronological D12A availability and excludes
  the original transaction during edits. Destination and source identities are
  revalidated when an edit changes asset identity.
- Historical and legacy positions remain readable and are never rewritten.

## Architecture and UI

- `AssetStockLotPolicy` owns pure lot validation.
- `AssetTradeValidator` coordinates lot validation with the existing sequence
  validator immediately before persistence.
- Asset Conversion, Quick Add, and transaction updates share the same policy.
- Stock forms show the definition lot size, derived shares/lots, odd-lot
  availability, cleanup amount, and remaining shares/lots. Non-stock assets and
  lot-size-1 stocks remain uncluttered.
- Portfolio calculations remain share-based; portfolio display derives whole
  or fractional lots from each holding's definition.

## Persistence

- SQLite remains version 9.
- No migration or derived lot fields were added.

## Verification

- Focused D12E tests: 117 passing, followed by 85 passing after the final
  structured-result correction.
- `flutter analyze`: clean (`No issues found`).
- Full `flutter test`: 271 passing.
- `flutter build web`: successful, including the WebAssembly dry run.

## Deferred D12 work

- D12F spread and execution-price presentation.
- Broker/market-specific odd-lot overrides and corporate actions remain future
  work.
