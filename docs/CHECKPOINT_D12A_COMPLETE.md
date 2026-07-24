# D12A Complete — Asset Oversell Prevention

## Behavior completed

- Added a pure chronological asset-transaction sequence validator.
- Asset sales cannot exceed the quantity available at the transaction date.
- Future purchases cannot fund backdated sales.
- Editing or moving a purchase is blocked when it would invalidate a later sale.
- Asset identity changes validate both the original and replacement histories.
- Deleting a required asset purchase is blocked; ordinary transaction deletion is unchanged.
- Quick Add and Asset Conversion show available sell quantity and clear oversell errors.
- Final validation runs immediately before create, update, duplicate, and relevant soft-delete writes.

## Identity, ordering, and tolerance

- Concrete assets are isolated by `assetDefinitionId`, including missing or archived definitions.
- Legacy transactions fall back to stored symbol/name and unit snapshots.
- Transactions replay by transaction date, then creation timestamp, matching portfolio ordering.
- Soft-deleted transactions are excluded.
- Quantity comparisons use a `1e-9` tolerance for the existing `double` quantity model.

## Main files changed

- `lib/features/assets/domain/services/asset_transaction_identity.dart`
- `lib/features/assets/domain/services/asset_transaction_sequence_validator.dart`
- `lib/features/assets/domain/services/asset_portfolio_calculator.dart`
- `lib/features/transactions/domain/usecases/transaction_usecases.dart`
- `lib/features/transactions/presentation/controllers/transaction_controller.dart`
- Asset Conversion and Quick Add controller/form integration
- `lib/features/assets/presentation/widgets/asset_sale_availability.dart`

## Verification

- Focused D12A and regression tests: 72 passed.
- Full test suite: 188 passed.
- `flutter analyze`: no issues.
- `flutter build web`: successful, including Wasm dry run.
- SQLite schema: version 7; no migration added.

## Deferred D12 work

- Fees and fee accounting
- Buy/sell spread modeling
- Generalized precision and rounding policies
- Stock lot-size enforcement
- Other D12B+ work
