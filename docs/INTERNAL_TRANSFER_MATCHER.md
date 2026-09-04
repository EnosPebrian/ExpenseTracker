# Internal Transfer Matcher

## Scope

BETA-08F1 adds a deterministic, source-neutral review layer over the BETA-08F0 canonical linked-pair transfer model. Candidates are transient: there is no matcher table, sync entity, backup payload, AI call, or persistent rejection history.

## Eligibility

A pair is eligible only when both records are live ordinary expense/income entries in the same household, use different active accounts, have the same currency and exact positive integer minor-unit amount, have opposite directions, are no more than two local calendar days apart, and are not already in an active canonical transfer. Legacy one-row transfers, asset conversions, deleted rows, same-account movements, unequal amounts, split transfers, and cross-currency movements are excluded.

## Ranking and ambiguity

Hard constraints are applied before ranking. Candidate buckets are indexed by currency, amount, opposite direction, and local date. Ranking is deterministic and explainable: same date, matching reference, counterpart account-name hint, transfer-keyword evidence, then one- or two-day distance. Stable ID provides display ordering only. Equal-quality leaders are `ambiguous` and never silently selected.

The centralized support keywords are `TRANSFER`, `TRF`, `XFER`, `TRANSFER TO`, `TRANSFER FROM`, `TRANSFER KE`, `TRANSFER DARI`, and `PEMINDAHAN`. Text is normalized only in matching copies; stored descriptions and source fingerprints remain unchanged.

## Supported modes

- Draft to existing: import review can confirm a deterministic draft ID against a stored counterpart.
- Existing to existing: Transactions → Review possible transfers scans the current month by default, with previous-month and custom ranges.
- Draft to draft: the canonical service can atomically save both deterministic draft IDs plus one deterministic link; the matcher abstraction supports different-account draft pools without redesigning single-account CSV import.

## Confirmation and atomicity

Nothing changes until explicit confirmation. Draft-to-existing saves the draft and link in one database transaction. Draft-to-draft saves both drafts and link in one transaction. Existing-to-existing uses the BETA-08F0 conversion operation. Expected transaction versions are rechecked inside the write transaction; stale candidates fail with “This transfer candidate changed. Review again.” A pair never partially persists.

Import duplicate classification runs before matching. `alreadyImported`, invalid, possible-deleted, and excluded duplicate rows cannot use matching to bypass duplicate safety. Import rules may suggest a category, but canonical transfer classification wins only after explicit confirmation; the rule and deterministic source identity are unchanged.

## Financial and synchronization behavior

Confirmed links retain the original -X/+X account movement while excluding both legs from household income/expense, outgoing budget spend, and incoming tithe derivation. Unpair restores ordinary classifications. Matcher state never syncs; only normal transaction and `transfer_links` outbox mutations use the existing local-first pipeline. Local-only and offline linked households use current device data.

## Limitations

No FX, unequal-amount/fee inference, split matching, automatic confirmation, or lifetime automatic scans are included. Bulk existing conversion uses pair-level atomicity and reports results per pair.

## Persistent import reviews

BETA-08G persists normalized import drafts, but never treats a saved transfer
candidate or rejection as authoritative. Resume reruns the BETA-08F1 matcher
against current unpaired household transactions. New counterparts may appear;
stale, changed, deleted, or newly paired counterparts disappear. Confirmation
still occurs only in the shared review UI and creates the canonical pair at
explicit commit.
