Continue Pilgrim Tracker cleanup after Transaction feature migration.

Read:

- docs/product_spec.md
- docs/roadmap.md
- docs/architecture.md
- docs/progress.md

Transactions feature migration is complete.

Before moving to other features, remove remaining transaction compatibility code.

Tasks:

1. Search for:

- old searchable picker implementations
- duplicate dropdown logic
- transaction widgets still living outside features/transactions
- temporary compatibility exports

2. Replace remaining transaction-related dropdown usage with:

lib/core/shared/widgets/searchable_dropdown.dart

3. Ensure only one reusable searchable dropdown implementation exists.

4. Ensure AppShell contains only:

- app shell
- routing
- dependency setup

It should not contain:

- transaction UI
- transaction forms
- transaction business logic

5. Run:

flutter analyze

flutter test

6. Update docs/progress.md.

Report:

- Removed compatibility code
- Remaining legacy code
- Current transaction architecture status
