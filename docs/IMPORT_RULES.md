# Deterministic transaction import rules

BETA-08E adds household-scoped `TransactionImportRule` configuration for CSV,
receipt/invoice, and bank-statement drafts. Rules suggest a category during
review; they never create transactions, change saved transactions, or learn in
the background. Manual transaction entry is outside this milestone.

## Matching contract

Rules target exactly one transaction type (`expense` or `income`) and match one
source-neutral field: description, reference, optional merchant hint, or
description-or-reference. Operators are case-insensitive `contains`, `equals`,
and `startsWith`. Matching trims outer whitespace and collapses repeated
whitespace without changing stored draft text, removing digits, or executing
patterns as SQL, regex, or script. Patterns require at least three meaningful
characters and are limited to 160 characters. `pattern_key` stores the
normalized comparison value.

A rule may apply to any account or one active account in the same household.
Its category must be in the same household and compatible with the transaction
type. Deleted accounts and unavailable/deleted categories remain historically
readable but cannot produce an active suggestion.

Enabled rules are evaluated by descending integer priority. Equal highest
priority matches for one category are safe; equal highest priority matches for
different categories are reported as ambiguous and produce no automatic
category. Stable rule ID provides deterministic display ordering, never an
arbitrary category tie-break.

## Review precedence and identity

Category authority is:

1. the user's current manual selection;
2. an exact, valid category supplied by the source;
3. an unambiguous deterministic rule suggestion;
4. unresolved.

The review screen names the provenance and matching rule. Clearing a manual
selection re-evaluates the draft. Editing description, reference, type, or
account also re-evaluates rules without overriding a remaining manual choice.
Rule evaluation never changes a source fingerprint, source-row identity, or
deterministic transaction ID.

`Create rule` from review opens an editable confirmation dialog. It proposes
the full merchant hint when present, otherwise the full description. Nothing is
saved until confirmation, and saving the transaction never edits a rule.

## Persistence, synchronization, and conflicts

SQLite schema 22 stores `transaction_import_rules` with stable UUID identity,
soft deletion, lifecycle/version fields, household/category/account references,
and an active semantic uniqueness key. Native and web stores enforce equivalent
validation. A local mutation and its ordinary outbox operation commit
atomically for linked sync-ready households; remote application never echoes a
new mutation. Local-only households use the same engine without cloud access.

Supabase uses the existing initial upload/download, push/pull, cursor,
`app_changes`, manifest, conflict, and RLS protocol. Rules cannot move between
households, and remote category/account references are validated. Conflicts use
Keep shared, Keep this device, or explicit manual merge. Identity and lifecycle
fields cannot be manually merged, and delete-versus-update remains explicit.

## Backup and recovery

Encrypted portable backup format v3 includes
`transaction_import_rules.json`, its count, and checksum. V1 has neither
budgets nor rules; v2 has budgets but no rules; v3 has both. Restoring or
recovering v1/v2 never interprets the missing rules section as deletion.
V3 integrity validation checks household, enums, pattern, lifecycle, category,
account, and semantic uniqueness references.

Selective recovery classifies rule identity like other synchronized entities.
Safe missing rules can be recovered through current mutation/outbox semantics;
conflicts, remote tombstones, invalid references, and foreign-household records
remain blocked. Create-new-household cloning assigns the new book identity,
remaps rule/category/account IDs, and discards stale sync metadata.

Rules are configuration protected by encrypted backup, not financial/reporting
rows, so normal CSV export intentionally excludes them.

## Deferred

No regex, fuzzy matching, AI categorization, automatic pattern creation,
retroactive recategorization, or manual-entry suggestions are included.

BETA-08F1 transfer matching runs after rule suggestion and duplicate safety. A
confirmed canonical transfer overrides ordinary report/budget/tithe category
classification without editing the rule. If kept ordinary, the suggested or
manually selected category behaves normally.

## Pending-import reevaluation

Opening an Import Inbox session evaluates current enabled rules again only for
drafts without a valid manual or explicit-source category. Precedence remains
manual > valid source > deterministic rule > unresolved. Persisted category ID
and provenance prevent name-based remapping; an unavailable manual/source
category blocks import until the user selects a current category.
