# D13C1 Complete — Asset Catalog UX

## Completed behavior

- Added immediate local search across display name, symbol, provider symbol,
  exchange, valuation currency, unit, and friendly asset-kind label.
- Added lifecycle-scoped multi-kind and pricing filters with clear active-filter
  feedback, result counts, and a clear-filters action that preserves lifecycle.
- Added deterministic presentation-only sorting by name, recent update, kind,
  and symbol with normalized-name and definition-ID tie-breakers.
- Added distinct empty states for a new catalog, no filter matches, and an empty
  archive, including only the contextually safe actions.
- Added responsive desktop/mobile catalog composition without changing the app
  shell or persisting catalog state.
- Grouped the editor into Identity, Trading and measurement, and Pricing
  provider sections.
- Added create-only, dirty-field-aware defaults and explicit IDX,
  symbol-as-unit, and FX provider-pair actions.
- Presets do not enable online pricing, overwrite explicit values, alter linked
  fields, or bypass D13A validation.
- Preserved D13B archive/restore, open-position blocking, historical resolution,
  and linked-field protection.

## Verification

- Focused D13C1 and D13A/D13B regression tests: 83 passed.
- SQLite remains version 10; no migration or catalog-state persistence was added.
- `flutter analyze`: no issues found.
- Full `flutter test`: 375 passed.
- `flutter build web`: successful, including the Wasm dry run.

## Remaining D13C2 work

- Retire the obsolete `asset-stock-portfolio` seed safely.
- Complete legacy-seed compatibility cleanup and the D13 closure audit.
