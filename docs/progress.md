# Pilgrim Tracker Progress

## Current milestone

- Flutter app shell runs on web, Android, and Windows targets.
- Premium dashboard, transactions, accounts, projects, tithe, reports, and asset conversion screens exist.
- Quick Add supports expense, income, and transfer entry with controller-supplied defaults while keeping date/time/project out of the compact fast-entry surface.
- Quick Add now uses the compact prototype-style centered modal: type tabs, amount, account, category, description, and one primary save action.
- Asset conversion supports source/destination assets, quantity, unit cost, fee treatment, and optional date/time.
- Local-first transaction storage is implemented with versioned SQLite on Android/Windows and a browser preview fallback.
- Transaction records include UUIDs, project IDs, soft deletion, version, device ID, and sync status.
- Default expense categories, income categories, projects, and financial accounts are seeded from the approved user lists.
- Categories, projects, and accounts have add/edit management interfaces and feed directly into Quick Add.
- Existing transactions can be edited from their detail dialog and are saved back to the same UUID record with a new version.
- Asset conversion supports both buying measured assets with cash and selling gold, stocks, Bitcoin, or inventory back to cash/bank accounts.

## Architecture alignment work completed

- Completed Phase 1 shell extraction: `lib/main.dart` is now a bootstrap entrypoint and the application shell lives in `lib/app/app.dart`.
- Added `lib/app/theme/app_theme.dart` and a transitional `lib/app/router.dart` route registry.
- Existing SQLite code remains isolated in `lib/core/database/`.
- Transaction Phase 1 extraction completed: the transaction entity/model now lives in `lib/features/transactions/domain/entities/transaction.dart`.
- Added `TransactionRepository` domain contract and `LocalTransactionRepository` SQLite adapter under `lib/features/transactions/`.
- Existing app-shell transaction UI remains behaviorally compatible through a `TxType` typedef during the incremental move.
- Added transaction application use cases for create, update, soft delete, get, and duplicate operations.
- AppShell creation, loading, and editing now delegate through repository-backed transaction use cases instead of direct SQLite calls.
- Added focused unit tests for transaction creation, update versioning, duplication metadata, and soft deletion.
- Added `TransactionController` with loading/error state and CRUD/duplicate commands.
- Added a transitional `TransactionProviders` dependency factory for future Riverpod migration.
- AppShell now observes the controller and routes transaction create/update operations through it.
- Extracted the transaction list and detail presentation surface into `lib/features/transactions/presentation/`.
- Added reusable `TransactionFilters`, `TransactionTile`, and `TransactionCard` widgets plus `TransactionListScreen` and `TransactionDetailScreen`.
- AppShell now routes the Transactions page through `TransactionListScreen`; the feature screen observes `TransactionController` and keeps edit/delete callbacks at the shell boundary.
- Extracted Quick Add into `presentation/quick_add/` with a `QuickAddController`, configurable default context chips, and controller-backed persistence.
- Extracted Edit Transaction into `presentation/edit/` with reusable form fields, project editing, date/time editing, transfer and asset-conversion fields.
- New transaction and edit forms reuse the shared searchable picker and preserve the existing keyboard-first selection behavior.
- Transaction domain copying now supports explicitly clearing nullable `project_id`; edit presentation no longer carries UUID, version, or sync metadata manually.

- Added nullable `transactions.project_id`.
- Added SQLite schema migration from version 1 to version 2.
- Added an optional project selector to Quick Add.
- Preserved local-first writes before future synchronization.
- Added database migration version 3 with dedicated `books`, `accounts`, `categories`, and `projects` tables, including soft-delete and synchronization metadata.
- Wired master-data seed loading and account/category/project additions and renames to local persistence.

## Known architecture follow-ups

- Replace the transitional SQLite repository with Drift ORM.
- Introduce Riverpod state management and GoRouter navigation.
- Move the current presentation code into feature-first `data/`, `domain/`, and `presentation/` folders.
- Add business units, contacts, ledger entries, revisions, tithe entities, and sync queues as separate tables.
- Replace the dashboard's compatibility `RecentTransactions`/legacy tile with `TransactionCard` when the dashboard is extracted.
- Remove the temporary searchable-picker compatibility declarations from `app.dart` after all legacy master-data screens use the shared widget directly.
- Extract transaction presentation controllers/providers into the final app state-management solution after the Riverpod migration.
