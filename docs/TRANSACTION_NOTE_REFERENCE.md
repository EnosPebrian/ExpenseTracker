# Transaction Note and Reference

## Domain semantics

`Transaction.note` and `Transaction.reference` are nullable user-owned
metadata. They are not sync identifiers, import identities, or financial
dimensions.

- `null` means no value.
- A whitespace-only user value normalizes to null.
- Reference trims leading and trailing whitespace, preserves case and
  punctuation, and is limited to 256 characters.
- A non-empty note preserves internal whitespace, commas, quotes, newlines, and
  Unicode, and is limited to 4,000 characters.
- Values over the limit are rejected; they are never truncated.

The metadata does not participate in BETA-08B UUIDv5 transaction identity,
duplicate identity, amount/account/category behavior, or reporting totals.

## Persistence and import

SQLite schema 27 adds nullable transaction columns. Existing rows migrate with
null metadata and unchanged financial and synchronization state. The in-memory
web store follows the same entity semantics. Full transaction entry/edit can
set, edit, and clear both fields. Existing CSV and shared Import Review
finalization now retain metadata already present or manually edited in drafts;
receipt, statement, Inbox, and eventual Telegram paths use that same commit
pipeline without inventing values.

## Synchronization compatibility

Modern transaction payloads contain both keys, including explicit null when a
user clears a value. On an existing row:

- property absent: preserve the current value;
- property present with null: clear the value;
- property present with a valid string: set the value.

An older-client create that omits both fields stores null. Initial sync,
incremental sync, conflict application, and new-device bootstrap retain this
presence distinction without creating an echo outbox operation.

## Backup and future CSV

Encrypted backup v6 stores both fields. v1–v5 remain readable and restore null
because the fields did not exist. Exact restore, clone, and selective recovery
preserve current metadata. Backup cryptography is unchanged.

Human-editable Portable CSV v1 is deliberately not part of BETA-08M0. It
remains future BETA-08M work built on this durable foundation.
