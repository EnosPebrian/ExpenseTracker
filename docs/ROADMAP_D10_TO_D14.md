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

The overall D12 milestone remains open pending final engineering review.

## D13 — Asset-management finalization

Planned.

## D14 — Regression, cleanup, documentation, and release hardening

Planned.
