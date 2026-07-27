# BETA-02 Complete — Household, Members, Books, and Sync-Ready Local Architecture

**Completed:** 2026-07-26

## Verdict

BETA-02 is complete. Pilgrim Tracker now has an authoritative local financial
book, local household members, account ownership, transaction entry
attribution, per-book persistence scope, and an explicit future sync design.
It does not yet provide authentication, invitations, synchronization, or
multi-device sharing.

## Delivered behavior

- Existing installations migrate into one financial book without changing
  financial amounts, transaction history, asset snapshots, or accounting.
- The current local profile becomes the first owner member; first launch creates
  the same profile/book/owner sequence idempotently.
- Active book and member persist in the local session.
- Accounts can be joint or member-owned and filtered by owner.
- New normal, Quick Add, duplicated, linked-fee, and asset-conversion records
  receive the active book/member context.
- Applicable native and web records are scoped by active book, with independent
  per-book master-data seeds.
- Household Settings supports household rename, local member add/rename, roles,
  and active-member selection.

## Persistence

- SQLite schema: **version 12**.
- Version 11 upgrades add/upgrade books, create household members, add session
  references, account owner, transaction attribution, and applicable book IDs.
- Legacy null scopes are backfilled to the migrated book.
- Migration, idempotence, close/reopen, ownership, attribution round trip,
  two-book isolation, referenced-member blocking, and web parity are tested.

## Files and architecture

New production files:

- `lib/features/master_data/domain/entities/financial_book.dart`
- `lib/features/master_data/domain/entities/household_member.dart`
- `lib/features/master_data/presentation/screens/household_settings_page.dart`
- `lib/core/database/household_schema_native.dart`

The v12 schema/migration responsibility was extracted from the already-large
native store. Existing repository and controller paths were extended rather
than duplicated. Financial calculations remain unchanged.

## Verification

- Focused BETA-02/accounting tests: **20 passed**.
- Full Flutter suite: **442 passed**.
- `flutter analyze`: **No issues found**.
- `flutter build web`: **successful**; Wasm dry run also succeeded.
- SQLite migration/reopen: **passed**.

## Remaining limitations

- Members are local people, not authenticated users.
- No Supabase, invitations, Row Level Security, network sync, outbox, conflicts,
  tombstone exchange, backup/restore, or two-device acceptance exists yet.
- Web storage remains an in-memory development preview.
- D14 remains open until BETA-05 and the outstanding signing/runtime gates.

## Next milestone

BETA-03 may implement Supabase PostgreSQL/Auth, user-to-book membership,
household invitations, and Row Level Security. Realtime must not become the
source of truth; offline synchronization remains BETA-04.
