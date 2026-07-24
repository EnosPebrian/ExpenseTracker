# D13A Complete — Asset Definition Integrity

## Completed behavior

- Added one pure-domain `AssetDefinitionIntegrityPolicy` with structured field,
  code, message, and conflicting-definition metadata.
- Stock identity uses normalized symbol plus exchange. Matching symbols conflict
  when either exchange is missing; distinct explicit exchanges may coexist.
- Non-stock definitions protect their established stable market-price identity.
- Online provider code plus provider symbol is unique across asset kinds.
- Active and archived definitions participate in create, edit, and seed checks.
- Online pricing requires provider code and symbol; foreign-currency pairs must
  match source and valuation currency.
- Disabling online pricing retains stored provider configuration.
- The asset editor keeps entered values after rejection, shows field errors,
  clears stale errors on correction, and remains responsive at narrow widths.
- Seed validation remains idempotent and runs before repository insertion.

## Files changed for D13A

- `lib/features/assets/domain/services/asset_definition_integrity_policy.dart`
- `lib/features/assets/controllers/asset_definition_controller.dart`
- `lib/features/assets/presentation/screens/asset_management_screen.dart`
- `test/asset_definition_integrity_policy_test.dart`
- `test/asset_definition_controller_test.dart`
- `test/asset_management_screen_test.dart`
- `docs/ROADMAP_D10_TO_D14.md`
- `docs/ARCHITECTURE.md`
- `docs/PRODUCT_SPEC.md`

## Verification

- Focused D13A tests: 32 passed.
- `flutter analyze`: no issues found.
- Full `flutter test`: 323 passed.
- `flutter build web`: successful, including Wasm dry run.
- SQLite schema remains version 10; no migration was added.
- No conflicts were found in the default definition seeds or test fixtures.

## Deferred D13 work

- Archive and restore UI/workflows.
- Restrictions for editing definitions linked to historical transactions.
- Asset-management search/filter and remaining finalization work.
- Existing conflicting user data, if encountered, is reported and is never
  automatically deleted or merged.
