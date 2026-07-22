# Pilgrim Tracker Architecture Documentation

## 1. Purpose

This document defines the technical architecture rules for Pilgrim
Tracker.

Pilgrim Tracker is a local-first financial management system supporting:

-   Personal finance
-   Projects
-   Businesses
-   Income
-   Expenses
-   Transfers
-   Asset conversion
-   Quantity-based assets
-   Tithe tracking
-   Offline operation
-   Synchronization
-   Import/export

This file exists so future Codex sessions understand the existing
architecture and do not redesign completed decisions.

------------------------------------------------------------------------

# 2. Core Architecture Principles

## Local-first

The local database is the primary source of truth.

Rules:

1.  Save changes locally first.
2.  Never require internet for normal transactions.
3.  Queue changes for synchronization.
4.  Sync later when internet exists.

## Shared business logic

Android and Windows must share:

-   Database models
-   Financial calculations
-   Validation
-   Tithe engine
-   Asset engine
-   Import/export logic
-   Sync logic

Only presentation layers should differ.

------------------------------------------------------------------------

# 3. Technology Stack

## Frontend

Flutter

Targets:

-   Android
-   Windows

Future:

-   iOS
-   macOS
-   Linux
-   Web

## Database

SQLite + Drift ORM

Reasons:

-   Offline support
-   Reliable migrations
-   Strong querying

## State Management

Recommended:

Riverpod

## Routing

Recommended:

GoRouter

## Models

Recommended:

Freezed immutable models

------------------------------------------------------------------------

# 4. Project Structure

Recommended:

    lib/

    app/
    core/
    features/
    shared/

Feature folders:

    accounts
    assets
    books
    categories
    dashboard
    import_export
    projects
    recurring
    reports
    settings
    tithe
    transactions

Each feature should contain:

    data/
    domain/
    presentation/

------------------------------------------------------------------------

# 5. Database Architecture

Pilgrim Tracker must preserve financial dimensions.

Main entities:

-   Users
-   Devices
-   Books
-   Accounts
-   Projects
-   Business Units
-   Categories
-   Contacts
-   Transactions
-   Transaction Entries
-   Transaction Revisions
-   Assets
-   Tithe Rules
-   Tithe Obligations
-   Recurring Rules
-   Attachments
-   Import Batches
-   Sync Changes

------------------------------------------------------------------------

# 6. Project Tracking (IMPORTANT)

Projects are a required financial dimension.

Every transaction must support:

    project_id nullable

A transaction may exist without a project, but if linked it must
contribute to project reporting.

Example:

    Income
    Project: Client Website
    Amount: IDR 10,000,000

Project reports:

-   Income
-   Expenses
-   Profit
-   Cash flow
-   Asset usage
-   Tithe generated

Project table:

    projects

    id
    book_id
    name
    description
    status
    start_date
    end_date
    created_at
    updated_at
    deleted_at

------------------------------------------------------------------------

# 7. Transaction Architecture

Transaction types:

-   Income
-   Expense
-   Transfer
-   Asset Conversion
-   Asset Sale
-   Tithe Payment
-   Refund
-   Adjustment
-   Split Transaction

Transaction fields:

    id
    book_id
    project_id
    business_unit_id
    transaction_type
    transaction_date
    description
    amount
    currency
    account_from_id
    account_to_id
    category_id
    contact_id
    created_at
    updated_at
    deleted_at
    version
    device_id
    sync_status

------------------------------------------------------------------------

# 8. Double Entry Principle

Transactions generate ledger entries.

Example:

Income:

    Debit:
    Bank

    Credit:
    Income

Expense:

    Debit:
    Expense

    Credit:
    Cash

Transfer:

    Debit:
    Destination Account

    Credit:
    Source Account

Transfers do not affect profit.

------------------------------------------------------------------------

# 9. Asset Conversion

Asset conversion is NOT an expense.

Example:

    Cash:
    - IDR 50,000,000

    Gold:
    +20 grams

Result:

    Cash decreases
    Gold asset increases

Required fields:

    source_asset
    destination_asset

    source_amount
    destination_quantity

    source_unit
    destination_unit

    unit_price
    cost_basis

    fee_amount
    fee_treatment

Supported assets:

-   Gold
-   Silver
-   Stocks
-   Cryptocurrency
-   Property
-   Inventory
-   Equipment
-   Other measurable assets

------------------------------------------------------------------------

# 10. Tithe Architecture

Tithe is generated from eligible income.

Entities:

    tithe_rules
    tithe_obligations
    tithe_payments
    tithe_payment_allocations

Every eligible income stores:

    tithe_rate_snapshot
    tithe_due_amount

Changing the tithe percentage creates a new rule version.

Example:

    January 2026: 13%

    February 2026: 14%

Old income keeps 13%.

------------------------------------------------------------------------

# 11. Synchronization Architecture

Every synced entity requires:

    id
    version
    created_at
    updated_at
    deleted_at
    device_id
    sync_status

Sync states:

    LOCAL
    PENDING
    SYNCED
    CONFLICT
    FAILED

Never silently overwrite financial conflicts.

Manual conflict review required for:

-   Amount
-   Account
-   Date
-   Asset quantity
-   Cost basis
-   Tithe values

------------------------------------------------------------------------

# 12. Import and Export

Supported:

Import:

-   CSV
-   XLSX
-   JSON backup

Export:

-   CSV
-   XLSX
-   Full backup

Import metadata:

    import_batch_id
    source_file
    source_row
    fingerprint

------------------------------------------------------------------------

# 13. Desktop and Mobile Roles

## Desktop

Financial control center:

-   Spreadsheet transaction editing
-   Bulk editing
-   Reports
-   Import/export
-   Reconciliation

## Mobile

Fast capture:

-   Quick Add
-   Custom keypad
-   Duplicate last transaction
-   Receipt capture
-   Offline entry

------------------------------------------------------------------------

# 14. Codex Rules

Before coding, always read:

    docs/product_spec.md
    docs/roadmap.md
    docs/architecture.md
    docs/progress.md

Never remove these dimensions:

    Book
    Project
    Business Unit
    Account
    Category
    Contact
    Transaction
    Asset
    Tithe

When adding features:

1.  Update architecture.md.
2.  Create database migration.
3.  Update tests.
4.  Update progress.md.

------------------------------------------------------------------------

# 15. Current Important Correction

The project column must exist in the transaction database.

Required:

    transactions.project_id

This field is nullable.

Examples:

Personal food:

    project_id = NULL

Client project expense:

    project_id = website_project_id

Without this field, project profitability reports cannot work.

------------------------------------------------------------------------

# 16. Long-Term Vision

Pilgrim Tracker becomes a financial operating system supporting:

-   Personal finance
-   Business finance
-   Project accounting
-   Asset management
-   Tithe management
-   Receipt intelligence
-   Multi-device synchronization
