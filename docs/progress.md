# Pilgrim Tracker Progress

## D14 closed — 2026-08-02

**D14 PASS — Ready for controlled private deployment by Enos and Grace.**

Owner acceptance covers private household use on Windows and Android, hosted
Supabase synchronization, encrypted backup and restore, and CSV export. It does
not claim public production launch, Play Store publication, enterprise use,
web production readiness, or third-party security certification.

Accepted evidence includes configured Windows release runtime, owner-signed
APK/AAB output with a verified non-debug Enos APK signature, Android runtime
and reopen persistence, Android-to-Windows synchronization, Windows/Android
backup workflows, safe restore, CSV ZIP export and owner inspection, and
invalid-extension rejection. The automated baseline is 587 passing tests and a
clean analyzer; web, Windows debug, and Android debug compilation gates passed
during the latest repair. No verification was rerun for this documentation-only
closure. Further development may begin.

- Closed-beta fresh-install blocker fixed: production bootstrap no longer creates
  demo accounts, projects, categories, transactions, balances, or analytics.

- BETA-04C conflict resolution, sync health, automatic triggers, and Realtime
  wake-up are implemented locally. Remote deployment and BETA-05 owner
  acceptance remain open.

**Snapshot date:** 2026-07-21

```text
flutter analyze
No issues found!

flutter test
93 tests passed
```

## Current application state

- Flutter shell runs on web preview, Android, and Windows targets.
- Navigation contains Overview, Assets, Transactions, Accounts, Categories, Asset Conversion, Projects, Tithe, and Reports.
- Overview is period-based and no longer carries detailed asset analytics.
- Assets is a dedicated portfolio destination.
- Transactions use repository/use-case/controller flow.
- Native storage uses SQLite version 5.
- Web uses a compatible in-memory preview store.
- Accounts, categories, and projects are seeded/manageable.
- Tithe summaries use an effective-date policy.

## Dashboard work completed

- Assets inserted after Overview.
- navigation tests updated
- Overview reduced to monthly balance, income, expenses, tithe, cash flow, spending, recent transactions, and activity
- detailed assets moved to Assets

## Asset transaction work completed

Transaction now supports:

```text
assetName
assetSymbol
assetAction
quantity
unit
unitPrice
```

- buy/sell actions are explicit
- stock ticker is required
- shares and grams are recorded
- SQLite v4 added asset name/action
- SQLite v5 added symbol and market-price cache
- legacy conversions remain calculable

## Market-price work completed

Added:

```text
AppEnvironment
MarketQuote
AssetSymbolMatch
AssetPriceRepository
AlphaVantageAssetPriceRepository
AssetMarketPrice
AssetPriceController
```

Capabilities:

- stock quote parsing
- symbol-search service
- gold spot retrieval
- USD/IDR and ounce/gram conversion
- provider/rate-limit errors
- injected HTTP client tests
- online and manual prices
- cached latest native prices
- source/status/date display
- no-key manual fallback

## Portfolio engine completed

Added:

```text
AssetPortfolio
AssetHolding
AssetKind
AssetPortfolioCalculator
```

Implemented:

- gold quantity
- stock shares/lots
- chronological processing
- weighted-average cost
- remaining cost basis
- partial sale
- realized/unrealized gains
- market value
- quote matching
- cost-basis fallback
- legacy support
- soft-delete filtering

## Assets UI completed

- portfolio value
- cost basis
- realized/unrealized gain
- holdings
- quantity/lots/shares
- average/current price
- market value and return
- online/manual refresh
- quote source/status/date
- provider error and empty states

## Current boundaries

- `AppShell` composes features.
- HTTP parsing stays in data implementation.
- quote retrieval uses a domain repository.
- portfolio math stays in a pure domain service.
- widgets render and trigger controller actions.
- native and web stores keep compatible methods.

## Known gaps

High priority:

- no persistent `AssetDefinition`
- lot size fixed at 100 for stocks
- stock online refresh assumes IDR
- provider symbol/exchange/currency not separately configured
- overselling not blocked before save
- fee treatment shown but not persisted/applied
- client API key unsuitable for public release

Medium priority:

- web storage is in-memory
- latest quote only, no history
- symbol-search has no UI
- no refresh-age/rate-limit policy
- no complete net worth with cash/liabilities
- no market-value allocation chart
- no safe ticker-correction flow

Planned migrations:

- Drift
- Riverpod
- GoRouter
- ledger entries
- revisions
- sync queue
- persistent tithe entities

## Next implementation

Add persistent `AssetDefinition` with:

```text
id
displayName
kind
symbol
providerCode
providerSymbol
exchangeCode
currencyCode
unit
lotSize
onlinePricingEnabled
createdAt
updatedAt
deletedAt
version
deviceId
syncStatus
```

Then migrate v5 safely, seed defaults, integrate conversion selection, use configured lot/currency, reject quote-currency mismatch, add oversell validation/fees, and preserve all 93 tests.

## BETA-01 — Structured Accounts, Opening Balances, and Local Profile

Completed on 2026-07-26:

- stable structured `Account` records with legacy name-list compatibility;
- signed integer starting balances with nullable effective dates;
- pure account balance calculation with date, deletion, asset-fee, and legacy
  transfer rules;
- real account cards plus create/edit/remove starting-balance UI and old-entry
  warning;
- lightweight persistent local profile and session;
- SQLite version 11 fresh schema and historical/v10 migration;
- native reopen, web parity, bootstrap idempotence, reporting isolation, and
  responsive widget coverage.

Final verification: 29 focused BETA-01 tests and 431 full-suite tests passed;
Flutter analysis reported no issues; the web build and WebAssembly dry run
succeeded.

These D14 gates were later completed and accepted in the 2026-08-02 closure.

## BETA-02 — Household, Members, Books, and Sync-Ready Local Architecture

Completed on 2026-07-26:

- authoritative `FinancialBook` boundary and local `HouseholdMember` model;
- one idempotent default household with the local profile as owner;
- active book/member session persistence and per-book store reads/seeds;
- joint or member-owned accounts plus owner filtering;
- active-member attribution for new and duplicated transactions;
- Household Settings with local add, rename, role display, and active selection;
- SQLite version 12 migration and equivalent in-memory web behavior;
- documented Supabase/RLS direction and durable offline-sync requirements.

BETA-02 did not itself provide cloud identity, invitations, synchronization, or
two-device sharing. Later milestones and the 2026-08-02 D14 closure completed
the approved private-deployment gates.

Final verification: 20 focused BETA-02/accounting tests and 442 full-suite
tests passed; Flutter analysis reported no issues; the web build and WebAssembly
dry run succeeded.

## Historical D14 Final owner-acceptance pass — 2026-07-30

The owner Android certificate identity passed preflight. Exactly one signed APK
build was attempted; Gradle's Java daemon exhausted native memory, so no signed
APK/AAB was produced and Android runtime remained blocked without an attached
target. Windows release compilation, identity metadata, and process startup
passed, but interactive runtime/reopen and portability acceptance were not run.
No production code changed; the 546-test, clean-analyzer, and passing web/Wasm
BETA-06 baseline was reused. D14 remained open at that checkpoint; the later
2026-08-02 owner closure supersedes this verdict.

## BETA-06 — Household backup, safe restore, and CSV export

Implemented on 2026-07-29 with encrypted household snapshots, integrity and
accounting verification, non-merge restore modes, mandatory pre-replacement
safety backup, local-only post-restore state, spreadsheet-safe CSV ZIP, scoped
platform file access, and SQLite version 20 household-scoped market-price keys.
Final gates are recorded in `CHECKPOINT_BETA06_COMPLETE.md`; owner runtime
acceptance was completed in the 2026-08-02 D14 closure.

## BETA-04B — Controlled initial upload and secondary download

Completed locally on 2026-07-26:

- SQLite version 15 durable initialization state, manifest, progress, safe
  errors, snapshot boundary, and upload/download staging with web parity;
- owner-confirmed one-time primary upload, enforced server-side against an
  occupied remote mirror, using stable bounded idempotent batches;
- authorized stable secondary download with non-merge target protection,
  atomic integrity validation/activation, member mapping, and no outbox echo;
- interruption resume, safe cancellation, and cursor handoff to one immediate
  incremental synchronization run;
- focused Initial Synchronization UI under Cloud Sharing; and
- a 17-assertion pgTAP suite for claims, idempotency, completion,
  authorization, and cross-book denial.

BETA-04 remains open for BETA-04C conflict-resolution UX and synchronization
polish. BETA-05 remains responsible for real Enos/Grace two-device proof.

Final verification: 35 focused tests and 493 full-suite tests passed; Flutter
analysis reported no issues; the web release build and Wasm dry run succeeded.
The 17-assertion BETA-04B pgTAP suite was authored but not executed because the
Supabase CLI is unavailable locally.

## BETA-04A — Durable outbox and cursor protocol

Completed on 2026-07-26:

- SQLite version 14 durable outbox, per-book cursor/initialization state, and
  conflict persistence with native/web parity;
- atomic local record plus outbox writes for all seven syncable entity types;
- authenticated, membership-scoped, idempotent and version-aware Supabase push;
- monotonic book-scoped pull with atomic local batch/cursor commit;
- tombstones, interrupted-send recovery, bounded retry, single-flight runs,
  durable version conflicts, and calm Cloud Sharing status;
- explicit primary-upload/secondary-download guard preventing accidental
  historical transfer before BETA-04B.

Final verification: 29 focused tests and 484 full-suite tests passed; Flutter
analysis reported no issues; the web build and Wasm dry run succeeded. The
16-assertion pgTAP suite was authored but not executed because Supabase CLI is
unavailable locally. BETA-04 remains open for BETA-04C.

## BETA-04A — Durable outbox and cursor protocol

Completed on 2026-07-26:

- SQLite version 14 durable outbox, per-book cursor/initialization state, and
  conflict persistence with native/web parity;
- atomic local record plus outbox writes for all seven syncable entity types;
- authenticated, membership-scoped, idempotent and version-aware Supabase push;
- monotonic book-scoped pull with atomic local batch/cursor commit;
- tombstones, interrupted-send recovery, bounded retry, single-flight runs,
  durable version conflicts, and calm Cloud Sharing status;
- explicit primary-upload/secondary-download guard preventing accidental
  historical transfer before BETA-04B.

Final verification: 29 focused tests and 484 full-suite tests passed; Flutter
analysis reported no issues; the web build and Wasm dry run succeeded. The
16-assertion pgTAP suite was authored but not executed because Supabase CLI is
unavailable locally. BETA-04 remains open for BETA-04C.

## BETA-03 — Supabase authentication and household authorization

Implemented on 2026-07-26:

- optional Supabase Flutter initialization through public `--dart-define`
  configuration with fully usable unconfigured/offline local mode;
- email OTP request, verification, restored session, and remote-only sign-out;
- remote books, memberships, invitations, financial mirror tables, monotonic
  change cursor, least-privilege grants, and membership-scoped RLS;
- idempotent household linking and invitation create/discover/accept operations;
- Cloud Sharing UI inside Household Settings with an explicit no-sync warning;
- SQLite version 13 additive remote-link/member-auth mapping and web parity.

BETA-03 does not synchronize financial rows. BETA-04 remains responsible for
the durable outbox, server cursor exchange, idempotent transfer, tombstones,
conflict resolution, retries, and recovery.

Final verification: 25 focused tests passed (19 new BETA-03 tests), 461 tests
passed in the full suite, Flutter analysis reported no issues, and the web
release build plus Wasm dry run succeeded. The 19-assertion pgTAP suite was
authored but not executed because Supabase CLI is unavailable locally.

Final verification: 25 focused tests passed (19 new BETA-03 tests), 461 tests
passed in the full suite, Flutter analysis reported no issues, and the web
release build plus Wasm dry run succeeded. The 19-assertion pgTAP suite was
authored but not executed because Supabase CLI is unavailable locally.

Final verification: 20 focused BETA-02/accounting tests and 442 full-suite
tests passed; Flutter analysis reported no issues; the web build and WebAssembly
dry run succeeded.
