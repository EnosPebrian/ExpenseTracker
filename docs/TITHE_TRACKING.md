# Tithe Tracking

BETA-08L separates an obligation from its payment:

- **Tithe Due** is calculated only by the existing `TithePolicy`.
- **Tithe Paid** is the sum of live ordinary expense transactions whose
  `category_id` exactly equals `UUIDv5(book_id, "system-category:tithe")`.
- **Balance** is cumulative Due minus cumulative Paid. Positive values are
  Outstanding; negative values are Advance / Credit.

Names are not identity. A custom category named `Tithe` remains ordinary and
does not count as Paid. Legacy transactions with only a Tithe text snapshot do
not count. Deleted transactions, invalid records, non-expenses, opening balance
effects, and canonical transfer legs are excluded under existing lifecycle
rules.

## System category

Every initialized household has one deterministic live expense category named
`Tithe`. Bootstrap ensures it idempotently through local category persistence;
linked households use the normal outbox and BETA-08K synchronization. Repeated
ensure creates neither another row nor another outbox operation. A malformed
canonical row is reported as an integrity error and is never replaced by a
second category. Client mutation policy and the deployed BETA-08L0A server
guard reject rename, type change, archive, delete, household move, or identity
replacement. Custom same-name categories are unaffected.

## Payments and periods

**Record Tithe Payment** reuses ordinary transaction creation with Expense and
the exact System Tithe category locked for that dedicated entry. Account,
amount, date, and supported notes remain normal transaction fields. The
payment reduces its account and household cash flow once. It is not stored in
a separate ledger and is not added again to expense totals.

Payment date determines the Paid period. Month and year-to-date summaries are
shown with a cumulative balance that carries prior underpayment or advance.
Editing amount/date/category or deleting/restoring the transaction naturally
recomputes the derived summary. Recent payments navigate to ordinary
transaction detail/edit.

The household Tithe page follows the existing base-currency reporting model
and filters out accounts in other currencies; no implicit FX conversion or
cross-currency addition occurs. Statements calculate their Tithe section per
currency while retaining the ordinary payment in expenses exactly once.

## Portability and diagnostics

Backup stays v5: categories and transactions already contain all required
state. Exact restore preserves the canonical identity. Clone and narrowly
supported cross-household System-Tithe recovery remap the source household's
canonical category to the destination household's canonical ID atomically.
Other cross-household recovery remains blocked.

Health Check is read-only. It reports
`system_category_tithe_missing` or `system_category_tithe_invalid`; a custom
same-name category is not corruption and Health Check performs no repair.
