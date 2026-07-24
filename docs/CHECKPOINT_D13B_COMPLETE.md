# D13B Complete — Asset Definition Lifecycle

## Completed behavior

- Added pure transaction-derived definition usage and linked-edit policy.
- Unused and fully closed definitions may be archived; open holdings are blocked
  with a formatted quantity explanation.
- Soft-deleted asset conversions remain historical links without affecting open
  quantity; generated fee expenses and legacy snapshot-only rows do not link.
- Restore reuses the same definition ID, creation timestamp, and provider
  configuration, increments version metadata, and reruns full D13A integrity.
- Repeated archive/restore operations are safe and do not create duplicates.
- Linked definitions may edit display name and valid provider configuration.
- Linked kind, symbol, exchange, currency, unit, and lot size are protected.
- Archived definitions are read-only and excluded from new transaction selectors.
- Historical portfolio resolution includes archived definitions, preserving
  cost basis and realized gain behavior.
- Archive does not remove cached market prices or alter transaction snapshots.
- Asset Management now has Active and Archived views, lifecycle actions, usage
  summaries, confirmation, conflict messages, and responsive protected fields.

## Verification

- Focused D13B tests: 90 passed.
- `flutter analyze`: no issues found.
- Full `flutter test`: 346 passed.
- `flutter build web`: successful, including Wasm dry run.
- `git diff --check`: clean.
- SQLite schema remains version 10; no migration was added.

## Remaining D13C work

- Asset-definition search, kind filtering, and sorting controls.
- Currency/unit preset refinements and remaining management finalization.
- Obsolete seed retirement and other explicitly deferred cleanup.
