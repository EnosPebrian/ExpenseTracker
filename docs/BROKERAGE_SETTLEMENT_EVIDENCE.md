# Brokerage settlement evidence

Accepted owner/Lead Architect decision: 2026-09-15.

BUY_SETTLEMENT and SELL_SETTLEMENT are reconciliation evidence, not transactions.
They have zero independent effect on brokerage cash, quantity, cost basis,
realized/unrealized P&L, household income/expense, budgets, net worth and Tithe.
Corresponding BUY/SELL trade events remain the sole financial authority.

Evidence preserves source statement date, positive amount, currency, settlement
direction, statement fingerprint, row identity/fingerprint, reference and note.
An unmatched row is valid evidence and can be imported without inventing a trade.
Reconciled evidence references an explicitly reviewed set of authoritative trade
IDs. One evidence row may reference multiple trades, and a trade may be referenced
by multiple evidence rows. References never mutate trade identity or values.

Candidate suggestions are not reconciliation confirmation. Ambiguous candidates
must remain reviewable. Household, brokerage account, currency and BUY/SELL
direction must agree. No guessed allocations or automatic financial adjustments.

Interest is a separate real brokerage activity, not a dividend alias. Deposit and
withdrawal remain canonical cash transfers; dividend, fee and tax are unchanged.

Implementation and automated engineering verification: PASS; implementation
8ac408b pushed to origin/main. Owner acceptance:
NOT RUN. Hosted deployment: NOT AUTHORIZED by this work item.

Implementation uses `brokerage_settlements` separate from transactions. Its ID
reuses the existing brokerage statement event UUIDv5 calculation. Reviewed trade
IDs form a sorted unique JSON set, permitting many-to-many references; state is
derived as unmatched for an empty set and reconciled otherwise. Reconciliation
updates require the expected local version and no unresolved evidence conflict.
Conflicts use existing whole-record selection, never independent UUID merging.
Source columns are immutable; confirming unchanged links is a no-op.

SQLite 29 adds one table without modifying financial rows. Backup v8 includes
evidence; versions 1–7 remain readable with an empty evidence section. Clone
remaps evidence/account/trade IDs and retains source provenance. Selective
recovery includes account/trade dependencies. Health Check validates links
read-only; unmatched evidence is valid. The one new Supabase migration remains
undeployed and must be rolled out before this client’s evidence sync is used.

Open Import brokerage statement → Settlement evidence to review persisted rows.
The review dialog offers all compatible trades and labels seven-day candidates;
amount/reference agreement only ranks suggestions. No suggestion is preselected
unless already reviewed. Users may select several trades or leave none selected.

Unavailable historical links are never silently dropped: the user must explicitly
confirm their removal or cancel. Interest remains unimplemented in this repair.

Validation: focused Flutter 33/33; full Flutter 1010/1010; analyzer clean;
Web, Windows debug, Android debug builds passed. Local clean replay passed,
pgTAP 12/12 focused and 326/326 full. Local advisor has no errors; two unchanged
legacy search-path warnings remain. Hosted deployment and owner acceptance
have not been performed.
