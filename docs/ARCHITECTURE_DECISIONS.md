# Pilgrim Tracker Architecture Decisions

**Snapshot date:** 2026-07-21

## ADR-001 — Local-first writes

Financial writes are local first. Online services enhance the product but do not gate normal transaction entry.

## ADR-002 — Integer money, separate measurable quantity

Money is stored as integer values. Asset quantities may use `double`.

## ADR-003 — Feature-first boundaries

Transactions, assets, dashboard, tithe, and reports remain separate features. `AppShell` composes features; it does not absorb their business logic.

## ADR-004 — Overview and Assets are separate destinations

Overview reports period activity. Assets manages holdings and valuation.

## ADR-005 — Asset buy/sell identity is explicit

New asset conversions persist `assetName`, `assetSymbol`, and `assetAction`. String parsing is legacy compatibility only.

## ADR-006 — Weighted-average cost basis first

Partial sales remove cost using the pre-sale weighted average. FIFO and specific-lot accounting remain future strategies.

## ADR-007 — Current quote is separate from historical cost

Updating a quote must not rewrite purchase transactions or cost basis.

## ADR-008 — Quote provider behind a repository contract

`AssetPriceRepository` is the domain boundary. Alpha Vantage is one implementation.

## ADR-009 — Manual price is always available

Manual pricing remains usable without an API key and after provider failure.

## ADR-010 — Cache the latest quote locally

`asset_market_prices` stores the latest price per asset key. Full historical price series requires a later table.

## ADR-011 — Native/web LocalStore API parity

Native and web stores expose the same public methods. New store methods must be added to both.

## ADR-012 — Incremental framework migrations

Drift, Riverpod, and GoRouter are planned migrations, not prerequisites for unrelated business features.

## ADR-013 — Client API keys are not production security

`dart-define` is acceptable for private local development only. Public distribution requires a backend proxy.

## ADR-014 — Database changes are versioned

Persisted changes require a version increment, `onCreate`, `onUpgrade`, record mapping, native/web parity, and tests.

## ADR-015 — Tests and docs are completion criteria

A feature batch is complete only after formatting, clean analysis, passing tests, and updated documentation.

**Current baseline:** 93 passing tests.
