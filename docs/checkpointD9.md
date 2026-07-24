1. CHECKPOINT_D9_COMPLETE.md
   Create:
   notepad docs\CHECKPOINT_D9_COMPLETE.md
   Paste:

# Pilgrim Tracker — Development Checkpoint

## Checkpoint

D9 is fully complete.

Last verified baseline:

- Flutter analyzer: clean
- Full test suite: 132 tests passed
- SQLite schema version: 7
- Platform tested: Windows CMD / Flutter desktop test environment
- Application project path: `D:\ExpenseTracker`

## Current Product

Pilgrim Tracker is a Flutter expense and asset-management application.

The application currently supports:

- ordinary income and expense transactions
- transfers
- asset conversions
- concrete asset definitions
- gold holdings
- stock holdings
- cryptocurrency definitions
- inventory definitions
- manual market prices
- Alpha Vantage online market pricing
- weighted-average asset cost
- partial asset sales
- realized gains
- unrealized gains
- asset portfolio dashboard
- soft-delete and local persistence
- SQLite migration compatibility

## Current Main Architecture

### Transactions

`Transaction` supports:

- `quantity`
- `unit`
- `unitPrice`
- `assetDefinitionId`
- `assetName`
- `assetSymbol`
- `assetAction`

The stable link is:

````text
Transaction.assetDefinitionId
    -> AssetDefinition.id
Transaction snapshots remain stored:
asset name
asset symbol
action
quantity
unit
unit price
This means historical transactions remain readable even if the linked asset definition is edited or archived.
Asset Definitions
AssetDefinition currently contains:
final String id;
final String displayName;
final AssetKind kind;
final String? symbol;
final String? providerCode;
final String? providerSymbol;
final String? exchangeCode;
final String currencyCode;
final String unit;
final int lotSize;
final bool onlinePricingEnabled;
final DateTime createdAt;
final DateTime updatedAt;
final DateTime? deletedAt;
final int version;
final String deviceId;
final String syncStatus;
Important getters include:
normalizedSymbol
normalizedProviderCode
normalizedProviderSymbol
normalizedExchangeCode
normalizedCurrencyCode
normalizedUnit
quoteSymbol
marketPriceKey
Current Default Asset Definitions
The valid default definitions are:
Gold Holdings
Bitcoin Wallet
Inventory
Generic Stock Portfolio is not a concrete persisted AssetDefinition.
Each stock must have its own definition, for example:
Display name: Bank Central Asia
Kind: stock
Symbol: BBCA
Provider code: ALPHA_VANTAGE
Provider symbol: BBCA.JK
Exchange: IDX
Currency: IDR
Unit: share
Lot size: 100
The old string Stock Portfolio may still exist in compatibility paths, but it must not be treated as a real tradable stock definition.
Completed Development Milestones
D1
Extracted AssetKind
Added AssetDefinition
Added repository abstraction
Added mapping, validation, and copy tests
D2
Added SQLite version 6
Added asset_definitions
Added repository persistence
Added migration and persistence tests
D3
Added default definitions
Added AssetDefinitionController
Added initialization and controller tests
D3.1
Removed generic Stock Portfolio from persisted default definitions
D4
Connected asset-definition repository and controller to AppShell
Preserved legacy conversion names temporarily
D5
Added Asset Management screen
Added create, edit, and soft-delete behavior
Added Manage Assets button to Assets dashboard
D6
Asset Conversion now accepts List<AssetDefinition>
Stock ticker comes from the concrete definition
Unit comes from the concrete definition
Quick Add also uses concrete definitions
Transactions preserve asset snapshots
D7
Added Transaction.assetDefinitionId
Added SQLite version 7
Added transactions.asset_definition_id
Added v6 to v7 migration
Preserved legacy transactions with a null definition ID
D8
Portfolio calculator accepts asset definitions
Holdings are grouped primarily by assetDefinitionId
Kind, unit, symbol, and lot size come from definitions
Legacy transactions still use snapshot fallback
Fully sold positions now contribute to total realized gain
D9
D9A
AssetHolding now includes:
assetDefinitionId
providerCode
providerSymbol
currencyCode
onlinePricingEnabled
It also exposes:
normalizedProviderCode
normalizedProviderSymbol
normalizedSymbol
normalizedCurrencyCode
normalizedUnit
quoteSymbol
D9B
Online stock pricing now requests the provider symbol.
Example:
Display symbol: BBCA
Provider symbol: BBCA.JK
Request symbol: BBCA.JK
Cache asset key: BBCA
Legacy stock transactions continue using their stored ticker.
D9C
Online quotes are validated before being cached.
Validation includes:
supported provider
positive price
valid minor-unit scale
currency compatibility
unit compatibility
returned symbol compatibility
Invalid quotes do not replace the existing cache.
D9D
Cache and manual-price consistency are complete.
Current behavior:
failed refresh preserves the previous cached price
online refresh replaces the same asset key rather than duplicating it
manual price uses the holding currency and unit
portfolio ignores cached prices with mismatched currency
portfolio ignores cached prices with mismatched unit
legacy cached prices remain supported
Current Pricing Flow
AssetDefinition
    display symbol: BBCA
    provider symbol: BBCA.JK
        ↓
AssetHolding.quoteSymbol
        ↓
AssetPriceController
        ↓
Alpha Vantage request: BBCA.JK
        ↓
MarketQuote validation
        ↓
AssetMarketPrice.assetKey: BBCA
        ↓
Portfolio price matching
Important Current Database Details
SQLite schema version:
7
The transactions table includes:
asset_definition_id
asset_name
asset_symbol
asset_action
quantity
unit
unit_price
The asset_definitions table includes provider, currency, unit, and lot-size metadata.
asset_market_prices uses:
asset_key
symbol
price_minor
minor_unit_scale
currency_code
unit
quoted_at
source
is_delayed
is_manual
updated_at
Known Test Warning
Migration tests print:
You are changing sqflite default factory.
This warning is currently harmless.
It appears because tests assign:
databaseFactory = databaseFactoryFfi;
The migrations and full test suite still pass.
Latest Verification
flutter analyze
No issues found

flutter test
132 tests passed

---

# 2. `ROADMAP_D10_TO_D14.md`

Create:

```bat
notepad docs\ROADMAP_D10_TO_D14.md
Paste:
# Pilgrim Tracker — Locked Roadmap D10 to D14

This roadmap is currently locked.

Do not expand the main scope until D14 is complete.

## D10 — Foreign Currency Asset Model and FX Pricing

### D10A — Foreign-Currency Domain Model

Add:

```dart
AssetKind.foreignCurrency
Add initial concrete definitions:
US Dollar Cash
Symbol: USD
Unit: USD
Valuation currency: IDR
Online pricing: enabled
Provider: ALPHA_VANTAGE
FX pair: USD/IDR
Singapore Dollar Cash
Symbol: SGD
Unit: SGD
Valuation currency: IDR
Online pricing: enabled
Provider: ALPHA_VANTAGE
FX pair: SGD/IDR
Required updates:
asset-kind enum
asset-definition validation
default asset definitions
asset-management form defaults
icons and labels
portfolio kind handling
Quick Add compatibility mapping
tests for entity mapping and defaults
D10B — FX Repository Contract
Extend AssetPriceRepository with an FX method such as:
Future<MarketQuote> fetchForeignExchangeRate({
  required String fromCurrency,
  required String toCurrency,
});
Implement Alpha Vantage exchange-rate retrieval using:
CURRENCY_EXCHANGE_RATE
The returned quote should represent:
price: IDR per one unit of foreign currency
currencyCode: IDR
unit: USD or SGD
symbol: USD/IDR or SGD/IDR
D10C — Asset Price Controller FX Support
Add online refresh handling for:
AssetKind.foreignCurrency
Examples:
USD holding -> request USD/IDR
SGD holding -> request SGD/IDR
Validate:
source currency
valuation currency
returned unit
returned pair
positive rate
valid scale
D10D — UI and Regression
Update:
Asset Management icons and labels
Assets dashboard quantity formatting
selected-asset summary
manual price labels
online refresh availability
portfolio tests
pricing tests
default-definition tests
D11 — Foreign Currency Conversion and Valuation
Support buying and selling foreign currency.
Example purchase:
Cash paid: Rp16,200,000
Asset received: USD 1,000
Average cost: Rp16,200 per USD
Example valuation:
Current rate: Rp16,450 per USD
Market value: Rp16,450,000
Unrealized gain: Rp250,000
Example partial sale:
Quantity sold: USD 400
Sale rate: Rp16,600 per USD
Average cost: Rp16,200 per USD
Realized gain: Rp160,000
Required work:
Asset Conversion supports foreign currency
quantity formatting supports decimal currencies
FX unit price is IDR per foreign-currency unit
portfolio calculates weighted average
partial sales calculate realized gain
market valuation uses FX cache
tests for USD and SGD purchases and sales
D12 — Transaction Safety and Accounting Accuracy
Add:
oversell validation
fee handling
spread handling
rounding rules
lot-size validation
currency precision rules
clearer validation errors
Oversell example:
Holding: USD 1,000
Requested sale: USD 1,500
Result: rejected
Fee modes:
Capitalize into cost basis
Record as separate expense
Deduct from sale proceeds
Spread support should distinguish:
Purchase rate
Market rate
Sale rate
D13 — Asset Management Finalization
Complete the Asset Management experience.
Add:
search
filtering by asset kind
duplicate symbol validation
duplicate provider-symbol validation
archive and restore
edit protection for linked definitions
provider configuration checks
currency and unit presets
better create/edit forms
safe retirement of obsolete default seed IDs
The obsolete fixed seed ID that may need cleanup is:
asset-stock-portfolio
Do not remove historical transactions.
Only retire the obsolete persisted definition when its fixed ID matches the retired seed.
D14 — Release Hardening
Final work:
full regression suite
migration verification
Chrome runtime smoke test
Windows runtime smoke test
local database reopen verification
manual-price verification
online quote verification
documentation update
architecture decision update
roadmap update
progress update
continuation prompt update
remove dead compatibility paths where safe
inspect and reduce test-only sqflite warnings if practical
D14 completion criteria:
flutter analyze -> clean
flutter test -> all tests passed
Chrome runtime -> passed
Windows runtime -> passed
SQLite migration -> passed
USD flow -> passed
SGD flow -> passed
Stock flow -> passed
Gold flow -> passed
Legacy transaction flow -> passed
Deferred Advanced Assets
These are intentionally deferred until after D14:
mutual funds
ETFs with specialized behavior
bonds
sukuk
deposits
property
vehicles
receivables
silver
platinum
collectibles
These may become D15 or later.

---

# 3. `NEXT_PROMPT_D10.md`

Create:

```bat
notepad docs\NEXT_PROMPT_D10.md
Paste:
# Continuation Prompt — Start D10

I am continuing a Flutter project located at:

```text
D:\ExpenseTracker
The app is called Pilgrim Tracker.
Please continue from the following verified checkpoint:
Current milestone: D9 complete
SQLite schema: version 7
flutter analyze: clean
flutter test: 132 tests passed
Read these project checkpoint files first:
docs\CHECKPOINT_D9_COMPLETE.md
docs\ROADMAP_D10_TO_D14.md
docs\PROJECT_WORKFLOW.md
Important Architectural Decisions
A generic Stock Portfolio is not a concrete tradable asset definition.

Every stock has its own definition.

Example:
Bank Central Asia
Symbol: BBCA
Provider symbol: BBCA.JK
Exchange: IDX
Currency: IDR
Unit: share
Lot size: 100
Transactions store both:
assetDefinitionId
and historical snapshots:
assetName
assetSymbol
assetAction
unit
quantity
unitPrice
Portfolio matching prioritizes:
Transaction.assetDefinitionId
and falls back to transaction snapshots for legacy records.
Online stock pricing uses:
AssetDefinition.providerSymbol
Example:
request symbol: BBCA.JK
cache asset key: BBCA
Invalid online quotes must never replace valid cached prices.

Foreign-currency assets are now part of the locked D10 to D14 roadmap.

Immediate Next Task
Start D10A:
AssetKind.foreignCurrency
USD and SGD concrete asset definitions
domain and UI support
regression tests
Before proposing code changes, inspect the current files:
type lib\features\assets\domain\entities\asset_kind.dart
type lib\app\data\default_asset_definitions.dart
powershell -Command "Get-Content 'lib\features\assets\domain\entities\asset_definition.dart' | Select-Object -First 220"
findstr /s /n /c:"AssetKind." lib\*.dart test\*.dart
powershell -Command "Get-Content 'lib\features\assets\presentation\screens\asset_management_screen.dart' | Select-Object -Skip 730 -First 120"
powershell -Command "Get-Content 'lib\features\transactions\presentation\quick_add\quick_add_controller.dart' | Select-Object -Skip 350 -First 180"
Locate default-definition tests:
dir /s /b test\*default*asset*test.dart
Also inspect the current tests for:
type test\asset_definition_test.dart
type test\asset_portfolio_calculator_test.dart
type test\asset_price_controller_test.dart
D10A Expected Model
Add:
AssetKind.foreignCurrency
Suggested concrete definitions:
US Dollar Cash
ID: asset-usd
Kind: foreignCurrency
Symbol: USD
Provider code: ALPHA_VANTAGE
Provider symbol: USD/IDR
Currency code: IDR
Unit: USD
Lot size: 1
Online pricing: true
Singapore Dollar Cash
ID: asset-sgd
Kind: foreignCurrency
Symbol: SGD
Provider code: ALPHA_VANTAGE
Provider symbol: SGD/IDR
Currency code: IDR
Unit: SGD
Lot size: 1
Online pricing: true
Clarify during implementation whether provider symbols should be stored as:
USD/IDR
SGD/IDR
or represented through dedicated source and target currency metadata.
Prefer a clean domain model over parsing arbitrary display strings.
Work in Small Batches
Suggested sequence:
D10A.1
- AssetKind.foreignCurrency
- exhaustive switch fixes
- tests

D10A.2
- USD and SGD definitions
- default seed tests

D10A.3
- Asset Management form defaults and icons
- widget tests

D10B
- FX repository contract
- Alpha Vantage implementation
After every batch run:
dart format <changed files>
flutter analyze
flutter test <focused tests>
flutter test
Do not move to the next batch unless analyzer and tests are green.
Important User Preference
Give exact Windows CMD commands.
Prefer:
complete replacement blocks
precise find-and-replace instructions
small batches
expected test totals
Do not provide vague pseudocode.
Do not silently modify unrelated behavior.
The existing test warning about changing the sqflite default factory is known and currently harmless.

---

# 4. `PROJECT_WORKFLOW.md`

Create:

```bat
notepad docs\PROJECT_WORKFLOW.md
Paste:
# Pilgrim Tracker — Project Workflow

## Environment

Project:

```text
D:\ExpenseTracker
Shell:
Windows CMD
Framework:
Flutter / Dart
Preferred Development Style
Work in small batches.
Each batch should contain:
file backup
exact edit instructions
formatting
analyzer verification
focused tests
full test suite
runtime smoke test when relevant
Backup Command Pattern
Run backup and format commands separately.
Correct:
copy source.dart source.dart.bak_batch
dart format source.dart
Incorrect:
copy source.dart source.dart.bak_batchdart format source.dart
Commands must not be pasted together without a line break.
Required Verification
After source changes:
dart format <changed files>
flutter analyze
flutter test <focused test files>
flutter test
For UI milestones:
flutter run -d chrome
When desktop behavior matters:
flutter run -d windows
Current Known Warning
Migration tests may print:
You are changing sqflite default factory.
The warning currently comes from test setup using:
databaseFactory = databaseFactoryFfi;
Do not treat it as a failure when:
All tests passed
Architectural Safety Rules
Transactions
Never remove transaction snapshots merely because a stable definition ID exists.
Keep:
asset_definition_id
asset_name
asset_symbol
asset_action
quantity
unit
unit_price
Asset Definitions
Every tradable stock must be concrete.
Valid:
Bank Central Asia / BBCA / BBCA.JK
Invalid as a concrete stock:
Stock Portfolio
Legacy Compatibility
Transactions without assetDefinitionId must continue working.
Fallback sources may include:
asset name
asset symbol
account path
transaction title
unit
Cache Identity
Stock request and cache identity may differ.
Example:
provider request: BBCA.JK
cache key: BBCA
Do not change cache identity to the provider symbol without a migration and compatibility plan.
Pricing Validation
Before saving an online quote, validate:
positive price
minor-unit scale
currency
unit
provider symbol
supported provider
Failed refreshes must preserve old cache records.
Foreign Currency
Foreign currency should be modeled as an owned quantity.
Example:
quantity: 1,000
unit: USD
price: IDR per USD
valuation currency: IDR
Do not model USD or SGD merely as bank-account labels.
Documentation Update Points
After each completed milestone, update:
docs\CHECKPOINT_D9_COMPLETE.md
docs\ROADMAP_D10_TO_D14.md
docs\NEXT_PROMPT_D10.md
After D10 begins, create a newer checkpoint file rather than overwriting history, for example:
CHECKPOINT_D10_COMPLETE.md

---

## Save and verify the files

Run:

```bat
dir docs
````
