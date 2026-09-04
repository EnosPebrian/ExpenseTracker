# Data Health & Sync Diagnostics

BETA-08J adds a fast, read-only Health Check under **Data & Sync**. It is an
operational trust surface for local data and synchronization state, not a
developer console and not a repair workflow.

## Architecture and safety

```text
existing local stores / repositories
        ↓
LocalHealthCheckDataSource (read-only snapshot)
        ↓
HealthCheckService
        ↓
immutable HealthCheckReport
        ↓
HealthCheckController
        ↓
HealthCheckScreen
```

The screen never queries SQLite directly. Running or refreshing a check does
not synchronize, retry outbox work, resolve a conflict, derive an import ID,
repair a transfer, alter backup state, or modify financial data. Safe actions
only navigate to existing Import Inbox, Household/conflict, or Backup screens.
Diagnostic runs are not persisted.

## Status and stable codes

Individual checks use `healthy`, `info`, `warning`, or `error`. Overall status
is **Healthy** unless a warning requires **Attention needed** or a structural
error makes the result **Critical**. Informational pending imports do not
downgrade overall status. Cloud unavailability is a sync warning and never
turns otherwise healthy local finance into database corruption.

Every check has a stable support/test code, including
`database.schema_version`, `transactions.invalid_reference`,
`transactions.account_reconciliation`, `transfers.canonical_integrity`,
`inbox.deferred_identity`, `rules.reference_integrity`,
`sync.pending_outbox`, `sync.unresolved_conflicts`, and `backup.status`.

## Checks

- Database: readable local store and expected SQLite schema v25.
- Household: active book/session identity, active membership, and scope.
- Transactions: stable live IDs; account, category, project, member, and asset
  references; established transaction-type rules; current-month account
  reconciliation through `AccountBalanceCalculator`.
- Transfers: BETA-08F0 canonical linked-pair validation; legacy one-row
  transfers remain valid informational history.
- Import Inbox: G lifecycle, session/draft relationships, G1 nullable paired
  identity/account binding, completed included-draft identity, and safe source
  identity presence. Health Check never derives an ID.
- Rules/planning: active import-rule references and semantic uniqueness,
  monthly-budget structural references/keys, account ownership, and current
  tithe-policy resolution.
- Sync: local-only/cloud-linked state, locally known pending and failed work,
  unresolved conflicts, and last-known successful sync. No cloud request is
  made.
- Backup: support for encrypted format v4. The app does not persist reliable
  latest-backup history, so it truthfully says recent status is not tracked.

Archived account/category history is accepted where the financial model keeps
snapshot references valid. Deleted transactions follow normal lifecycle
exclusion. Broken canonical links, unresolved completed import identity, schema
mismatch, and invalid financial references are structural errors.

## Privacy-safe support summary

**Copy summary** includes only section status and issue/warning counts. It does
not include amounts, descriptions, account/card numbers, raw UUIDs, source
fingerprints, Telegram identifiers, authentication data, or secrets. BETA-08J
does not create diagnostic files or support bundles.

## Intended use

Run Health Check before and after BETA-08H1 hosted deployment and consolidated
owner acceptance. Compare local structural health separately from temporary
cloud status. Any critical result should be preserved and investigated; this
milestone intentionally provides no automatic repair.

SQLite remains v25, backup remains v4, and BETA-08J adds no Supabase/SQL
change.
