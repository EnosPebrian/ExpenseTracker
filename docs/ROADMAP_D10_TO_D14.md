# D10–D14 Roadmap

## D10 — Foreign-currency asset model and FX pricing

Complete. Concrete USD and SGD definitions, IDR-per-unit FX quotes, validation,
cache/manual pricing, and transaction snapshots are in place.

## D11 — Foreign-currency conversion and valuation

Complete. Foreign-currency buy/sell transactions now derive IDR unit rates,
reuse weighted-average portfolio accounting, value USD and SGD holdings with
compatible FX quotes, and present currency-specific conversion and dashboard
labels.

## D12 — Oversell, fees, spread, and rounding

- D12A asset oversell prevention: Complete.
- D12B persisted trade fees and asset accounting: Complete.
- D12C linked separate-expense asset fees: Complete.
- D12D asset quantity precision and deterministic rounding: Complete.
- D12E stock lot-size and odd-lot validation: Complete.
- D12F execution-reference snapshot and execution-price presentation: Complete.

D12F compares gross execution price with an explicitly selected manual or
compatible cached reference snapshot. It is an estimated execution difference,
not a verified historical bid/ask spread, and it does not affect accounting.

The D12 final engineering closure audit passed. Migration paths from versions
5, 7, 8, and 9 through version 10, combined accounting, fee-link lifecycle,
stock validation, and foreign-currency regression behavior are verified.

**D12 status: Complete.**

## D13 — Asset-management finalization

- D13A asset-definition integrity and duplicate protection: Complete.
- D13B archive/restore and linked-edit protection: Complete.
- D13C1 search, filters, sorting, presets, and UX finalization: Complete.
- D13C2 obsolete-seed retirement and D13 closure audit: Complete.

D13A adds normalized stock/exchange identity checks, stable non-stock market
identity protection, provider-code/symbol uniqueness across asset kinds, and
archived-definition conflict detection. Validation runs at save and seed time;
archive/restore UI was completed in D13B.

D13B adds transaction-derived usage, open-position archive protection,
same-row restore with complete D13A integrity checks, and read-only identity and
accounting fields for definitions linked to historical transactions. Archived
definitions remain available to historical portfolio resolution but are excluded
from new transaction selection.

D13C1 adds presentation-only local search, lifecycle/kind/pricing filters,
deterministic sorting, result counts, responsive empty states, and safe
create-form presets. Catalog state is not persisted, and presets remain subject
to D13A validation and D13B linked-field protection.

D13C2 permanently retires the exact `asset-stock-portfolio` system definition.
Fresh installations never seed it; unused or fully closed legacy rows are
soft-archived, while an open historical holding remains sell-only until it is
closed. Historical snapshots and portfolio accounting remain readable, and a
user-created definition with the same display name is unaffected.

The integrated D13 closure audit passed across integrity, lifecycle, linked
edits, catalog behavior, and legacy retirement. SQLite remains version 10.

**D13 status: Complete.**

## D14 — Regression, cleanup, documentation, and release hardening

Planned.
