# D13C2 Complete — Obsolete Seed Retirement and Compatibility Cleanup

## Completed behavior

- Centralized retirement rules for the exact fixed ID
  `asset-stock-portfolio`; display-name matches are not special-cased.
- Removed the obsolete definition from fresh bootstrap defaults, Quick Add
  fallback construction, and normal create/buy selection.
- Added automatic soft-archive for unused or fully closed legacy rows using the
  existing lifecycle metadata.
- Kept an open legacy holding active as sell-only, subject to the existing D12
  oversell, precision, lot, fee, and execution-reference rules.
- Automatically archives the definition after a closing transaction and keeps
  historical snapshots, cost basis, and realized gain readable.
- Blocked identity edits and permanent-system-seed restore with an actionable
  message; ordinary same-name user definitions remain unaffected.
- Added consistent Asset Conversion, Quick Add, edit-form, and Asset Management
  legacy behavior and warning presentation.

## Compatibility retained

- `assetDefinitionId` resolution and transaction snapshot fallback.
- Historical generic-stock transactions and portfolio calculations.
- Soft deletion, versioning, timestamps, and sync metadata.

No transaction relinking, ticker inference, hard deletion, persistence flags,
or replacement IDs were added.

## Verification

- Focused D13C2/D13 closure tests: 130 passed.
- `flutter analyze`: no issues found.
- Full `flutter test`: 388 passed.
- `flutter build web`: successful, including the Wasm dry run.
- SQLite remains version 10; no migration was added.

## Deferred to D14

- Regression cleanup, documentation review, and release hardening.
- Backup/restore, onboarding, security/PIN, installers, and signed builds remain
  outside D13C2.
