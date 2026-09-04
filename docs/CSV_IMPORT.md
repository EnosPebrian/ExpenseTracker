# CSV Transaction Import

Transactions → Import now offers CSV, Receipt / invoice photo, and Bank
statement PDF / images. All three sources converge on the normalized draft,
duplicate review, atomic commit, and ordinary sync pipeline described here;
CSV parsing and mapping behavior is unchanged. See `RECEIPT_IMPORT.md` and
`BANK_STATEMENT_IMPORT.md` for their source-specific extraction rules.

CSV import is transaction data entry. It does not restore a backup, replace a
household, change synchronization cursors, or import lifecycle metadata.

## Entry point and limits

Open **Transactions → Import CSV** on Windows or Android. Android uses the
scoped document picker and requests no broad storage permission. Files must be
UTF-8 `.csv` files of at most 10 MB and 5,000 data rows. Comma and semicolon
delimiters, UTF-8 BOM, CRLF/LF, quoted fields, escaped quotes, embedded
delimiters, and blank lines are supported. Malformed quoting, invalid UTF-8,
overlong fields, more than 100 columns, and over-limit files are rejected
without mutation.

## Pilgrim canonical CSV

Required headers are `date`, `description`, `amount`, and `type`. Optional
headers are `category`, `reference`, and `note`.

```csv
date,description,amount,type,category,reference,note
2026-08-01,Supermarket,250000,expense,Groceries,REF001,Weekly groceries
2026-08-02,Salary,12500000,income,Salary,PAY0826,August salary
```

`type` is `income` or `expense`; transfers are not supported. The selected
destination account supplies account ownership and currency. Reference and
note are review metadata in v1 because the current transaction schema has no
separate reference/note columns.

## External bank mapping

The mapping screen supports either a signed amount column with an explicit sign
convention, or separate debit and credit columns. Exactly one debit/credit value
must be greater than zero. Extra columns are ignored. The first row can be
treated as headers or data.

Date choices are `yyyy-MM-dd`, `dd/MM/yyyy`, `MM/dd/yyyy`, `dd-MM-yyyy`,
`yyyy/MM/dd`, `dd MMM yyyy`, and `dd MMMM yyyy`. Automatic recognition accepts
only unambiguous year-first dates. Dates remain local calendar dates.

Decimal and thousands separators are selected explicitly. Parsing produces
integer minor units without floating-point authority. Ambiguous punctuation,
invalid grouping, zero, NaN/infinity, and impossible precision are blocked.
Currency symbols are stripped only when explicitly enabled.

## Identity, duplicates, and review

The exact source bytes receive a SHA-256 fingerprint. Each row gets a stable
source fingerprint and an RFC UUIDv5 transaction ID derived from household,
destination account, file fingerprint, source row, and row fingerprint. Draft
edits do not change that identity. Re-importing the same file into the same
account therefore classifies rows as already imported and creates no outbox
work.

The shared BETA-08A duplicate detector additionally classifies semantic and
possible duplicates. Possible deleted matches remain excluded by default.
Category mapping uses one exact normalized compatible active-category match;
it never creates or fuzzily guesses categories.

Review happens before mutation. Rows can be edited, selected for compatible
bulk category assignment, included, or excluded. Already-imported, invalid,
and possible-deleted rows cannot be enabled. Semantic and possible duplicates
remain excluded by default but may be included only through an explicit review
choice. Draft edits rerun validation and duplicate classification without
changing source identity. Unconfirmed drafts are not saved across app restarts.

## Reviewed internal-transfer conversion

After duplicate detection and category-rule suggestions, safe new drafts are
matched against eligible stored transactions. Confirmation atomically writes
the deterministic imported ID and canonical link. Already-imported and blocked
duplicate rows never enter matching.

## Commit and synchronization

Confirmed rows use normal validation and one SQLite transaction. Every new row
and its ordinary outbox operation commits together; any failure rolls the whole
batch back. There is no import-history table, CSV cloud endpoint, Supabase SQL,
cursor reset, or reconnect flow.

Local-only import works offline. A cloud-linked offline device may continue
with a visible warning that duplicate analysis used current local data. New
rows then follow normal local-first outbox synchronization. Online analysis
attempts the ordinary sync refresh first.

The completion screen reports imported, already present, duplicate, excluded,
income, and expense totals. Its current-session transaction filter is not
persisted after restart. Projects and exchange-rate inference are intentionally
outside BETA-08B.

Future receipt, invoice, bank-statement image/PDF, and Telegram sources must
produce the same normalized draft/review/atomic-commit pipeline.

## BETA-08E rules

An exact valid canonical CSV category outranks a deterministic rule. Rows with
no category may receive a household rule suggestion in review. Provenance is
shown, manual selection wins, and clearing it re-evaluates the rule. Matching
does not alter source fingerprint, row identity, or deterministic transaction
ID, so repeated-import idempotency is unchanged.

## Save for later

After mapping and analysis, a CSV review may be saved to Import Inbox. Pilgrim
persists the fingerprint, row identities, normalized
drafts, inclusion, warnings, and edits—not CSV bytes. Leaving an uncommitted
review offers Save to inbox or Discard. Resume uses the shared editor and
recalculates rules, duplicates, and transfers before atomic import.

For account-known CSV imports, deterministic final IDs are still derived
immediately. BETA-08G1 additionally permits an inbox draft to exist before
account selection. Its final ID remains null until the destination account is
known, then the exact same BETA-08B UUIDv5 algorithm is used. Draft identity is
not final financial identity.

Telegram accepts only the canonical Pilgrim header set and retains UTF-8/BOM,
quoted-field, escaped-quote, 5,000-row, 100-column, 10 MB, exact-money, and field
limits. Noncanonical files are directed to the in-app mapper. Telegram drafts
keep the direct parser's source row number/key and row-fingerprint semantics,
but defer account-dependent identity to G1.
