# CSV Unknown-Category Resolution

## Review contract

Pilgrim never guesses or silently creates a category for an unknown non-empty
CSV value. Exact matching normalizes surrounding whitespace, letter case, and
repeated whitespace, and only accepts one compatible active category in the
current household. Fuzzy matching is intentionally unsupported.

An unknown source value remains a reviewable draft and blocks final import
until the user explicitly chooses one action:

- **Map to existing** applies one compatible current category.
- **Create category** records a creation intent; it does not create a category
  during review.
- **Ignore category** imports the row without category identity or a category
  name.

One resolution applies to rows with the same normalized source category and
transaction type. A manual row category edit has higher precedence and is not
overwritten by later source-category changes.

This resolution contract applies to CSV source-category review. Existing
legacy/source-neutral assignments and row-level manual assignments remain valid
without an `ImportRuleCategory` record; their established downstream category
validation remains authoritative. A user-confirmed **Map to existing** choice is
recorded as explicit map intent with its stable Category ID and is revalidated
against that exact target immediately before commit.

## Deferred creation and atomic commit

Create intent stores the requested display name and a planned local UUID in the
existing Import Inbox draft metadata. Repeated rows share one intent. The UUID
is not a persisted Category identity until commit succeeds.

Final import revalidates mappings, groups creation intents, reuses an exact
category that appeared since review, and writes new categories, imported
transactions, confirmed transfer links, and their ordinary outbox operations
in one local transaction. Any failure rolls back the entire group. Cancelling,
discarding, or saving for later creates no Category row.

The final transaction UUID remains the existing BETA-08B UUIDv5 value; category
resolution never changes it. Reimporting the same source into the same account
therefore remains idempotent.

## System Tithe and transfers

`Tithe` variants resolve only to the deterministic protected System Tithe
identity when compatible. A same-name custom category is preserved and is not
silently repurposed; Create cannot make another ordinary Tithe.

Confirmed canonical transfers remain transfer-authoritative. Their imported
leg uses the Transfer snapshot with null category identity, regardless of the
CSV source category.

## Persistence, sync, and backup

Unresolved, map, create, and ignore choices round-trip through the existing
Import Review Inbox without retaining source bytes. A linked offline commit
creates the same Category/Transaction/Transfer outbox entries as ordinary local
mutations; reconnect and initial bootstrap use the unchanged sync protocol.

Committed categories and transactions are already covered by encrypted backup
v6. Pending Import Inbox workflow remains excluded, so no backup-format change
is required. SQLite remains v27 and no Supabase migration is added.
