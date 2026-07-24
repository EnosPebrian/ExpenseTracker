# D11 Complete

- D11 behavior completed: foreign-currency buy/sell conversion, derived IDR
  rates, USD/SGD weighted-average valuation, quote compatibility checks, and
  currency-specific asset presentation.
- Files changed: asset conversion controller/form/summary, portfolio
  calculator, assets dashboard, and focused asset/controller/portfolio/widget
  tests.
- SQLite version: 7. No D11 schema migration or persistence change.
- Tests added: USD buy/sell, SGD conversion and valuation, weighted-average
  partial sale, incompatible FX quote rejection, and foreign-currency UI.
- Analyzer result: clean (`flutter analyze`, no issues found).
- Final test count: 158 passing (`flutter test`) after the closure audit.
- Web verification: `flutter build web` completed successfully, including the
  Wasm dry run.
- Runtime checks: focused Flutter tests and full suite completed. Chrome launch
  was attempted, but the interactive smoke flow was not completed.
- Closure fix: archived definitions are excluded from new conversion choices;
  archived and missing definitions remain readable for historical records.
- Known D12 limitations: oversell prevention, fee accounting, spread
  modeling, and additional rounding/precision policies remain deferred.
