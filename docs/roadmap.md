# Pilgrim Tracker Development Roadmap

## 1. Roadmap Purpose

This roadmap converts the Pilgrim Tracker product specification into an implementation sequence suitable for Codex or a software development team.

The roadmap prioritizes:

- Reliable financial records
- Offline-first operation
- Android and Windows support
- Fast transaction entry
- Asset conversion
- Tithe tracking
- Import and export
- Safe synchronization
- Future receipt scanning

The application should be developed in small, testable milestones.

---

# 2. Target Platforms

## Initial platforms

- Android
- Windows desktop

## Future platforms

- iOS
- macOS
- Linux
- Web

The first release should share as much business logic and database logic as possible between Android and Windows.

---

# 3. Recommended Architecture

## Client

- Flutter
- Dart
- Drift with SQLite
- Riverpod or Bloc
- GoRouter
- Freezed or equivalent immutable models

## Backend

Recommended options:

- Supabase, or
- Custom backend using FastAPI, NestJS, or ASP.NET Core

Backend components:

- PostgreSQL
- Authentication
- Synchronization API
- Object storage for receipt images
- Backup storage
- Device management

## Core principles

- Local database is the immediate source of truth
- All writes succeed locally first
- Synchronization happens later
- Financial calculations use integer money values
- Every important transaction edit creates a revision
- Synchronized deletion uses tombstones

---

# 4. Delivery Strategy

Each phase should end with:

- Working application build
- Automated tests
- Database migration
- Acceptance checklist
- Updated documentation
- Version tag

Recommended versioning:

```text
0.1.0 Offline foundation
0.2.0 Core transactions
0.3.0 Tithe engine
0.4.0 Asset conversion
0.5.0 Desktop transaction manager
0.6.0 Import and export
0.7.0 Synchronization
0.8.0 Recurring transactions
0.9.0 Release candidate
1.0.0 First stable release
```

---

# 5. Phase 0 — Project Foundation

## Goal

Create a maintainable Flutter project that runs on Android and Windows.

## Tasks

1. Create the Flutter project.
2. Enable Android and Windows targets.
3. Define the folder structure.
4. Configure dependency injection.
5. Configure navigation.
6. Configure state management.
7. Add logging.
8. Add environment configuration.
9. Add code formatting and linting.
10. Configure unit and integration tests.
11. Configure Git.
12. Add continuous integration.
13. Create development, testing, and production configurations.

## Suggested folder structure

```text
lib/
  app/
  core/
    database/
    errors/
    logging/
    money/
    sync/
    utilities/
  features/
    accounts/
    assets/
    books/
    categories/
    dashboard/
    import_export/
    projects/
    recurring/
    reports/
    settings/
    tithe/
    transactions/
  shared/
```

## Deliverables

- Android application opens
- Windows application opens
- Shared navigation works
- Local SQLite database initializes
- Automated test command works
- Basic theme and application shell exist

## Acceptance criteria

- The same codebase builds successfully for Android and Windows.
- Database initialization does not lose data during restart.
- Development configuration is separated from production configuration.

---

# 6. Phase 1 — Local Database and Core Models

## Goal

Create the offline financial data foundation.

## Core entities

- User
- Device
- Book
- Book member
- Account
- Category
- Project
- Business unit
- Contact
- Transaction
- Transaction entry
- Transaction revision
- Tag
- Transaction tag
- Tithe rule
- Tithe obligation
- Tithe payment allocation
- Recurring rule
- Attachment
- Import batch
- Sync change
- Sync conflict
- Asset unit
- Asset price
- Asset lot

## Tasks

1. Design the Drift schema.
2. Use UUID or ULID primary keys.
3. Add created, updated, and deleted timestamps.
4. Add database versioning.
5. Add migrations.
6. Implement repository interfaces.
7. Implement local repositories.
8. Add transaction-safe database operations.
9. Add seed data for default categories.
10. Add backup-safe serialization.

## Money rules

- Store money as integer values.
- Store currency using ISO currency codes.
- Do not use floating-point values for financial amounts.
- Store percentages using decimal-safe representation.

## Deliverables

- Database schema
- Migration system
- CRUD repositories
- Test fixtures
- Database documentation

## Acceptance criteria

- Records survive application restart.
- A migration can upgrade an old database.
- Foreign key relationships are enforced.
- Soft-deleted records remain available for synchronization.

---

# 7. Phase 2 — Books, Accounts, Categories, and Projects

## Goal

Allow users to create financial workspaces and organize transactions.

## Tasks

1. Create and edit books.
2. Create and edit accounts.
3. Support account types:
   - Cash
   - Bank
   - E-wallet
   - Credit card
   - Receivable
   - Payable
   - Investment
   - Gold
   - Silver
   - Stock
   - Cryptocurrency
   - Property
   - Equipment
   - Inventory
   - Other asset
   - Liability
4. Create income and expense categories.
5. Create projects.
6. Create business units.
7. Create contacts.
8. Archive accounts and categories.
9. Prevent deletion of referenced entities.
10. Add account opening balances.

## Deliverables

- Book management screens
- Account management screens
- Category management screens
- Project management screens
- Local account balance calculations

## Acceptance criteria

- Users can maintain separate books for personal, project, and business finances.
- Archived entities remain visible in historical transactions.
- Account balances are calculated from ledger entries.

---

# 8. Phase 3 — Core Transactions and Double-Entry Ledger

## Goal

Implement reliable income, expense, and transfer transactions.

## Transaction types

- Income
- Expense
- Transfer
- Refund
- Balance adjustment
- Split transaction

## Tasks

1. Implement transaction domain models.
2. Implement double-entry ledger generation.
3. Implement income creation.
4. Implement expense creation.
5. Implement transfers.
6. Implement refunds.
7. Implement balance adjustments.
8. Implement split transactions.
9. Add transaction validation.
10. Add transaction search and filters.
11. Add soft deletion.
12. Add transaction restore.
13. Add revision history.
14. Add undo for recent edits.

## Financial rules

### Income

- Increases an asset account.
- Increases income reporting.

### Expense

- Decreases an asset account.
- Increases expense reporting.

### Transfer

- Decreases one account.
- Increases another account.
- Does not affect income.
- Does not affect expense.

## Deliverables

- Transaction service
- Ledger service
- Mobile transaction list
- Mobile transaction form
- Transaction detail screen
- Revision history screen

## Acceptance criteria

- Transfers do not affect profit.
- Split transactions always balance.
- Deleted transactions no longer affect balances.
- Restored transactions affect balances again.
- Every important edit creates a revision.

---

# 9. Phase 4 — Fast Mobile Transaction Entry

## Goal

Make daily transaction entry fast enough for one-handed phone use.

## Tasks

1. Build Quick Add screen.
2. Add Income, Expense, Transfer, and Asset Conversion tabs.
3. Add custom numeric keypad.
4. Add `00` and `000` keys.
5. Add expression parsing.
6. Support:
   - `125k`
   - `1.5m`
   - `25000 + 15000`
   - `25 * 6`
7. Add Duplicate Last.
8. Add Duplicate Without Amount.
9. Add recent accounts.
10. Add recent categories.
11. Add recent projects.
12. Add saved templates.
13. Add optional haptic feedback.
14. Add home-screen shortcuts later.

## Deliverables

- Quick Add screen
- Amount parser
- Duplicate transaction actions
- Recent transaction suggestions

## Acceptance criteria

- A common expense can be entered in a few taps.
- Duplicate Last never copies IDs, attachments, or sync metadata.
- The new transaction date defaults to today.
- The keypad works without internet.

---

# 10. Phase 5 — Tithe Tracking Engine

## Goal

Implement versioned tithe rules and obligation tracking.

## Core concepts

- Tithe rule
- Tithe obligation
- Tithe payment
- Tithe payment allocation
- Tithe credit or advance
- Voluntary additional giving

## Tasks

1. Create tithe rule management.
2. Support percentage and effective date.
3. Support eligible income categories.
4. Support gross or net basis.
5. Snapshot the applicable rate on income.
6. Generate obligation when eligible income is posted.
7. Allow partial tithe payments.
8. Allocate payments to:
   - Oldest obligation
   - Selected month
   - Selected income
   - Advance balance
9. Show monthly outstanding amounts.
10. Show overpayments.
11. Add rule history.
12. Recalculate when eligible income changes.
13. Detect date changes that cross rule boundaries.
14. Add confirmation before obligation recalculation.
15. Preserve recalculation history.

## Example rule history

```text
2026-01-01    13%
2026-02-01    14%
```

## Deliverables

- Tithe settings screen
- Tithe dashboard
- Obligation service
- Payment allocation service
- Monthly tithe report

## Acceptance criteria

- Historical income keeps its original rate snapshot.
- New income uses the rule effective on its transaction date.
- Partial payments remain visible as outstanding.
- Overpayments can become advance tithe.
- Changing eligible income updates the obligation only after confirmation.
- Asset conversion does not create a new tithe obligation.

---

# 11. Phase 6 — Asset Conversion and Quantity-Based Assets

## Goal

Support conversion between assets with different units.

## Main example

```text
Cash paid: IDR 50,000,000
Gold acquired: 20 grams
Average unit cost: IDR 2,500,000 per gram
```

## Tasks

1. Add quantity tracking to asset accounts.
2. Add unit definitions.
3. Add asset conversion transaction type.
4. Add source monetary amount.
5. Add destination quantity.
6. Add destination unit.
7. Add acquisition unit price.
8. Add total cost basis.
9. Add weighted-average cost calculation.
10. Support conversion fees.
11. Allow fee treatment:
    - Capitalized
    - Expensed
12. Add asset market prices.
13. Add current market valuation.
14. Calculate unrealized gain or loss.
15. Add partial asset sale.
16. Calculate removed cost basis.
17. Calculate realized gain or loss.
18. Preserve quantity and valuation history.
19. Add validation for negative quantities.
20. Prevent selling more than available quantity.

## Asset conversion rules

- Source asset decreases.
- Destination quantity increases.
- Destination cost basis increases.
- Conversion is not income.
- Conversion is not an ordinary expense.
- Fees may be capitalized or expensed.

## Asset sale example

```text
Gold sold: 5 grams
Cash received: IDR 15,000,000
Removed cost basis: IDR 12,500,000
Realized gain: IDR 2,500,000
Remaining gold: 15 grams
```

## Deliverables

- Asset conversion form
- Asset account detail screen
- Quantity and cost-basis service
- Market valuation service
- Asset sale form
- Realized and unrealized gain reports

## Acceptance criteria

- IDR 50,000,000 can be converted into 20 grams of gold.
- Cash decreases by IDR 50,000,000.
- Gold quantity increases by 20 grams.
- Cost basis becomes IDR 50,000,000.
- Average cost becomes IDR 2,500,000 per gram.
- Asset conversion does not affect ordinary income or expense.
- Partial sale updates quantity and cost basis correctly.
- Realized gain or loss is calculated correctly.

---

# 12. Phase 7 — Windows Desktop Transaction Manager

## Goal

Create a high-speed desktop workspace for editing and reviewing transactions.

## Tasks

1. Build spreadsheet-like transaction table.
2. Add inline cell editing.
3. Add double-click editing.
4. Add keyboard navigation.
5. Add column sorting.
6. Add filters.
7. Add saved views.
8. Add column visibility settings.
9. Add column reordering.
10. Add multi-row selection.
11. Add bulk editing.
12. Add copy and paste.
13. Add Excel clipboard paste.
14. Add transaction detail panel.
15. Add drag-and-drop receipt attachment.
16. Add undo and redo.
17. Add conflict indicators.
18. Add sync status indicators.

## Keyboard shortcuts

```text
Ctrl + N          New transaction
Ctrl + D          Duplicate selected transaction
Ctrl + Shift + D  Duplicate without amount
Ctrl + S          Save
Ctrl + Z          Undo
Ctrl + Y          Redo
Ctrl + F          Search
Enter             Edit selected cell
Esc               Cancel editing
Delete            Move to trash
Alt + 1           Income
Alt + 2           Expense
Alt + 3           Transfer
Alt + 4           Asset conversion
```

## Deliverables

- Desktop transaction grid
- Bulk-edit dialog
- Keyboard shortcut system
- Saved table layouts

## Acceptance criteria

- Transactions can be created and edited using only the keyboard.
- Copy-pasted rows are validated before saving.
- Bulk amount changes require confirmation.
- Desktop edits create transaction revisions.

---

# 13. Phase 8 — Reports and Dashboards

## Goal

Provide reliable personal, project, business, tithe, and asset reporting.

## Reports

- Income and expense summary
- Cash flow
- Account balances
- Project profit
- Business unit profit
- Category breakdown
- Tithe obligations
- Tithe payments
- Outstanding tithe
- Asset allocation
- Asset quantities
- Historical cost basis
- Current market value
- Unrealized gains and losses
- Realized gains and losses

## Tasks

1. Build dashboard summaries.
2. Add monthly and custom date ranges.
3. Add filters by book, project, account, category, and business unit.
4. Add drill-down to transactions.
5. Add asset allocation reporting.
6. Add tithe reporting.
7. Add export-ready report data.
8. Add report caching where appropriate.

## Deliverables

- Mobile dashboard
- Desktop dashboard
- Report screens
- Drill-down navigation

## Acceptance criteria

- Reports work offline.
- Reports update immediately after a local transaction.
- Transfers are excluded from income and expense totals.
- Asset conversions are excluded from ordinary income and expenses.
- Realized and unrealized gains are shown separately.

---

# 14. Phase 9 — Import, Export, Backup, and Restore

## Goal

Make data easy to move, inspect, and recover.

## Import formats

- CSV
- XLSX
- JSON backup
- Clipboard data from Excel

## Export formats

- CSV
- XLSX
- JSON backup
- ZIP backup with attachments

## Tasks

1. Implement CSV export.
2. Implement XLSX export.
3. Implement full JSON backup.
4. Implement ZIP backup.
5. Implement restore preview.
6. Implement merge or replace mode.
7. Add CSV import.
8. Add XLSX import.
9. Add column mapping.
10. Add validation preview.
11. Add duplicate detection.
12. Add import batches.
13. Add full batch rollback.
14. Add backup version checking.
15. Add restore logs.

## Deliverables

- Import wizard
- Export screen
- Backup creation
- Restore workflow
- Import report

## Acceptance criteria

- CSV and XLSX open correctly in spreadsheet software.
- Full backup preserves all relationships.
- A clean installation can restore the backup.
- Invalid import rows are reported.
- Imported batches can be rolled back.

---

# 15. Phase 10 — Offline Synchronization

## Goal

Synchronize Android and Windows without sacrificing offline operation.

## Tasks

1. Add authentication.
2. Add device registration.
3. Create server schema.
4. Create synchronization API.
5. Add local sync queue.
6. Push local changes.
7. Pull remote changes.
8. Add record versioning.
9. Add tombstones.
10. Add retry logic.
11. Add exponential backoff.
12. Add sync status.
13. Add sync center.
14. Add conflict detection.
15. Add conflict resolution interface.
16. Add attachment synchronization.
17. Add background synchronization.
18. Add manual synchronization.
19. Add last-sync timestamps.
20. Add server-side audit logs.

## Automatic merge candidates

- Notes
- Description
- Tags

## Manual conflict fields

- Amount
- Date
- Currency
- Account
- Asset quantity
- Unit price
- Cost basis
- Tithe rate
- Tithe amount
- Deleted versus edited state

## Deliverables

- Synchronization API
- Local sync engine
- Conflict center
- Device management
- Attachment synchronization

## Acceptance criteria

- Transactions created offline synchronize later.
- Phone changes appear on desktop.
- Desktop changes appear on phone.
- Conflicting amount changes are not silently overwritten.
- Deleted synchronized records remain represented by tombstones.

---

# 16. Phase 11 — Recurring Transactions

## Goal

Automate predictable transactions.

## Tasks

1. Create recurring templates.
2. Support daily recurrence.
3. Support weekly recurrence.
4. Support monthly recurrence.
5. Support yearly recurrence.
6. Support every N days, weeks, or months.
7. Support start and end dates.
8. Support maximum occurrences.
9. Support automatic creation.
10. Support draft creation.
11. Support reminder-only mode.
12. Prevent duplicate generated instances.
13. Add upcoming transaction dashboard.

## Deliverables

- Recurring rule editor
- Recurring transaction processor
- Upcoming transactions screen
- Reminder integration

## Acceptance criteria

- A recurring rule generates only one transaction per occurrence.
- Generated transactions can be edited independently.
- Tithe obligations remain income-triggered rather than calendar-triggered.

---

# 17. Phase 12 — Receipt and Bill Scanning

## Goal

Generate draft transactions from receipt or bill images.

## Tasks

1. Add camera capture.
2. Add gallery selection.
3. Add crop and perspective correction.
4. Add OCR.
5. Extract merchant.
6. Extract date and time.
7. Extract subtotal.
8. Extract tax.
9. Extract discount.
10. Extract total.
11. Extract currency.
12. Extract payment method.
13. Extract receipt number.
14. Extract line items.
15. Add confidence scores.
16. Create draft transaction.
17. Require user confirmation.
18. Store receipt attachment.
19. Synchronize attachment later.
20. Add merchant and category suggestions.

## Deliverables

- Receipt scanner
- OCR parser
- Draft transaction review
- Receipt attachment viewer

## Acceptance criteria

- OCR never automatically posts uncertain transactions.
- Extracted fields show confidence.
- The user can correct every extracted value.
- Receipt scanning can create a draft while offline when the OCR engine supports it.

---

# 18. Phase 13 — Security and Reliability

## Goal

Protect financial information and reduce data-loss risk.

## Tasks

1. Add PIN lock.
2. Add biometric lock.
3. Add secure token storage.
4. Encrypt network traffic.
5. Encrypt cloud backups.
6. Add optional local database encryption.
7. Add automatic backup reminders.
8. Add backup verification.
9. Add restore tests.
10. Add session management.
11. Add device list.
12. Add remote sign-out.
13. Add audit history.
14. Add attachment retention controls.
15. Add database integrity checks.

## Deliverables

- Security settings
- Device management
- Backup verification report
- Audit log

## Acceptance criteria

- Authentication tokens are not stored in plain preferences.
- Backups can be verified before deletion of old copies.
- Users can revoke access for lost devices.

---

# 19. Phase 14 — Release Preparation

## Goal

Prepare Pilgrim Tracker for stable use.

## Tasks

1. Complete accessibility review.
2. Complete localization preparation.
3. Test Android phones with different screen sizes.
4. Test Windows display scaling.
5. Test offline behavior.
6. Test unstable-network behavior.
7. Test large transaction databases.
8. Test import files with errors.
9. Test backup and restore.
10. Test cross-device conflicts.
11. Test asset conversion calculations.
12. Test tithe rate changes.
13. Complete privacy documentation.
14. Complete user documentation.
15. Add crash reporting with privacy controls.
16. Conduct beta testing.
17. Fix release-blocking bugs.
18. Publish release notes.

## Deliverables

- Android release build
- Windows release build
- User guide
- Privacy policy
- Release notes
- Database backup guide

## Acceptance criteria

- No known data-loss defects.
- Backup and restore have been tested on clean installations.
- Offline-created transactions synchronize after reconnection.
- Tithe and asset-conversion calculations pass automated tests.
- The first stable version is tagged `1.0.0`.

---

# 20. Testing Roadmap

## Unit tests

Cover:

- Money arithmetic
- Transfer balancing
- Split transaction balancing
- Tithe rule selection
- Tithe snapshot calculation
- Tithe payment allocation
- Weighted-average asset cost
- Partial asset sale
- Realized gain or loss
- Import duplicate fingerprinting
- Sync conflict detection

## Database tests

Cover:

- Migrations
- Soft deletion
- Revision history
- Transaction rollback
- Import batch rollback
- Sync queue persistence

## Widget tests

Cover:

- Quick Add form
- Custom keypad
- Tithe dashboard
- Asset conversion form
- Desktop transaction table
- Conflict resolution screen

## Integration tests

Cover:

- Android offline transaction creation
- Windows offline transaction editing
- Synchronization after reconnection
- Backup and restore
- CSV and XLSX import
- Receipt draft creation

---

# 21. Recommended First Codex Prompt

```text
Read product_spec.md and roadmap.md completely before changing code.

Create the initial Flutter project for Pilgrim Tracker with Android and Windows support.

Use:
- Flutter
- Dart
- Drift with SQLite
- Riverpod
- GoRouter
- Freezed where useful

Implement only Phase 0 and Phase 1 from roadmap.md.

Requirements:
- Use a feature-first folder structure.
- Use UUID or ULID identifiers.
- Store money as integers.
- Add created_at, updated_at, deleted_at, version, device_id, and sync_status to synchronized records.
- Add database migrations.
- Add repository interfaces and local repository implementations.
- Add unit tests for money storage and database persistence.
- Do not implement cloud synchronization yet.
- Do not implement receipt OCR yet.
- Document all setup and commands in README.md.

After implementation:
1. Run formatting.
2. Run static analysis.
3. Run tests.
4. Report files created.
5. Report any unresolved issues.
```

---

# 22. Definition of the First Stable Release

Pilgrim Tracker 1.0 should provide:

- Android application
- Windows desktop application
- Offline-first local database
- Books
- Accounts
- Categories
- Projects
- Business units
- Income
- Expenses
- Transfers
- Split transactions
- Asset conversion
- Quantity-based asset accounts
- Weighted-average cost basis
- Partial asset sale
- Realized and unrealized gains
- Tithe rules
- Tithe obligations
- Tithe payments
- Fast mobile entry
- Desktop spreadsheet-like editing
- Transaction revision history
- Recurring transactions
- CSV and XLSX import and export
- Full backup and restore
- Cross-device synchronization
- Conflict resolution
- Security settings

Receipt scanning may be included after version 1.0 if it would delay stability of the financial core.
