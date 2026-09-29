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
Clipboard/bulk/undo are the separately authorized BETA-09B2 sprint.
Owner desktop/Android acceptance remains PENDING / NOT RUN.
