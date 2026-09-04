# Bank Statement PDF / Image Import

BETA-08D extends the secure BETA-08C gateway with
`document_type=bank_statement`. Sources are one unlocked PDF, or an ordered set
of JPEG/PNG/supported WebP page images (maximum 50 pages and 25 MB total).
Password handling is deliberately absent; export an unlocked copy instead.

The strict transient result contains institution, account-holder hint, last
four account hint only, currency, statement period, opening/closing balances,
page counts, document warnings, and transaction rows. Each row contains source
position, transaction/posting dates, substantially source-faithful description,
amount, debit/credit direction, optional reference/running balance, confidence,
and warnings. The extractor excludes headers, opening/closing balances,
subtotals, carry-forward, and other summary rows.

The user always confirms one Pilgrim destination account. A bank/account hint
never maps it automatically and no full account number is persisted. Debit is
normalized to expense and credit/refund to income. Posting date is used only
when transaction date is absent and is flagged for review. Transfers, loans,
assets, tithe, projects, and categories are never inferred.

## Identity, overlap, and reconciliation

One PDF uses SHA-256 of its original bytes. An image set uses a deterministic
length-framed hash in page order, so reordering pages changes the source.
Stable row identity combines the source hash, normalized source row data and
duplicate occurrence; the existing planner adds household and destination
account to UUIDv5 identity. Whitespace is normalized, and review edits preserve
the source identity.

The same statement/account produces already-imported rows and zero new
mutations. Different exports and overlapping periods are additionally checked
by the existing deterministic semantic duplicate detector; overlaps are
excluded by default. Deleted matches retain the existing tombstone-safe policy.

Opening plus credits minus debits is compared with closing balance using exact
integer minor units. Results are reconciled, mismatch, or insufficient
information. Extracted running balances are checked where present. A mismatch
is prominent review evidence but does not override the user's row review.

All rows enter the BETA-08B shared edit/include/exclude/category review and one
atomic commit. They become ordinary transactions and ordinary outbox entries;
there is no statement table, sync protocol, reconnect, or source retention.

## Deterministic category suggestion

Statement description and reference fields pass through the same BETA-08E rule
engine as CSV and receipts. The extractor is never asked to classify Pilgrim
categories. Rules only prefill an identified suggestion in review and cannot
change statement fingerprint or deterministic transaction identity.

## Internal-transfer review

Statement drafts use the shared deterministic matcher after reconciliation,
duplicate detection, and rule suggestions. Sequential statements from two
accounts can match a new draft to a stored opposite leg without another AI
call, while statement and transaction identities remain unchanged.

## Save for later

Statement drafts and minimal institution/period/currency/reconciliation summary
may be saved to Import Inbox. PDF/image bytes and provider payloads are never
persisted. Restart or a secondary device reconstructs review from normalized
rows, then reruns reference validation, rules, duplicates, and transfer matching
against current household state before explicit commit.

Telegram unlocked PDFs default to this bank-statement contract; one image with
exact `/statement` caption also uses it. V1 does not reconstruct media groups,
so multi-page image statements must be sent as one PDF or imported directly.
No account is inferred from bank, filename, masked-number, or caption hints.
