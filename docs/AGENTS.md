# Pilgrim Tracker — Codex Project Instructions

## Project

- Path: `D:\ExpenseTracker`
- Framework: Flutter / Dart
- Primary shell: Windows CMD
- Product: local-first personal finance and asset-management application

## Usage Efficiency

Codex usage is limited.

- Inspect only files relevant to the requested milestone.
- Do not reread the full documentation bundle unless explicitly required.
- Use targeted `rg` searches before opening files.
- Do not paste complete source files or long logs in reports.
- Do not create `.bak` files; use Git diff.
- Do not perform unrelated cleanup.
- Prefer extending existing architecture over parallel implementations.
- Run focused tests during implementation.
- Run `flutter analyze` once after implementation.
- Run the full test suite only once at the end.
- Run expensive runtime checks only when relevant.
- Keep final reports concise.

## Architecture

Preserve the existing feature-first, local-first architecture.

- Presentation coordinates rendering and user interaction.
- Controllers manage state, validation, and use-case coordination.
- Domain services contain financial calculations and reusable business rules.
- Repository contracts remain in the domain layer.
- Data implementations handle SQLite, HTTP, and platform storage.
- `AppShell` is a composition root, not a business-logic container.

Never put:

- HTTP parsing in widgets
- SQL in controllers
- portfolio or accounting mathematics in widgets
- provider-specific parsing in domain entities
- money in `double`
- unrelated feature logic in `AppShell`

## Financial Guardrails

- Money is stored as integers.
- Measurable asset quantities may use the existing `double` model.
- Transfers are not income or expenses.
- Asset conversions are not ordinary income or expenses.
- Unrealized gains are not cash income.
- Market prices never rewrite historical cost basis.
- Transaction snapshots must remain preserved.
- New asset transactions must use concrete asset definitions.
- Prefer `assetDefinitionId`; retain legacy snapshot fallback.
- Different concrete assets must never be silently merged.
- IDR and foreign-currency values must never be silently mixed.
- Invalid online quotes must never replace valid cached prices.
- Manual prices must remain usable offline.

## Scope Discipline

Implement only the milestone requested in the current prompt.

Do not introduce unless explicitly requested:

- Drift
- Riverpod
- GoRouter
- synchronization
- price-history infrastructure
- broad database redesign
- general ledger migration
- unrelated UI redesign
- speculative abstractions

Do not silently modify unrelated behavior.

## File Maintainability

Do not make oversized files materially worse.

- Inspect the size and responsibilities of every production file being changed.
- Prefer small cohesive extractions when adding substantial new responsibility.
- Do not split files merely to satisfy an arbitrary line limit.
- Reuse existing widgets, helpers, and formatters.
- Keep screens focused on composition.
- Keep controllers focused on state and coordination.
- Keep calculations in pure domain services.
- Do not turn a feature milestone into a project-wide refactor.

## Database Changes

A persistence change requires:

- schema version increment
- fresh-install schema update
- migration path
- preservation of existing rows
- native/web method parity where applicable
- migration and round-trip tests
- documentation update

Do not increment the database version for behavior that fits the existing schema.

## Verification

During development:

```bat
flutter test <focused tests>
```

After implementation:

```bat
dart format <changed Dart files>
flutter test <focused tests>
flutter analyze
flutter test
```

Run the full test suite only once unless production code changes after the final run.

Run `flutter build web` or runtime smoke tests only when required by the milestone.

Never report a command as successful unless it was actually run.

## Completion Report

Keep the final report concise and include:

1. files changed
2. behavior implemented
3. architecture decisions
4. tests added
5. analyzer result
6. final full-test count
7. build or runtime result
8. SQLite version and migration status
9. remaining limitations

Do not paste full source files or extensive test logs.
