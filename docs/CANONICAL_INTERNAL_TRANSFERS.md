# Canonical Internal Transfers

## BETA-08F0 decision

New internal transfers are represented by two independently addressable
transaction legs plus one explicit directional `transfer_links` record. The
outgoing expense leg belongs to the source account, the incoming income leg
belongs to the destination account, and the relation retains both stable
transaction IDs. The relation itself has a stable UUID.

The existing generic transaction relation fields are intentionally not reused:
they describe parent/fee relationships and cannot encode two directional legs
without overloading ambiguous fields. `transfer_links` is therefore the
smallest explicit entity that preserves direction and import identity.

## Invariants

An active link requires live expense/outgoing and income/incoming legs in the
same household, different live accounts, equal positive integer amounts, and
the same account/link currency. A transaction may belong to only one active
pair. Domain validation, atomic repository writes, native/web remote apply,
initial download validation, backup integrity checks, Supabase triggers, and
partial unique indexes protect these invariants.

## Lifecycle

- Create writes outgoing leg, incoming leg, relation, and their ordinary
  outbox operations atomically. New writes never use the legacy one-row model.
- Convert links two existing opposite-direction rows without changing either
  transaction ID and can enforce the caller-observed row versions.
- Edit presents one transfer and updates both legs plus the relation atomically,
  retaining all three IDs and rejecting stale versions.
- Unpair tombstones only the relation. Both legs remain and immediately regain
  ordinary expense/income and category behavior.
- Delete tombstones the relation and both legs atomically. It is distinct from
  Unpair and follows the normal synchronized tombstone lifecycle.

## Financial behavior

Account balances continue to apply the outgoing negative and incoming positive
effects. An active link excludes both legs from household income, expense,
cash-flow, category budget, and tithe-eligible income classification. Household
net worth is unchanged. Once unpaired, the two rows are ordinary expense and
income again.

## Local-first and portable data

`transfer_links` uses the existing outbox, cursor push/pull, conflict, Realtime
wake-up, and initial synchronization architecture—there is no transfer RPC.
Remote applies do not echo. The local validator exposes a pair only after both
legs and their accounts are valid. Per-entity conflicts involving a transfer
are classified for explicit review; silent financial merge is prohibited and
integrity validation runs after resolution.

Encrypted backup format v4 adds `transfer_links`. Formats v1-v3 remain readable
and never fabricate links. Replacement restore validates legs before applying
the snapshot atomically. Selective recovery orders safe missing legs before the
relation and blocks changed dependencies or authoritative tombstones. Clone
restore remaps link, book, transaction, and account references together. CSV
exports both legs with shared `transfer_link_id` and explicit direction, plus a
`transfer_links.csv` structural table.

## Legacy policy

Legacy transfers remain one transaction with `type=transfer`, a Transfer
category, and display-only route text such as `Source -> Destination`. They are
readable, excluded from reporting under existing rules, backup/sync compatible,
and are never automatically paired or rewritten. Their text cannot prove two
account identities, so automatic migration would be unsafe.

## BETA-08F1 reviewed matching

The deterministic BETA-08F1 matcher now proposes draft-to-existing,
existing-to-existing, and draft-to-draft candidates without mutating data.
Only same-household, different-account, same-currency, exact-amount,
opposite-direction ordinary entries within two local calendar days qualify.
Ambiguous candidates require manual counterpart selection, and every conversion
requires confirmation. Confirmed pairs reuse this canonical representation;
candidate and rejection state remain transient.
