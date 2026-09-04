# Household Backup and Restore

Pilgrim Tracker treats synchronization, backup, and CSV export as separate
tools. Synchronization converges authorized devices. An encrypted `.ptbackup`
captures one recoverable household snapshot. CSV is a readable interchange
export and is not a full backup.

## Portable format

Format version 3 is current. It retains the format-1 container and cryptography,
retains v2 budgets, and adds `transaction_import_rules.json`, rule counts, and
checksum coverage. Versions 1 and 2 remain readable and restorable; a legacy
preview explains which configuration sections are unavailable. Version 1 has
no budgets or rules; version 2 has budgets but no rules. Its preview states: “This
backup was created before monthly budgets were supported.” Restore as new has
no budgets, while matching-household replacement preserves existing budgets
instead of treating their omission as deletion.

The encrypted envelope contains an authenticated
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
budgets.json
transaction_import_rules.json
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

For a cloud-linked household, encrypted backup is a disaster-recovery,
archival, offline-recovery, and catastrophic cloud/account-recovery tool. A
normal second or replacement device should sign in and bootstrap the existing
household from the shared cloud state. Local-only households have no shared
cloud copy, so backup remains essential for device-loss recovery. Changes with
a positive sync pending count are not yet present in the cloud copy and cannot
be recovered from another device.

Pilgrim does not upload or restore a SQLite `.db` file as its normal sync
mechanism.

Native backup reads books, members, accounts, categories, projects,
transactions, asset definitions, monthly budgets, and manual prices in one SQLite read
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

For that relink, BETA-07C1 never uploads or heuristically merges the restored
copy. The user chooses an active hosted membership and must save a new encrypted
pre-reconnect safety backup. The hosted snapshot is authoritative. A matching
ID is replaced atomically after validation; a different ID is downloaded as an
additional household and activated only after success. Cancellation or failure
leaves the original local-only household usable.

Version-2 budget rows are validated against their household, expense category,
month, base currency, uniqueness, lifecycle, IDs, and versions. Categories are
restored before budgets. Replacement classifies budgets with other entities;
activation stays atomic and creates no outbox operations.

Web uses equivalent validation and collection snapshot rollback, but its
in-memory store remains a development preview and is not durable after reload.

## Historical category snapshots

Transactions store the category name captured at entry time, not a category
UUID foreign key. If that definition is later absent, backup reports a
recoverable warning and requires confirmation while preserving the transaction
and snapshot text. Soft-deleted definitions remain in the full snapshot.
Cross-household records remain fatal. Save and restore names are independently
validated as `.ptbackup`; picker filters alone are not trusted.

## Recover from backup is not restore

`Recover from backup` compares a same-book v1/v2 backup with the current local
book and, when linked, a mandatory read-only hosted snapshot. It adds only
selected missing records and safe dependencies. It never replaces the book,
clears linkage/cursor/readiness, reconnects, deletes current-only rows,
overwrites changed identities, or resurrects hosted tombstones. Recovered rows
preserve stable business IDs but receive current mutation metadata and ordinary
linked outbox operations. See `BACKUP_RECOVERY.md`.

## Restore lifecycle after activation

The Backup & Export UI labels full replacement as **Restore entire backup** and
**Advanced / Disaster recovery**. After activation it starts local-only and
offers Keep local only, Reconnect existing shared household, and Create new
shared household. New sharing clones the restored snapshot to a fresh book and
entity identity set before using normal owner linking and initial upload. The
original restored household remains intact. See `RESTORE_LIFECYCLE.md`.

V3 rule restore validates household, enum, pattern, category, account, and
lifecycle integrity. V1/v2 replacement preserves current rules because absence
means unsupported, not deletion. V3 create-new-household cloning remaps rule,
book, category, and optional account identity and does not transplant stale
sync metadata. The backup encryption and password derivation are unchanged.

## V4 canonical transfer structure

Backup format v4 adds `transfer_links` and validates both referenced legs and
accounts before atomic replacement. Encryption and password derivation are
unchanged. V1-v3 remain readable; absence of the section means the older format
did not support canonical pairing and no relation is fabricated. Clone restore
remaps the relation and all book/transaction/account references together.

## Import Inbox exclusion

Pending and completed Import Inbox workflow records are intentionally excluded
from encrypted backup v4, Restore, and Recover missing records. They are
uncommitted/reconciliation workflow state, not committed household finances.
Linked inboxes synchronize separately; local-only inboxes persist on that
device but are not portable disaster-recovery data. Source files are never
retained. The backup format and cryptography are unchanged.
