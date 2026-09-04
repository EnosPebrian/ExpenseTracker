# Pilgrim Tracker Progress

## BETA-08J Data Health & Sync Diagnostics — 2026-09-01

Implemented a read-only Data & Sync Health Check over immutable local snapshots.
It covers SQLite v25, household/transaction references, existing account
reconciliation, canonical/legacy transfers, Import Inbox and G1 identity,
rules/budgets/tithe, local outbox/conflicts/cloud status, and truthful encrypted
backup v4 support. It adds stable codes, deterministic severity, expandable
responsive UI, safe navigation, privacy-safe copy, and large-data tests without
repair, persistence, SQL, cloud calls, or hosted changes. Owner acceptance is
NOT RUN. Final gate results are recorded in `CHECKPOINT_BETA08J_COMPLETE.md`.

Engineering PASS. The owner temporarily lifted feature freeze for the bounded
BETA-08K through BETA-08N sequence; freeze resumes after BETA-08N.

## BETA-08K Cloud Durability & New-Device Bootstrap — 2026-09-04

Reused the existing local-first outbox/change-feed and protected initial-sync
architecture for normal new-device recovery. Added explicit selection among
all authorized initialized hosted households and retained selected
membership/member context. Sync events that arrive during an active run now
coalesce into one follow-up run. Empty-device download, populated-target
rejection, interruption/restart/idempotency, membership isolation, health
status, and a 5,000-transaction activation are covered without adding SQLite,
backup, Supabase, hosted deployment, or background-service changes. Owner
acceptance is NOT RUN. BETA-08L/M/N are not implemented.

Engineering PASS: 82 focused tests and 832 full-suite tests passed; analyzer,
web, Windows debug, and Android debug gates passed. The preserved BETA-08E
500-rule/5,000-draft performance regression was made deterministic by
normalizing each draft input once without changing rule matching behavior.

## BETA-08H1 hosted deployment preflight blocked — 2026-08-31

Read-only preflight confirmed the expected linked private Supabase project and
the exact local E -> F0 -> G -> G1 -> H migration chain. The hosted project is
inactive, its migration history could not be read, no recoverable hosted backup
was listed, and the four required OpenAI/Telegram server secrets are missing.
The mandatory safety gate stopped the run before any hosted mutation, function
deployment, webhook call, artifact build, or owner action. Engineering PASS for
BETA-08A1 through BETA-08H remains valid; Hosted Deployment and Consolidated
Owner Runtime remain NOT RUN. See `CHECKPOINT_BETA08H1_DEPLOYMENT.md` and
`CONSOLIDATED_OWNER_ACCEPTANCE_A1_TO_H.md`.

## BETA-08C/D reviewed document ingestion implemented — 2026-08-19

Receipt/invoice photos and bank-statement PDF/image sessions now enter the
existing BETA-08B mapping, review, duplicate-detection, atomic commit, and
ordinary outbox pipeline through an authenticated, non-retaining Supabase Edge
Function gateway. Statement ingestion includes stable source and row identity,
same-file idempotency, overlapping-period duplicate review, debit/credit
normalization, page-completeness metadata, and exact balance reconciliation.
SQLite remains version 21 and no Supabase SQL migration or sync protocol change
was introduced.

Final verification passed 48 focused BETA-08B/C/D tests, all 703 Flutter tests,
and 7 local Edge Function contract/security tests without a paid API call.
`flutter analyze` reported no issues; web, Windows debug, and Android debug
builds succeeded. The Android build retained the known forward-looking
`file_picker` Kotlin compatibility warning. Owner runtime acceptance for both
milestones is deferred and NOT RUN.

## BETA-08A1 restore lifecycle implemented — 2026-08-10

Full Restore now has three explicit destinations: remain local, reconnect to an
existing hosted household, or create a separate shared household. New sharing
uses a fresh-identity clone with complete supported-entity reference remapping
and the existing controlled initial-upload protocol. The original restored
snapshot and every pre-existing hosted household remain protected. SQLite stays
at version 21 with no Supabase SQL change. BETA-08A real-owner selective recovery
is recorded PASS. Final verification passed 61 focused tests and all 655 Flutter
tests; analysis found no issues; web, Windows debug, and Android debug builds
succeeded. Android retained the known forward-looking `file_picker` Kotlin
compatibility warning.

## BETA-07C deployment complete; owner acceptance open — 2026-08-03

The monthly-budget Supabase migration is deployed to the linked private
project, local and remote migration histories agree, and local verification
passed 81 pgTAP assertions. Configured Windows, owner-signed APK, and
owner-signed AAB releases were rebuilt; the APK verifies with the expected Enos
certificate and is not debug signed. Required existing-database, CRUD,
calculation, navigation, copy, two-device/offline/conflict, backup/restore, CSV,
and category-lifecycle owner checks remain NOT RUN. BETA-07C is therefore FAIL
at the acceptance gate, and BETA-07A/B remain unreleased. Historical D14 status
is unchanged.

## BETA-07B implemented, unreleased — 2026-08-03

Explicit monthly budget copying now previews a selected source month against
the displayed target month, adds only missing active-category plans, skips
already-present or unavailable categories safely, and never copies spending.
Linked SQLite writes and ordinary budget outbox operations are atomic;
local-only and web-preview paths remain supported. The Budgets page now shows a
compact planning summary and immediate understandable success/no-op results.
Engineering validation is recorded in `CHECKPOINT_BETA07B_COMPLETE.md`.
BETA-07A/B remain unreleased pending owner acceptance; D14 remains the
historical private-deployment baseline.

## BETA-07A implemented, unreleased — 2026-08-02

Monthly household expense-category budgets are implemented across SQLite v21,
the web preview, Windows/Android-responsive UI, existing Supabase sync and
conflict resolution, encrypted backup format v2 with v1 compatibility, restore,
and CSV export. Engineering validation is recorded in
`CHECKPOINT_BETA07A_COMPLETE.md`. Owner acceptance is still required before
this milestone is released. The completed D14 private-deployment checkpoint
below remains the historical baseline.

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

## 2026-08-09 — BETA-07 closed and BETA-08A implemented

BETA-07A PASS, BETA-07B PASS, BETA-07C PASS, BETA-07C1 superseded by C2,
and BETA-07C2 PASS on owner Windows/Android devices for controlled private
deployment by Enos and Grace. D14 history remains unchanged.

BETA-08A adds same-household selective encrypted-backup recovery, hosted
read-only verification, stable-ID and semantic duplicate classification,
dependency-aware preview, and atomic normal-mutation/outbox commit. SQLite
remains v21 and no Supabase SQL changed. Owner acceptance follows
`BETA08A_OWNER_ACCEPTANCE.md`.

## BETA-07C1 — hosted household reconnect recovery

Implemented an explicit recovery path for a signed-in mapped member whose
active household became local-only after safe replacement restore. Discovery
uses active hosted memberships and protected manifests only. Same-ID recovery
requires an encrypted safety backup and atomically installs the authoritative
hosted snapshot with its cursor; different-ID recovery preserves the current
book and uses secondary download. No automatic merge, local upload, outbox
generation, SQL migration, or financial-rule change was introduced. Owner
Windows/Android retesting remains required, so BETA-07C is not closed.

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
# 2026-08-19 — BETA-08B

Implemented the CSV transaction ingestion pipeline: scoped picking, strict
parsing/mapping, exact dates and money, deterministic UUIDv5 identities, shared
duplicate detection, review controls, atomic transaction/outbox persistence,
and ordinary local-first synchronization. SQLite remains v21 and no Supabase
change was required. BETA-08A1 owner acceptance remains deferred.

# 2026-08-19 — BETA-08C/D

Implemented one authenticated, server-secret document extraction gateway plus
receipt/invoice and bank-statement ingestion. Both normalize into BETA-08B's
review, duplicate, atomic commit, and ordinary sync path. Added source hashing,
exact reconciliation, page completeness, safe overlap handling, cancellation,
retry, and privacy controls. SQLite remains v21; owner acceptance is deferred.

# 2026-08-19 — BETA-08E engineering

Implemented persisted household merchant/category import rules across the
shared CSV, receipt, and statement draft pipeline. Added deterministic
normalization/operators/priority/ambiguity, explicit provenance and rule
confirmation UI, SQLite v22/web parity, ordinary sync/conflicts/RLS, encrypted
backup v3, selective recovery, and restore/new-household remapping. No AI,
automatic transaction creation, retroactive recategorization, or transfer
matching was added. Owner acceptance for BETA-08A1/B/C/D/08E remains deferred.

# 2026-08-20 — BETA-08F0 engineering

Implemented the canonical internal-transfer foundation as two stable ordinary
transaction legs plus one explicit directional relation. Added SQLite v23/web
parity, atomic lifecycle operations, reporting/budget/tithe exclusions,
logical transaction UI, existing sync/conflict/initial-sync integration,
Supabase RLS and validation, encrypted backup v4, recovery/clone handling, and
coherent CSV context. Legacy one-row transfers are unchanged. Automatic
matching and owner runtime acceptance remain deferred.

# 2026-08-21 — BETA-08F1 engineering

Implemented deterministic indexed internal-transfer matching for
draft-to-existing, existing-to-existing, and draft-to-draft records, with
explainable ambiguity-safe review and stale-checked pair-atomic conversion.
SQLite remains v23, backup remains v4, no Supabase migration was added, and
owner acceptance is deferred.

# 2026-08-29 — BETA-08G engineering

Phase 0 Windows and Android debug builds passed, closing BETA-08F1 and
consolidated BETA-08F as Engineering PASS while owner acceptance remains not
run. Implemented the persistent Import Review Inbox for CSV, receipt, invoice,
and bank-statement normalized drafts with SQLite v24, native/web parity,
ordinary cross-device sync and initial snapshots, provenance-safe current-state
reanalysis, workflow-only discard, deterministic commit/reconciliation safety,
and one undeployed Supabase migration. Backup remains v4 and source files are
not retained. Telegram remains future documentation only.

# 2026-08-30 — BETA-08G1 deferred import identity

Implemented the narrow prerequisite requested after BETA-08H's safety stop.
Import-review workflow/source identities now exist independently of nullable
account-dependent final transaction identity. Added canonical UUIDv5
finalization, explicit account binding, account-change invalidation, commit and
conflict guards, SQLite v25 migration, web/sync parity, an undeployed Supabase
migration, pgTAP coverage, and focused restart/sync/reconciliation tests. Backup
remains v4. Owner acceptance is deferred. No Telegram code was implemented as
part of BETA-08G1 itself.

## BETA-08H — Secure Telegram ingestion (engineering)

Implemented one undeployed server migration, private pairing and connection
management, authenticated/idempotent webhook processing, transient secure file
handling, canonical CSV plus reused document extraction, atomic unresolved
Inbox delivery, Integrations UI, SQL/Edge/Flutter tests, and deployment/owner
guides. SQLite stays 25 and backup stays v4. Hosted deployment and owner
acceptance remain deferred.

# 2026-08-31 — BETA-08I financial statements

Implemented local Monthly/Annual Household and Account statements using a pure
generator over existing balance, report, transfer, tithe, and budget semantics.
Added responsive preview and local A4 PDF export through the existing portable
file service, currency separation, deterministic running balances, explicit
year-end net-worth omission, and focused financial/UI/PDF fixtures including a
5,000-transaction annual case. SQLite remains 25, backup remains v4, and no
Supabase/SQL or BETA-08H1 hosted change was made. Final verification passed 13
focused tests, 810 full-suite tests, analyzer, web, Windows debug, and Android
debug gates. Owner acceptance remains NOT RUN.
