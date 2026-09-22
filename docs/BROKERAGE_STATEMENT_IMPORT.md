# Brokerage Statement CSV Import

## Scope

BETA-08N1 imports UTF-8 broker-export CSV files into the existing BETA-08N0
investment ledger. It does not introduce a second accounting engine. Financial
rows become the same authoritative `Transaction`, `AssetDefinition`,
and canonical `InternalTransferLink` records used by manual brokerage entry.

Supported financial activities are BUY, SELL, DIVIDEND, INTEREST, FEE, TAX,
DEPOSIT, WITHDRAWAL, and SPLIT. R3 adds separate non-financial BUY_SETTLEMENT and
SELL_SETTLEMENT evidence. Unknown activity text remains `UNRESOLVED`. Unsupported
corporate actions are not guessed.

## Mapping and review

The review screen explicitly maps date, activity, symbol/instrument, quantity,
execution price, gross amount, fee, tax, currency, reference, note, optional
broker realized P&L, and split ratio. The canonical header preset is only a
deterministic convenience; it recognizes both canonical snake-case labels and
Pilgrim's exported human-readable labels (for example, `Symbol / instrument`
and `Broker realized P&L`). External layouts require explicit mapping.

Money remains exact integer minor-unit accounting. Brokerage statement imports
may review non-zero fractional IDR using HALF_UP to the nearest rupiah, with
negative ties moving symmetrically away from zero. The review identifies every
affected row and final import remains disabled until the user approves rounding
for that session. Structured provenance appended to the durable note metadata
preserves each original source value, field, rounded integer and policy. This
does not change household transaction precision or other CSV importers.

The Date column is inspected as a whole when automatic format is selected.
ISO dates prefer yyyy-MM-dd; slash dates select DD/MM/YYYY or MM/DD/YYYY only
when one interpretation fits the entire column. Ambiguity requires a format
choice. Invalid dates retain their source text and a null review date; no epoch
date is fabricated and unresolved dates cannot commit.

An exact active symbol-and-currency match maps automatically, case-insensitively.
Buy, Sell, Dividend and Split require an instrument. Interest, funding, Fee and
Tax do not.
In **Trusted Stockbit / IDX statement** mode, unknown four-letter equity symbols
are staged once per normalized symbol with symbol-as-name, IDX exchange, IDR
currency and lot size 100. The summary counts included ready instrument
creations. Definitions remain in memory until final atomic import. Existing,
archived or ambiguous catalog identities cannot be silently duplicated. Generic
statements retain explicit map/create review. Funding rows require an active,
same-currency counterparty account.

Rows show Ready, Ready · New instrument, Needs review or Invalid. Needs-review
rows may be explicitly excluded so the valid selected rows can proceed.

BUY_SETTLEMENT and SELL_SETTLEMENT import as unmatched non-financial evidence,
without an instrument or a fake Buy/Sell choice. They create no transaction,
cash, position, P&L, income/expense, budget, net-worth or Tithe effect. Persisted
evidence is available from the Settlement evidence action for explicit
many-to-many reconciliation. See BROKERAGE_SETTLEMENT_EVIDENCE.md.

Exact normalized `INTEREST` resolves automatically. A valid Interest row needs
only date, positive amount, and compatible brokerage currency. It never needs a
symbol, quantity, execution price, or split fields. Its reviewed commit creates
one instrument-free investment transaction; explicit source TAX remains a
separate deterministic child transaction. Zero/negative Interest keeps its
source sign, blocks commit, and is never coerced with `abs()` or reclassified as
Fee. Exact reimport remains inert.

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
reconnect, initial-sync, encrypted-backup v8, exact restore, clone, reporting,
budget, Tithe, and Health Check behavior. N1 adds no database field, migration,
backup section, remote authority, or special synchronization channel.

The later Interest repair adds only the undeployed additive Supabase migration
`20260916000331_beta08n_interest_activity.sql`, extending the existing activity
constraint/validation function. SQLite remains v29 and backup remains v8.

## Limits

- CSV only; no PDF/image extraction or AI interpretation.
- No brokerage login/API, scraping, trading, or order placement.
- No tax-law calculation.
- No options, futures, margin, shorts, security transfer between brokers, or
  unsupported corporate action.
- Account currency and source currency must match; no FX rate is fabricated.
- Fractional IDR is supported only by this reviewed brokerage importer. It uses
  explicit session approval, deterministic HALF_UP rounding and durable source
  provenance; rounding is never silent.
- Review state is in-memory for this bounded importer; only committed
  authoritative financial records persist.
