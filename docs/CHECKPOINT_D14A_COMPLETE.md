# D14A Complete — Persistence and Integrated Regression Hardening

## Verdict

D14A is complete. The version-10 financial model survives fresh creation,
historical upgrades, close/reopen, repeated bootstrap, atomic linked-fee
changes, lifecycle operations, and integrated multi-asset accounting.

## Defects fixed

- Fresh version-10 databases now create the account-name, category-type, and
  project-name indexes already produced by the historical v3 upgrade path.
- Web transaction soft deletion now updates `updated_at` alongside
  `deleted_at`, version, and sync status, matching native behavior.

No persisted fields or repository contracts changed.

## Verification

- Fresh schema: all expected tables, transaction columns, and indexes present.
- Migration matrix: v1, v3, v5, v7, v8, and v9 upgrade to v10 with applicable
  transactions, project/master metadata, snapshots, definitions, prices, fees,
  relationships, soft deletion, sync metadata, and safe null defaults retained.
- Native reopen: IDs, snapshots, linked fees, execution references, archived
  definitions, market prices, portfolio cost basis, realized gain, and expense
  summaries remain correct.
- Bootstrap: repeated runs before and after reopen create no duplicate master
  data, `Asset Fees`, USD/SGD, asset defaults, or seed transactions; archived
  and user-modified definitions remain untouched.
- Atomicity: native rollback leaves no partial parent/child state; edit,
  treatment switching, duplicate, delete, and reopen retain one managed child
  per parent. Web snapshot rollback remains equivalent.
- Asset matrix: gold, IDX lot stock, lot-size-1 stock, cryptocurrency,
  inventory, USD, SGD, and historical odd-lot cleanup retain quantity, cost,
  valuation, fee, reference, and gain behavior after persistence.
- Lifecycle after reopen: integrity conflicts, archive/restore, linked edits,
  retired-seed sell-only closure, and non-mutating catalog filtering pass.

## Compatibility retained

- Transaction snapshot fallback without `assetDefinitionId`.
- Historical asset-name and symbol identity.
- Exact-ID retired `asset-stock-portfolio` handling.
- Legacy migration null/default behavior.

No compatibility path was removed because each remaining path is exercised by
historical persistence or domain tests.

## Final checks

- Focused D14A and regression tests: 47 passed.
- `flutter analyze`: no issues found.
- Full `flutter test`: 401 passed.
- `flutter build web`: successful, including the Wasm dry run.
- SQLite: version 10; no migration added.

## Remaining D14B scope

Windows and Android runtime smoke testing, signed artifacts/installers,
application version changes, release notes, onboarding, backup/restore,
PIN/biometric security, secure production quote proxy, public distribution,
and D14 final closure remain deferred.
