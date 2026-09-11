# BETA-08N Investments UI Navigation Completion Checkpoint

**Engineering status:** PASS
**Owner visual/runtime acceptance:** NOT RUN
**Date:** 2026-09-11

The complete BETA-08N0/N1 brokerage capability is now a first-class
`Investments` destination immediately after `Assets` on desktop and mobile.
The page title is Investments and the subtitle explains that it tracks
brokerage accounts, holdings, trades, and investment performance.

The responsive page contains six functional sections:

- Overview uses existing per-currency performance, account, holding, and
  recent-activity models.
- Brokerage Accounts uses the existing account editor with Brokerage
  preselected.
- Holdings displays positions already derived by the portfolio calculator.
- Trades displays existing BUY and SELL brokerage activity.
- Statements opens the existing reviewed brokerage CSV importer.
- Performance displays existing realized/unrealized, dividend, fee, and tax
  measures without claiming advanced return metrics.

Empty brokerage data produces explicit next-step states instead of errors or
fabricated values. Narrow layouts use scrollable section selection and wrapping
cards; desktop keeps Investments visible in the main sidebar.

Architecture remains unchanged: `Transaction` is the financial truth,
`AccountType.brokerage` is brokerage cash, `AssetDefinition` is instrument
identity, existing portfolio/performance calculators own calculations,
`BrokerageActivityService` owns manual posting, and `BrokerageImportScreen`
owns reviewed statement ingestion. No product placeholder, new calculation,
new parser, provider API, persistence field, schema migration, synchronization
rule, or backup-format change was added.

Validation completed:

- focused navigation/investment regressions: 33/33 PASS;
- full Flutter suite: 989/989 PASS;
- `flutter analyze`: PASS;
- Web build: PASS;
- Windows debug build: PASS;
- Android debug APK build: PASS;
- `git diff --check`: PASS.

SQLite remains version 28 and encrypted backup remains v7. No SQL/Supabase
migration or hosted action occurred. The existing non-blocking `file_picker`
Kotlin compatibility warning remains unchanged. Owner visual/runtime acceptance
on Windows and Android is **NOT RUN**; feature freeze remains active.
