# Pilgrim Tracker Architecture

Production bootstrap is load-only for user-owned finance. Reference asset
presets remain automatic, while sample transactions are test-only; see
`FRESH_INSTALL_DATA_POLICY.md`.

BETA-04C keeps conflict coordination in sync services/controllers, persistence
in native/web stores, and provider parsing in the transport. Realtime only
requests the existing single-flight cursor synchronization.

**Snapshot date:** 2026-07-21  
**Verified state:** Analyzer clean; 93 tests passing  
**Style:** Feature-first, local-first, layered, incrementally migrated

## 1. Non-negotiable principles

1. Local storage is the immediate source of truth.
2. Internet is optional for normal transactions.
3. Money uses integer values.
4. Quantity and money remain separate.
5. Presentation does not calculate portfolio accounting.
6. Domain code does not import Flutter UI.
7. Domain repositories are contracts; data implementations satisfy them.
8. Persisted changes require migrations and tests.
9. Project, asset, tithe, and sync metadata must be preserved.
10. Completed feature boundaries must not collapse into `AppShell`.

## 2. Current stack

```text
Flutter / Dart
SQLite via sqflite_common_ffi on native
Conditional LocalStore web fallback
ChangeNotifier controllers
Repository and use-case boundaries
UUID identifiers
package:http for market data
```

Transitional choices:

- ChangeNotifier while Riverpod is planned
- index-based shell navigation while GoRouter is planned
- direct SQLite store while Drift is planned
- in-memory web preview while persistent web storage is planned

Do not mix a broad framework migration into an unrelated feature batch.

## 3. Structure

```text
lib/
  app/
  core/
    config/
    database/
    design/
    shared/
  features/
    analytics/
    assets/
    dashboard/
    master_data/
    reports/
    tithe/
    transactions/
```

Dependency direction:

```text
presentation -> controller/application -> domain
data implementation -> domain contract
core infrastructure -> platform-specific services
```

## 4. AppShell boundary

`AppShell` is the current composition root. It may construct stores/controllers, bootstrap data, connect navigation, calculate page inputs, observe controllers, and dispose resources.

It must not perform HTTP parsing, calculate weighted-average cost, execute SQL directly, or duplicate feature business logic.

Current navigation indices:

```text
0 Overview
1 Assets
2 Transactions
3 Accounts
4 Categories
5 Asset Conversion
6 Projects
7 Tithe
8 Reports
```

## 5. Transaction feature

```text
features/transactions/
  data/repositories/
  domain/entities/
  domain/repositories/
  domain/usecases/
  presentation/controllers/
  presentation/edit/
  presentation/quick_add/
  presentation/screens/
  presentation/widgets/
```

The persisted transaction source for asset buys/sells contains:

```text
quantity
unit
unitPrice
assetName
assetSymbol
assetAction
feeAmount
feeTreatment
relatedTransactionId
relationType
```

New records must not depend on title/account parsing.

Asset trades using separate-expense fee treatment are coordinated in the
transaction use-case layer. The repository persists the parent and its managed
ordinary-expense child through one atomic change set. UI controllers never
orchestrate the two writes, and generated children cannot be independently
edited, duplicated, or deleted.

## 6. Assets feature

```text
features/assets/
  controllers/
    asset_conversion_controller.dart
    asset_price_controller.dart
  data/repositories/
    alpha_vantage_asset_price_repository.dart
  domain/entities/
    asset_market_price.dart
    asset_portfolio.dart
    asset_symbol_match.dart
    market_quote.dart
  domain/repositories/
    asset_price_repository.dart
  domain/services/
    asset_numeric_policy.dart
    asset_portfolio_calculator.dart
    asset_stock_lot_policy.dart
    asset_trade_validator.dart
  presentation/formatters/
    asset_quantity_formatter.dart
  presentation/screens/
    asset_conversion_screen.dart
    assets_dashboard_screen.dart
  presentation/widgets/
```

`AssetNumericPolicy` is the single pure-domain source for measurable asset
precision, new/edit quantity validation, deterministic integer unit-price
rounding, comparison tolerance, and near-zero normalization. Presentation uses
`AssetQuantityFormatter`, which applies the same policy while grouping digits
and trimming unnecessary zeroes. Historical over-precision `REAL` quantities
remain readable and calculable; the stricter policy applies only when a user
creates or edits an asset transaction.

`AssetStockLotPolicy` is the pure definition-driven source for stock lot rules.
Quantities continue to be shares; lots and odd-lot status are derived from the
linked definition's `lotSize`. `AssetTradeValidator` coordinates that policy
with chronological oversell validation. New and edited stock trades use the
quantity available at the candidate date, excluding the original edit record.
Historical odd-lot transactions remain readable, while cleanup sales may sell
whole lots or remove the odd residue to leave a whole-lot or zero balance.

`AssetDefinitionIntegrityPolicy` is the pure-domain validation boundary for new
and edited concrete asset definitions. It normalizes identity comparisons at
validation time without rewriting stored history. Stock identity is symbol plus
exchange, with a missing exchange treated as potentially conflicting; non-stock
definitions protect their established market-price identity. Online provider
code and symbol pairs are unique across asset kinds, and archived definitions
participate in all conflict checks. The controller applies the policy immediately
before persistence and during seed initialization. Archive/restore coordination
is provided by the D13B usage policy and controller lifecycle flow.

`AssetDefinitionUsagePolicy` derives definition lifecycle state from transaction
history. Links use only `assetDefinitionId`; snapshot names and symbols never
link concrete definitions. Soft-deleted asset conversions remain historical
links but do not affect open quantity, while generated fee expenses are ignored.
Open quantity reuses `AssetPortfolioCalculator` and D12D numeric normalization.
The controller blocks archiving open holdings, restores the same persisted row
only after D13A validation, and protects kind, symbol, exchange, currency, unit,
and lot size once any historical transaction is linked. Display name and online
provider configuration remain editable subject to integrity checks.

Asset catalog discovery is presentation-only. `AssetDefinitionCatalogQuery`
holds local search, lifecycle, kind, pricing, and sort state, while the pure
`AssetDefinitionCatalogFilter` derives a deterministic view without mutating
controller or repository state. `AssetDefinitionFormPresets` supplies
create-only suggestions and respects dirty fields; persistence validation still
flows through `AssetDefinitionController` and `AssetDefinitionIntegrityPolicy`.

Responsibilities:

- `AssetConversionController`: form state, validation, explicit buy/sell transaction creation
- `AssetDefinitionController`: save-time integrity coordination and field errors
- `AssetDefinitionIntegrityPolicy`: pure structural and identity conflict rules
- `AssetDefinitionUsagePolicy`: pure usage, archive eligibility, and linked-edit rules
- `AssetDefinitionCatalogFilter`: pure presentation catalog filtering and sorting
- `AssetDefinitionFormPresets`: create-only, dirty-field-aware form suggestions
- `AssetDefinitionRetirementPolicy`: exact-ID legacy retirement, buy/sell eligibility, and restore/edit restrictions
- `AssetPortfolioCalculator`: pure weighted-average calculations and legacy compatibility
- `AssetPriceRepository`: provider contract
- `AlphaVantageAssetPriceRepository`: HTTP/provider parsing
- `AssetPriceController`: cache, refresh, manual price, loading/error state
- `AssetsDashboardScreen`: rendering and action triggers only

## 7. Market-price flow

```text
transactions + cached prices
        |
AssetPortfolioCalculator
        |
AssetsDashboardScreen
        |
user refresh/manual action
        |
AssetPriceController
        |
AssetPriceRepository
        |
provider or manual input
        |
AssetMarketPrice
        |
LocalStore cache
        |
controller notification and recalculation
```

## 8. Overview/Assets boundary

Overview owns period activity: income, expenses, net cash flow, tithe, categories, and recent activity.

Assets owns quantity, lots, cost basis, market prices, market value, and realized/unrealized gains.

Do not move detailed holdings back to Overview.

## 9. Persistence architecture

Conditional export:

```dart
export 'local_store_web.dart'
    if (dart.library.io) 'local_store_native.dart';
```

Native uses versioned SQLite (currently version 15). Web exposes the same method
surface but is currently in-memory. Both stores provide all-or-nothing managed
asset-fee parent/child changes.

Asset execution references are optional immutable transaction snapshots.
Presentation selects a manual or compatible cached quote explicitly; the asset
controller validates identity and snapshot metadata, while the pure
`AssetExecutionAnalysis` service calculates direction-aware differences.
Portfolio, fee, financial-summary, and tithe accounting do not consume this
analytical metadata. The latest-price cache remains mutable and is not price
history.

## 10. Environment configuration

```dart
String.fromEnvironment('ALPHA_VANTAGE_API_KEY')
```

The key is for private/local development only. Public builds need a secure backend proxy.

## 11. Testing

Current verified suite: 401 tests.

Required coverage includes transaction mapping, SQLite round trips, migrations, conversion controller/widget, provider parsing, quote cache, price controller, portfolio calculations, navigation/dashboard widgets, and financial summaries.

## 12. Planned migrations

- Drift behind existing repository/store boundaries
- Riverpod through incremental controller replacement
- GoRouter after route contracts are tested
- full ledger entries and transaction revisions

## 13. Asset guardrails

Do:

- add first-class `AssetDefinition`
- separate display name and provider symbol
- store currency/exchange/unit/lot size
- validate sales before save
- persist fees and treatment
- keep provider code behind repository contract
- keep portfolio math pure
- add migrations and native/web tests

Do not:

- parse tickers from titles for new records
- put HTTP in widgets
- put SQL in controllers
- store money as `double`
- overwrite cost basis with market value
- count unrealized gain as income
- assume every stock uses IDR
- silently oversell
- commit API keys

## 14. Obsolete asset-definition compatibility

The retired generic stock definition is recognized only by the fixed ID
`asset-stock-portfolio`; display names never trigger retirement behavior.
`AssetDefinitionRetirementPolicy` owns this identity and the associated
archive, buy, sell, edit, and restore rules.

Bootstrap excludes this definition from fresh seeds. The definition controller
soft-archives an existing unused or fully closed row using the normal lifecycle
metadata. An open legacy position remains active only as a sell target and is
automatically archived after its quantity reaches zero. Transaction use cases,
Asset Conversion, Quick Add, and transaction editing enforce the same sell-only
rule. Historical transaction snapshots and portfolio fallback remain intact;
no transaction relinking or schema migration is involved.

## 15. Persistence hardening

D14A treats native SQLite as the durable reference implementation and the web
store as an in-memory behavioral preview. Both stores preserve the current
transaction, fee/relation, execution-reference, asset-definition lifecycle,
market-price, and soft-delete metadata contracts. Native linked parent/child
changes use a SQLite transaction; web applies the same change set with snapshot
rollback.

At D14A, version 10 was verified from fresh creation and from historical
versions 1, 3, 5, 7, 8, and 9. Reopen tests reconstruct repositories and calculations from
persisted records rather than retaining pre-close domain objects. Bootstrap is
idempotent across reopen and does not overwrite user definition configuration
or restore archived rows.

## 16. Platform release posture

Android and Windows remain the intended native release targets. Both use the
same Dart domain and feature boundaries; platform runners contain only startup,
identity, permission, and packaging configuration. Native durability remains
SQLite version 15. Web is a buildable development preview backed by the
in-memory store and is not a durable production client.

Optional online pricing is configured at compile time and Android declares
INTERNET permission for its HTTPS provider. A missing provider key remains a
supported state because manual prices are available.

Permanent platform identity is `com.enospebrian.pilgrimtracker` on Android and
`Enos Pebrian` company metadata on Windows. Cross-platform icons derive from
committed SVG/PNG masters through `flutter_launcher_icons`. Android release
signing loads untracked owner properties when present; debug signing requires
an explicit technical-build environment opt-in and never represents the
production identity. Windows certificate identity remains owner-controlled.

## 17. Structured accounts and local profile

BETA-01 adds an immutable `Account` domain entity while preserving
`List<String> accounts` for existing transaction, Quick Add, and conversion
forms. `MasterDataController` owns validation and structured account mutation;
SQLite/web stores accept record maps. Account identity and metadata survive
renames, and active duplicate names are rejected case-insensitively.

`AccountBalanceCalculator` is a pure domain service. With an opening date, the
opening amount is the position immediately before transactions on that local
calendar date; active matching transactions on or after that date are applied.
Without a date, all active matching transactions retain the earlier behavior.
Ambiguous legacy transfers contribute zero because their record does not encode
both sides or direction. Opening balances never become transactions and remain
outside reports, tithe, activity, project/category totals, and portfolio math.

The local profile stores only display name and default currency. `AppShell`
coordinates first-run setup and uses the profile currency for new/default
accounts. The session is restored locally after reopen; it is not secure
authentication, synchronization, or an online identity.

## 18. Household and financial-book boundary

BETA-02 makes `FinancialBook` the authoritative financial-data boundary.
Accounts, categories, projects, transactions, asset definitions, and cached or
manual market prices are written and read under the active book. Bootstrap is
idempotent per book, and legacy null scopes are attached to the migrated book.

`HouseholdMember` represents a local person with an owner/member role. It is
not an authentication account. Accounts may be joint or reference one member;
transactions record the active member as read-only entry attribution. Neither
field affects accounting calculations. The device-local session retains the
active profile, book, and member.

SQLite remains the local source of truth. BETA-03 adds authenticated users,
memberships, PostgreSQL authorization, invitations, and RLS. BETA-04A adds an
atomic durable outbox, idempotent version-aware push, monotonic cursor pull,
tombstones, interruption recovery, and durable conflicts. BETA-04B adds a
stable staged snapshot boundary, owner-only empty-remote upload, authorized
non-merge download, integrity validation, and cursor handoff. Realtime remains
non-authoritative and is deferred to BETA-04C.

## 19. Household data portability

BETA-06 keeps portability feature-first. Presentation coordinates the focused
Backup & Export workflow; its controller owns transient operation state and
confirmation; domain services validate snapshots, calculate integrity totals,
encode/decode the versioned format, and generate CSV; the data layer adapts the
existing local store and scoped platform file picker. `AppShell` only composes
these dependencies.

Native snapshots use one SQLite transaction and final activation is one write
transaction. Restore serializers are domain-oriented rather than tied to raw
SQLite column order. Web mirrors validation with collection snapshot rollback.
Restore bypasses public mutation/upsert paths, creates no outbox work, and does
not carry authentication, device, or sync-protocol state across the boundary.

## 20. Monthly category budgets

BETA-07A adds a feature-first budget slice. `MonthlyBudgetController` owns
month/editor state, `LocalMonthlyBudgetRepository` adapts native/web stores,
and the pure `MonthlyBudgetCalculator` derives all totals from active local
transactions. Widgets contain no SQL or accounting rules. Budgets use the
existing local-first atomic record/outbox path and the existing sync/conflict,
initial-sync, encrypted-backup, restore, and CSV pipelines.

BETA-07B keeps copy classification and candidate creation in the pure
`MonthlyBudgetCopyService`. The repository gathers scoped source/target records
and category lifecycle data; native/web stores apply eligible rows atomically.
Native SQLite inserts copied budgets and ordinary budget outbox operations in
one transaction, while local-only and web-preview paths retain equivalent
add-missing/idempotent behavior. No derived planning totals are persisted and
no bulk remote copy protocol is introduced.

## 21. Selective backup recovery

BETA-08A composes the encrypted backup reader with a focused recovery service,
a source-neutral transaction duplicate detector, and native/web atomic store
adapters. Recovery is additive and identity-aware; replacement restore remains
separate. Linked preflight reads authoritative hosted rows through the existing
authenticated transport and RLS without opening a sync session or writing
remote state. Safe records then enter the unchanged mutation/outbox protocol.
Candidate and recovery-session state remains transient.

## 22. Restore lifecycle bootstrap

`RestoreLifecycleService` owns validation and the non-destructive snapshot clone
and reference remap. `RestoreLifecycleController` coordinates the user-selected
destination and cloud bootstrap callback. `AppShell` only composes activation,
existing cloud linking, and existing initial upload. SQLite activation remains
atomic, the source restored household is preserved, and no new persistence or
Supabase schema is introduced.
# BETA-08B shared ingestion boundary

CSV is the first source adapter for the normalized transaction-ingestion
pipeline: source bytes → parsed rows → mapped drafts → validation/duplicate
classification → review → atomic transaction repository batch → ordinary
outbox. Widgets do not parse CSV and controllers do not write SQL. Future
receipt/PDF/Telegram adapters must stop at the same draft boundary.
# Reviewed document ingestion (BETA-08C/D)

The presentation layer selects sensitive document bytes; a source-specific
controller coordinates an abstract `DocumentExtractionProvider`; the Supabase
data implementation invokes one authenticated Edge Function; and pure domain
normalizers produce the existing canonical import source/drafts. Provider JSON
and HTTP remain outside widgets, validation/reconciliation remain in domain
services, and final persistence remains the existing transaction use case.
There is no receipt/statement SQLite table or separate sync architecture.

## 23. Deterministic import rules

BETA-08E inserts one pure, source-neutral rule evaluation step between draft
normalization/category resolution and duplicate review. CSV, receipt, and
statement adapters all use the same immutable draft model and matcher. Rules
only annotate review suggestions; the existing atomic transaction commit and
ordinary outbox remain unchanged. Household rule configuration is persisted in
SQLite v22 and synchronized through the existing entity protocol. See
`IMPORT_RULES.md`.

## 24. Canonical linked-pair internal transfers

BETA-08F0 adds a narrow `transfer_links` aggregate rather than overloading the
asset-fee parent relation. Two ordinary directional transaction legs retain
their IDs; one stable relation names outgoing and incoming explicitly. A pure
integrity validator and atomic repository operation protect the aggregate.
Reporting receives active paired IDs as classification context while account
balance mathematics remains unchanged. See `CANONICAL_INTERNAL_TRANSFERS.md`.

## 25. Deterministic internal-transfer review

BETA-08F1 adds a pure, source-neutral matcher above import and transaction
review. It indexes candidates by currency, integer amount, direction, and local
date bucket; it does not mutate storage. Controllers coordinate explicit
review, while canonical services perform stale-checked pair-atomic conversion.
There is no matcher persistence or new sync entity.

## 26. Persistent import review inbox

BETA-08G persists household-scoped `import_review_sessions` and normalized
`import_review_drafts` between extraction and the existing review/commit
pipeline. They are ordinary local-first entities in the outbox, change feed,
conflict, and initial-sync manifest. Opening a session re-runs validation,
rules, duplicates, and transfer matching against current device state while
preserving explicit edits and stable transaction IDs. Source bytes are never
stored. Financial rows are created only by explicit commit; deterministic IDs
and completion reconciliation make interrupted or concurrent commit retry safe.

## BETA-08G1 deferred final import identity

SQLite v25 separates durable review identity from account-dependent financial
identity. `ImportReviewDraft.id` and source identity exist from ingestion;
`deterministic_transaction_id` and its account binding may both be null until a
destination account is selected. Finalization calls the single extracted
BETA-08B UUIDv5 implementation. Account changes invalidate pending analysis,
while completed transaction IDs remain immutable. Web mirrors this domain
model. At the G1 checkpoint, no Telegram component had yet been introduced.

## BETA-08H Telegram boundary

Telegram is a server transport into existing BETA-08G/G1 Inbox entities, not a
financial subsystem. The authenticated connection function manages pairing;
the externally callable webhook authenticates with its dedicated Telegram
secret and uses service authority only after resolving an active connection.
Exact bytes are transient. Existing sync delivers normalized unresolved drafts
to devices, and only the Dart review/commit architecture may create finance.

## BETA-08I derived financial statements

Statements follow a one-way derived-data boundary:

`financial repositories/services -> FinancialStatementGenerator -> immutable FinancialStatement -> controller/screen -> FinancialStatementPdfRenderer`.

The generator reuses account balance, report summary, budget, tithe, and
canonical-transfer primitives. Widgets and the PDF renderer do not query
repositories or redefine accounting rules. Statements are generated on demand
and introduce no SQLite table, sync entity, backup payload, or Supabase object.
The renderer is local/offline and uses the existing portable save abstraction.

## BETA-08J read-only data health

Health Check follows `local stores → read-only snapshot → HealthCheckService →
immutable report → controller → screen`. The service reuses established
balance and canonical-transfer domain semantics; widgets contain neither SQL
nor financial validation rules. Diagnostic runs are transient and never sync,
repair, retry, resolve, reconnect, or persist. Local structural health remains
separate from cloud availability. SQLite stays v25, backup stays v4, and no
Supabase object is added. See `DATA_HEALTH_DIAGNOSTICS.md`.

## BETA-08K cloud durability and bootstrap

Native SQLite remains the working replica and Supabase remains the durable
shared record copy for linked households. New devices reuse active-membership
discovery and the BETA-04B stable-snapshot/staging/atomic-activation protocol;
they never copy a database file or create a second sync channel. The
presentation controller selects among authorized hosted manifests, while the
existing coordinator retains single-flight, cursor, outbox, retry, and
conflict authority. See `CLOUD_DURABILITY_AND_DEVICE_BOOTSTRAP.md`.
