# Brokerage Statement CSV Import

## Scope

BETA-08N1 imports UTF-8 broker-export CSV files into the existing BETA-08N0
investment ledger. It does not introduce a second accounting engine. Every
accepted row becomes the same authoritative `Transaction`, `AssetDefinition`,
and canonical `InternalTransferLink` records used by manual brokerage entry.

Supported activities are exactly BUY, SELL, DIVIDEND, FEE, TAX, DEPOSIT,
WITHDRAWAL, and SPLIT. Unknown activity text remains `UNRESOLVED`. Unsupported
corporate actions are not guessed.

## Mapping and review

The review screen explicitly maps date, activity, symbol/instrument, quantity,
execution price, gross amount, fee, tax, currency, reference, note, optional
broker realized P&L, and split ratio. The canonical header preset is only a
deterministic convenience; external layouts require explicit mapping.

An exact active symbol-and-currency match may map automatically. Any other
instrument stays unresolved until the user chooses **Map to existing** or
**Create compatible asset definition**. No fuzzy match and no silent
instrument or category creation occurs. Funding rows require an explicit
active, same-currency counterparty account.

Pilgrim's weighted-average asset ledger remains authoritative. Broker-provided
realized P&L is comparison evidence only; a difference is shown as a
non-blocking reconciliation warning and never overwrites Pilgrim's basis.

## Stable identity and duplicates

Each statement event receives a UUIDv5 derived from household ID, brokerage
account ID, source-file SHA-256 fingerprint, stable source-row identity, and
the authoritative mapped-row fingerprint. Child fee, tax, funding-leg, and
transfer-link IDs derive from that event ID. Review choices never replace the
event identity.

Commit verifies that the preview still belongs to the effective household,
brokerage account, source, and row identity. Exact re-import is classified as
already present and creates no financial or outbox effect. Semantic and
possible duplicates remain excluded unless the user explicitly includes them.

## Atomicity and local-first behavior

Final commit revalidates definitions, duplicate evidence, stable identities,
and chronological asset quantity. Approved new definitions, transactions,
canonical transfer links, and ordinary outbox operations are then written in
one native SQLite transaction; the web development store mirrors rollback
semantics. A failure leaves all four sets unchanged.

The resulting authoritative N0 rows use ordinary offline sync, conflict,
reconnect, initial-sync, encrypted-backup v7, exact restore, clone, reporting,
budget, Tithe, and Health Check behavior. N1 adds no database field, migration,
backup section, remote authority, or special synchronization channel.

## Limits

- CSV only; no PDF/image extraction or AI interpretation.
- No brokerage login/API, scraping, trading, or order placement.
- No tax-law calculation.
- No options, futures, margin, shorts, security transfer between brokers, or
  unsupported corporate action.
- Account currency and source currency must match; no FX rate is fabricated.
- Review state is in-memory for this bounded importer; only committed
  authoritative financial records persist.
