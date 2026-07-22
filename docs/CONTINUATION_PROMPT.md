# Continuation Prompt

```text
Continue the existing Flutter project Pilgrim Tracker / ExpenseTracker.

Read completely, in order:

1. docs/PRODUCT_SPEC.md
2. docs/ARCHITECTURE.md
3. docs/ARCHITECTURE_DECISIONS.md
4. docs/DATABASE_SCHEMA.md
5. docs/ROADMAP.md
6. docs/PROGRESS.md
7. docs/NEXT_STEP_PLAN.md

Verified baseline:

- flutter analyze: no issues
- flutter test: 93 passing
- native SQLite version: 5
- Overview and Assets are separate
- asset transactions persist quantity, unit, unitPrice, assetName, assetSymbol, assetAction
- AssetPortfolioCalculator handles weighted average, partial sales, gains, and legacy records
- AssetPriceRepository has Alpha Vantage implementation
- AssetPriceController supports cached online/manual prices
- AssetsDashboard shows holdings, lots/shares, prices, values, returns
- API key comes from ALPHA_VANTAGE_API_KEY
- web LocalStore is an in-memory preview
- fees are not persisted/applied
- overselling is not blocked before save
- non-IDR quote handling is not yet safe

Implement only:

PERSISTENT ASSET DEFINITIONS AND CURRENCY-SAFE VALUATION.

Requirements:

1. Add AssetDefinition entity.
2. Include id, displayName, kind, symbol, providerCode, providerSymbol, exchangeCode, currencyCode, unit, lotSize, onlinePricingEnabled, timestamps, deletion, version, deviceId, syncStatus.
3. Add repository contract and local implementation.
4. Upgrade SQLite safely from v5.
5. Add equivalent web-store methods.
6. Preserve transactions and cached prices.
7. Keep existing assetName/assetSymbol snapshots.
8. Add load/add/edit controller and simple management UI.
9. Make Asset Conversion select a concrete definition.
10. Make portfolio use definition lot size, unit, and currency.
11. reject/handle quote-currency mismatch.
12. Keep provider code behind AssetPriceRepository.
13. Do not migrate Drift, Riverpod, or GoRouter.
14. Do not put HTTP, SQL, or portfolio math in widgets.
15. Add entity/repository/migration/controller/calculator/widget tests.
16. Preserve all 93 tests.
17. Update documentation.

Workflow:

- inspect exact files
- make backups
- work in small batches
- format
- analyze
- focused tests
- full tests

Report files, migration, tests, final results, and remaining limitations.
```
