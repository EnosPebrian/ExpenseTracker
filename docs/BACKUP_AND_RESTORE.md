# Household Backup and Restore

Pilgrim Tracker treats synchronization, backup, and CSV export as separate
tools. Synchronization converges authorized devices. An encrypted `.ptbackup`
captures one recoverable household snapshot. CSV is a readable interchange
export and is not a full backup.

## Portable format

Format version 1 is an encrypted envelope containing an authenticated
AES-256-GCM ciphertext. After decryption, the payload is a ZIP with:

```text
manifest.json
household.json
members.json
accounts.json
categories.json
projects.json
transactions.json
asset_definitions.json
manual_market_prices.json
checksums.json
```

The manifest records the application and SQLite schema versions independently,
export time, household identity/currency, entity and deleted-state counts,
content checksum, encryption metadata, and calculated accounting totals.
Per-file SHA-256 checksums and an aggregate checksum protect the logical
contents in addition to authenticated encryption.

The password is never stored or logged. PBKDF2-HMAC-SHA256 with 210,000
iterations derives a 256-bit key from a fresh 16-byte random salt. AES-256-GCM
uses a fresh 12-byte nonce. Pilgrim Tracker cannot recover a forgotten backup
password. Future format versions are rejected before local data changes.

## Snapshot and scope

Native backup reads books, members, accounts, categories, projects,
transactions, asset definitions, and manual prices in one SQLite read
transaction. It includes soft-deleted rows needed for integrity but excludes
authentication data, remote-link state, device/session state, outbox records,
sync cursors, API keys, and technical errors. Export does not mutate data or
create outbox work. Desktop creation opens a Save As dialog in the remembered
folder, validates the returned `.ptbackup` name, writes a flushed temporary
file, and renames it only after generation succeeds. A collision receives a
safe numeric suffix instead of overwriting an existing backup. Mobile/web use
their scoped platform document/download transaction.

## Restore policy

Restore validates the password, authenticated ciphertext, checksums, format,
scope, IDs, references, values, counts, lifecycle totals, and accounting
summary before activation.

- **Restore as new** is the default. Original IDs are retained if there is no
  local collision. A matching household ID is rejected unless the user
  explicitly requests an independently remapped copy. Histories are never
  merged.
- **Replace matching household** is advanced recovery. The backup ID must be
  the active household ID, the exact household name must be entered, and a new
  encrypted pre-restore safety backup must be saved first. SQLite replacement
  and session activation are one transaction; a failure preserves the old
  household.

Restored records become `local_only`, use a restore-local device marker, and do
not inherit authentication or cloud-ready state. No restore import creates
outbox operations. Verify the restored household locally, then deliberately
relink and reconcile cloud state before synchronization.

Web uses equivalent validation and collection snapshot rollback, but its
in-memory store remains a development preview and is not durable after reload.

## Historical category snapshots

Transactions store the category name captured at entry time, not a category
UUID foreign key. If that definition is later absent, backup reports a
recoverable warning and requires confirmation while preserving the transaction
and snapshot text. Soft-deleted definitions remain in the full snapshot.
Cross-household records remain fatal. Save and restore names are independently
validated as `.ptbackup`; picker filters alone are not trusted.
