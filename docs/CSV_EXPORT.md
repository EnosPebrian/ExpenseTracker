# CSV Export

The Backup & Export screen creates a ZIP for the active household containing:

```text
household.csv
members.csv
accounts.csv
categories.csv
projects.csv
transactions.csv
asset_definitions.csv
budgets.csv
asset_activity.csv
summary.csv
README.txt
```

CSV v1 uses stable English headers, comma delimiters, RFC-compatible quoting,
escaped embedded quotes, ISO-8601 UTC dates, and UTF-8 with a BOM for reliable
Excel detection. Money remains exact integer minor-unit text. Asset quantities
use non-scientific decimal text with at most eight decimal places.

`transactions.csv` includes transaction/book identity, date/type/description,
exact amount, currency, resolved account/category/project/member identity and
names, related transaction and fee fields, asset identity/quantity/unit price,
lifecycle timestamps, and version. `asset_activity.csv` provides the measured
asset subset. `summary.csv` summarizes the selected active transactions.

`budgets.csv` uses stable English columns for budget/book/month/category
identity and resolved category name, exact limit value and display text,
currency, note, lifecycle timestamps, and version. Rows are deterministically
ordered and household-scoped. `summary.csv` additionally includes selected
active budget count and total limit without changing existing financial totals.

User text whose first non-space character is `=`, `+`, `-`, or `@` is prefixed
with an apostrophe so spreadsheet applications do not execute it as a formula.

Filters cover date range, type, account, category, project, member attribution,
and deleted records. Defaults are all dates and non-deleted records in the
active household. Filters never affect encrypted full backups. CSV is readable
portability output, not a recoverable application backup.

An absent current category definition is a recoverable export warning. After
confirmation, the transaction remains in `transactions.csv`, its historical
category text remains in `category_name`, and `category_id` is blank because
legacy transaction rows do not store that UUID. ZIP destinations are validated
to end in `.zip` on every platform. Desktop export opens a Save As dialog in
the remembered folder; Android uses the scoped system document picker and does
not request broad storage permission.
# Relationship to CSV import

CSV export remains a reporting/export feature, not backup. Its transaction
columns may be mapped by the BETA-08B importer, but import never trusts exported
UUIDs, versions, deletion state, device IDs, or synchronization metadata. Only
the importer-generated deterministic source identity is authoritative.

# Canonical transfer context

For backup v4 snapshots, `transactions.csv` retains both accounting legs and
adds their shared `transfer_link_id` plus `outgoing`/`incoming` direction.
`transfer_links.csv` exports the durable structural relation. This prevents the
two rows from masquerading as unrelated household expense and income while
preserving existing transaction-export conventions.
