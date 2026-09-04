# Deferred Import Identity

## Decision

Draft identity is not final financial identity.

`ImportReviewDraft.id` is the durable review-workflow identity. It never changes
when an account is selected, rules are rerun, duplicates are reclassified, or a
transfer is reconsidered. The session source fingerprint plus the canonical
source-row key and row fingerprint are the durable source identity.

The nullable `deterministic_transaction_id` is the final financial transaction
identity. Destination account is part of that identity. Therefore unresolved
pending drafts do not receive a final financial ID until account selection.
No provisional UUID, draft-ID substitution, placeholder account, or second ID
algorithm is allowed.

## Canonical derivation

BETA-08G1 extracts, but does not change, the BETA-08B UUIDv5 algorithm:

```text
namespace = c76551e2-47f7-5a64-8d32-9423217b95b1
name = household | destination account | source fingerprint |
       source-row key | source-row fingerprint
```

Account-known-first and account-selected-later paths produce the same UUID.
`deterministic_transaction_account_id` records which account produced a stored
final ID. Both fields are null while unresolved and both are non-null when
resolved.

## Lifecycle and safety

- Pending unresolved sessions and drafts persist, synchronize, and reopen
  without inventing an account or transaction.
- Selecting an account derives the final ID and reruns rules, duplicate checks,
  and transfer matching.
- Changing the account before commit invalidates the prior analysis and derives
  the new canonical ID without changing draft or source identity.
- Commit is blocked while account/final identity is unresolved or the binding
  does not match the effective account.
- Completed financial IDs are immutable. Existing BETA-08G reconciliation uses
  the finalized ID after a crash and cannot create a duplicate.
- Excluded drafts may complete with both final-ID fields null.
- A sync conflict blocks commit. The final ID and its account binding are
  resolved as linked state rather than independent UUID fields.

## Migration compatibility

SQLite v25 rebuilds only `import_review_drafts`. Every v24 row and lifecycle,
provenance, sync, and source-fingerprint value is retained. Existing final IDs
are retained byte-for-byte. Their account binding is backfilled only from the
v24 session destination-account invariant; migration fails atomically if that
account cannot be proven.

The newly explicit `source_row_key` is recoverable for canonical CSV rows and
receipt/invoice rows. Legacy bank-statement drafts retain their already-derived
ID, but cannot be moved to a different account if the original extractor row
key was not persisted; reimporting the source is the safe fallback.

Backup remains v4 because uncommitted Import Inbox workflow state remains
excluded from backup.

## BETA-08H

BETA-08H correctly stopped at this identity safety gate. It may resume only
after BETA-08G1 engineering verification. BETA-08G1 contains no Telegram table,
pairing, webhook, bot API, Edge Function, or UI implementation at its own
checkpoint.

BETA-08H consumes this completed contract: Telegram persists source identity
but intentionally leaves account, deterministic transaction ID, and identity
binding null. The TypeScript gateway does not derive financial UUIDs. Once the
user selects an account, the existing Dart BETA-08B/G1 UUIDv5 implementation
produces the same identity as an account-known-first import.
