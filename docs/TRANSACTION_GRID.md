# Transaction grid editing boundary — BETA-09B1

The wide Transactions screen is a virtualized view over the existing
TransactionController. Narrow screens retain the card/list UI. There is no
second ledger, SQL in presentation, or new persistence schema.

Fixed header, horizontal scrolling, resizable/sortable columns and virtualized
44-pixel rows support thousands of records. Search/date filters retain existing
semantics. Click selects; Enter/double-click edits; Escape cancels; Tab and
Shift+Tab move between fields; arrows navigate outside editing.

Inline editing is restricted to ordinary, unlinked income/expense records.
Transfers, brokerage/asset events, managed children, fees and System Tithe route
to the existing coordinated editor. Category/project names must resolve to
existing stable catalog IDs. Account changes require one active household
account and unchanged currency. Amounts are explicitly integer account storage
units; the grid does not convert currencies or introduce decimal accounting.

All prepared edits pass existing transaction validation and then the existing
controller/update use case/repository path. Pending saves prevent repeated
submission; failed input remains in its selected cell with an error. Changes
detected while a cell is being edited require cancellation/reopening.

Per-transaction outbox/conflict diagnostics are read-only native/web queries.
Pending, Failed and Conflict override row acknowledgement status. Synced is
shown only for acknowledged rows without outstanding operations; local-only
records remain labelled Local only. Conflict opens the existing 09A resolver.

SQLite 29 and backup v8 unchanged. No SQL migration or hosted change.
Column hiding/reordering/preferences are optional and not implemented.
## BETA-09B2 reviewed editing

Shift-click or Shift-arrows select a visible rectangle. Copy/Ctrl+C produces
quoted tab-separated text suitable for spreadsheets, preserving embedded tabs,
newlines and quotes. Formula-like text is prefixed with an apostrophe so copy
does not become spreadsheet code. Clipboard parsing is bounded to 1,000,000
UTF-16 code units (the UI labels this approximately 1 MB) and 5,000
rows and rejects malformed quoting or nonrectangular input.

Paste/Ctrl+V starts at the selected cell, or must match a selected multi-row
rectangle. Every cell is parsed and validated before Apply is available.
Read-only/protected columns block the entire plan; nothing is silently skipped.
Set selected rows supports existing category/account/project and replacement
note/reference values; blank clears optional project/note/reference only.
Current transaction versions and catalog identities are rechecked before saves.

The existing batch repository is an insert/import authority, not a validated
atomic multi-row update coordinator. Therefore review explicitly states that
rows save individually through TransactionController. First failure stops later
rows; the result lists each saved, failed/uncertain, and unattempted row.
An error after local persistence is not described as rollback: users inspect
current data before retry. This is not an all-or-nothing bulk-update promise.

Undo/Ctrl+Z is limited to the most recent successful single-cell description,
date, amount, note or reference edit in the active screen. It checks the saved
version/timestamp and creates a new ordinary validated mutation. It refuses
intervening changes. Catalog reassignment and bulk undo are deferred: catalog
lifecycle and partially completed multi-row updates require separate review,
not snapshot/history rollback. Switching screens clears transient undo state.

Text/date filters remain on the screen; the grid adds type, category, account,
project and sync/conflict filters. Filters and layout never write financial
records. Copy uses visible order; hidden rows are never silently edited.
Owner desktop/Android acceptance remains PENDING / NOT RUN.
