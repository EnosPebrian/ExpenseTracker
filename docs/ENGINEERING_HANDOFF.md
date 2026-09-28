# Pilgrim Tracker — Engineering Handoff

This file is the durable resume point for Codex.

Update it whenever an engineering session materially changes state, especially before stopping, after validation, and after Git push.

---

## Current active work item

PT-BETA-09C — Deterministic CSV Date Handling.
Authority: `POST_BETA08N_PROGRAM_AUTHORIZATION.md`; R7 is already COMPLETE.

09C resume point: implementation began from clean `1bf704fea93f54924e5d2bb54bfcadf802f1ba6a`
(09A durable handoff pushed). Shared date-column policy now drives ordinary and
brokerage detection; session examples/help added to both mapping UIs; exported
economic dates use ISO calendar dates (audit timestamps unchanged). Focused
tests PASS 106/106 in pilgrim-beta09c-focused-final.log. The sole stale historical
expectation labeled invalid 2026-02-30 as detected ISO; updated to null while
preserving unresolved date and no-commit checks. No schema/Supabase change.
Final serial gates PASS: analyzer clean; full Flutter 1052/1052; Web, Windows
debug and Android debug APK PASS (unchanged file_picker Kotlin warning).
Logs pilgrim-beta09c-{full,web,windows,android}.log in system TEMP.
Diff reviewed; git diff --check PASS. Next: publish 09C, then begin 09B1.

## Current state

`IN_PROGRESS` — 09C inspection starts from validated/pushed 09A. Clean 09A starting
main/ origin/main: `35ee692429499a25bf2cd6e0213e24ddbdbdf0c3`; fetch succeeded.
Feature freeze temporarily lifted only for 09A, 09C, 09B1 and 09B2; execute
in that order, validating/committing/pushing each. R7 owner acceptance remains
PENDING. Only the authorized 09A dev migration has now been deployed.

09A implemented cursor-prefix safety, continued independent sync during
conflict, dependency-ordered draining, dirty-row protection, durable resolution
intent/retry, explicit merge UI and diagnostics. See BETA09A_ENGINEERING_ANALYSIS.
SQLite 29 and backup v8 unchanged. New deployed migration:
`20260927100120_beta09a_sync_serialization.sql` (CLI-generated filename),
serializing existing push/resolution functions with initial-sync household lock.

Validation so far: clean local replay PASS; focused pgTAP 17/17; full pgTAP
360/360 (18 files). Local lint matches unchanged hosted begin_initial_download
dynamic-SQL finding. Initial 09A tests 14/14; settlement persistence 3/3;
historical category+brokerage tests 32/32. Broader 152-test group had one stale
settlement remote-overwrite assertion, now repaired to verify preservation of
pending local data followed by acknowledgement/pull with no echo. Both focused
files then passed 17/17. No assertions about accounting were weakened.
Final focused group passed 152/152; follow-up sync/status group passed 29/29;
analyzer passed. First full run: 1036 passed, two budget-copy fixture failures
because a remote archive attempted to overwrite unacknowledged category creation.
Fixture now acknowledges that creation before remote archival; all financial/UI
assertions unchanged; budget-copy focused file passed 10/10. Analyzer + full
suite rerun passed the budget cases. A final UI review added persistence-aware
Review conflicts visibility while offline; that edit occurred during the run,
so its new regression saw an older compiled widget (1038 passed / one failed).
An overlapping focused invocation also hit the in-use sqlite3.dll; no cleaning
or production rollback was performed. Source is now frozen and serial focused,
analyzer and full gates are running (pilgrim-beta09a-final-serial.log).
Final serial gates now PASS: focused 15/15; analyzer clean; full 1039/1039.
All three builds PASS: Web, Windows debug, Android debug APK (unchanged
file_picker Kotlin warning). Source is frozen.
Hosted gates PASS on 2026-09-28: five non-empty dumps and verified SHA-256 at
pre-beta09a-20260928-140105; exact one-migration dry-run/push; history aligned;
24 public-table counts/content fingerprints unchanged; RLS/policies/ACLs and
security advisor details unchanged; expected function locks present. Hosted lint
retains the same known baseline issue.
09A commit/push PASS: `92c9381270fdff91dd89d3262689770cdc9c8035` on main;
HEAD == origin/main and clean status verified. This follow-up records publication
and activates 09C. Next: shared whole-column date detection and session-level
examples/choice across ordinary and brokerage CSV, preserving explicit formats,
identities and financial semantics. Do not restart R7 or repeat 09A gates.
Hosted read-only preflight: intended project positively identified as
pilgrim-tracker-dev / jylclfebdeaywfdwabph. Migration list has exactly one pending
09A migration; previous history through 20260921144802 matches. Pre-security
advisor: INFO rls_enabled_no_policy(5); WARN function_search_path_mutable(2),
anon_security_definer_function_executable(3),
authenticated_security_definer_function_executable(25),
auth_leaked_password_protection(1). Compare post-deploy, do not conflate these
existing warnings with a new regression. Final comparison was unchanged.

## PT-BETA-08N-R7 engineering evidence — 2026-09-27

```text
work item: PT-BETA-08N-R7
state: ENGINEERING COMPLETE / BLOCKED_OWNER
scope: brokerage import review-session replanning only
root cause: review actions finalized one row against persisted history instead of replanning the statement against an evolving simulated sequence
instrument resolution: one explicit Map/Create propagates by normalized symbol + currency only
planning order: activity date, then stable source row number
simulation: persisted transactions plus earlier included planned postings
validation authority: AssetTradeValidator unchanged; oversells remain blocked
commit behavior: one deterministic instrument definition; atomic import unchanged
reimport behavior: exact source/account import creates no duplicate financial effect or instrument
focused tests: 97/97 PASS
flutter analyze: PASS
full Flutter suite: 1024/1024 PASS
web build: PASS
Windows debug build: PASS
Android debug APK build: PASS (unchanged file_picker forward-looking Kotlin warning)
schema / Supabase / backup changes: none
owner acceptance: PENDING / NOT RUN
feature freeze: active
implementation/test/docs commit: 3aa15f67a970555e506bcd383a9fbbf2a0560e2f
push result: origin/main succeeded
post-push status: HEAD == origin/main; clean before this durable handoff record
```

## Latest pushed engineering baseline

```text
branch: main
remote: origin
commit: 3aa15f67a970555e506bcd383a9fbbf2a0560e2f
message: fix: replan brokerage import sessions
push: origin/main succeeded
HEAD == origin/main: yes
post-push worktree: clean
```

## Latest owner evidence — 2026-09-23

```text
work item: PT-BETA-08N-R6-R1 owner acceptance closure
state: targeted acceptance PASS / remaining physical-device matrix DEFERRED BY OWNER / NOT EXECUTED
owner fixture: real 125-row Stockbit/RDN CSV on Windows
review result: Invalid 0; Unresolved 0; 71 fractional-IDR values reached HALF_UP review with source provenance
commit result: 86 selected events imported; 16 financial rows; zero instruments
settlement result: BUY_SETTLEMENT / SELL_SETTLEMENT imported as zero-financial-effect evidence
Interest result: recognized as Interest without instrument requirement
duplicate policy: 39 duplicate/review candidates retained for review and were not blindly imported; not an import failure
remaining owner checks: DEFERRED BY OWNER / NOT EXECUTED
production/schema/Supabase/backup changes: none
feature freeze: active; no new product development authorized
closure commit: 5f1fb7804449f35e103a84fb03665f48e065fefe
push result: origin/main succeeded
```

## Engineering verification evidence — 2026-09-23

```text
work item: PT-BETA-08N-R6-R1
state: COMPLETE / BLOCKED_OWNER
branch: main
starting HEAD/origin: 3cf7e52b1c2d822cc22b639efc59200ab4ae063e; clean
owner runtime: D:\ExpenseTracker\build\windows\x64\runner\Release\pilgrim_tracker.exe
stale artifact evidence: Release data\app.so built 2026-09-16; R6 implementation commit authored 2026-09-22
diagnosis: current source already intercepts IDR brokerage values before generic CsvMoneyParser precision enforcement; the running release did not contain R6
regression: verified 14-column RDN row shape with a rejecting generic parser; 42563.75 -> 42564, exact provenance retained, approval required, no precision/positive-gross issue, settlement creates no transaction
production changes: none
schema / Supabase / backup changes: none
focused tests: 84/84 PASS
analyzer: PASS
full Flutter: 1020/1020 PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged file_picker Kotlin warning
artifacts: build\windows\x64\runner\Debug\pilgrim_tracker.exe; build\app\outputs\flutter-apk\app-debug.apk
git diff --check: PASS
next exact action: owner closes the stale Release app, launches the current Debug artifact (or rebuilds Release from current main), and reruns the 125-row CSV
owner acceptance: PENDING / NOT RUN
implementation/test commit: 69615b6
push result: origin/main succeeded
```

## Previous session evidence — 2026-09-22

```text
work item: PT-BETA-08N-R6
state: COMPLETE / BLOCKED_OWNER
branch: main
starting HEAD/origin baseline: 67bec5323cc0e55552feb1afcfc7cf51358519fa; clean before durable-state edits
owner evidence: Windows brokerage review screenshots plus the supplied 125-row CSV
aggregate diagnosis: 71/125 rows contain non-zero fractional IDR; counts by activity are BUY_SETTLEMENT 28, SELL_SETTLEMENT 10, DIVIDEND 1, INTEREST 16, TAX 16
root cause: CsvMoneyParser intentionally assigns IDR zero fractional digits; persistence uses integer currency minor units and accepted docs prohibit silent rounding
separator observation: choosing period/none resolves separator ambiguity but correctly exposes the excessive-precision error
implementation changes: brokerage-only exact IDR parser, review approval state/UI, commit defense, durable note provenance and focused tests
schema/migration/hosted changes: none
tests/builds: focused brokerage tranche 39/39 PASS; analyzer/full suite/builds pending
architecture resolution: explicit reviewed HALF_UP whole-rupiah rounding; original source values preserved in durable note provenance
implementation: exact brokerage-only parser, canonical period separator, session approval gate, rounded review display, commit guard and deterministic audit metadata
focused tests: brokerage import/settlement tranche 39/39 PASS
analyzer: PASS
full Flutter: 1019/1019 PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged file_picker warning
git diff --check: PASS
SQLite / backup: 29 / v8 unchanged
Supabase / hosted: untouched; no SQL change
next exact action: owner reruns the 125-row Windows review, enables Trusted Stockbit / IDX for unknown tickers, approves HALF_UP rounding once, and verifies import/re-import
owner acceptance: PENDING / NOT RUN
implementation commit: 542bc485d8a00b222e6f028d101acb41c239ac86
push result: origin/main succeeded
post-push status: clean before this durable-state follow-up
```

## Latest completed engineering state

```text
PT-BETA-08N-R5 settlement + Interest hosted rollout: ENGINEERING/HOSTED COMPLETE
SQLite: 29
backup format: v8
focused Flutter: 123/123 PASS
full Flutter suite: 1014/1014 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
local Supabase clean replay: PASS
focused pgTAP: 13/13 PASS
full pgTAP: 339/339 PASS across 17 files
git diff --check: PASS
Supabase migrations 20260915004307 and 20260916000331: DEPLOYED
hosted business counts preserved: yes
ACL migration 20260921144802: DEPLOYED
authenticated settlement ACL: SELECT/INSERT/UPDATE yes; DELETE no
post-deployment settlement + Interest verification: 38/38 PASS
hosted business-count and migration-history verification: PASS
fresh recovery point: pre-beta08nr5-acl-20260921-215323 (five non-empty dumps, SHA-256 recorded)
owner acceptance: PENDING / NOT RUN
feature freeze: active
BETA-08N1-R2 date/instrument review: VALIDATED / PUSHED
focused Flutter: 25/25 PASS
full Flutter suite: 1002/1002 PASS
analyzer: PASS
diff checks: PASS
builds: not required/rerun for this bounded item
remaining scope: owner runtime acceptance PENDING / NOT RUN
owner runtime acceptance: NOT RUN
BETA-08N1 brokerage CSV compatibility repair: VALIDATED / PUSHED
repair commit: 2684254c814d1bef781ffe707ab3e625c08c2f60
focused Flutter: CSV parser 27/27; brokerage import 15/15 PASS
full Flutter suite: 992/992 PASS
analyzer/builds/diff: PASS
push: origin/main succeeded on 2026-09-14 (included in R2 publication)
BETA-08N Investments UI navigation: COMPLETE
first-class destination: after Assets on desktop and mobile
sections: Overview, Brokerage Accounts, Holdings, Trades, Statements, Performance
focused Flutter: 33/33 PASS
full Flutter suite: 989/989 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
git diff --check: PASS
SQLite: 28
backup format: v7
SQL/Supabase change: none
owner visual acceptance: PENDING / NOT RUN
feature freeze: active
BETA-08N hosted rollout: PASS
BETA-08M0 migration 20260908124412: DEPLOYED
BETA-08N0 migration 20260910054452: DEPLOYED
local focused pgTAP: M0 23/23; N0 24/24 PASS
local full pgTAP: 314/314 PASS
hosted business counts preserved: yes
new severe advisor finding: no
owner acceptance: PENDING / NOT RUN
feature freeze: active
BETA-08N1 implementation: COMPLETE
SQLite: 28
backup format: v7
BETA-08N1 Supabase migration: none
focused N1 tests: 14/14 PASS
focused N0 regression: 14/14 PASS
affected import/investment tranche: 120/120 PASS
full Flutter suite: 983/983 PASS
analyzer: PASS
builds: Web, Windows debug, Android debug APK PASS
git diff --check: PASS
remaining failures: 0
```

## Exact next action

Owner reruns the real 125-row RDN CSV acceptance on Windows, then completes the
remaining Windows/Android matrix in `docs/BETA08N_OWNER_ACCEPTANCE.md`. Do not
mark acceptance complete without owner execution and do not create a feature
item while the feature freeze remains active.

R3 completion context:

R3 implementation is preserved and undergoing validation. Starting main/origin:
6dd013c283bece6a903bf9a9d7570d618bbec49e. SQLite 29, backup v8;
new migration 20260915004307 remains UNDEPLOYED.
Domain evidence tests 5/5, brokerage focused group 30/30, enhanced native/web
persistence/migration/backup/remote-apply tests 3/3 passed. Earlier affected
persistence/N0/Health Check group passed 34/34. Local clean Supabase replay
passed, focused pgTAP 12/12 and full pgTAP 326/326 passed.
Final focused brokerage/settlement group: 33/33 PASS. Analyzer: PASS after
13 missing-braces style fixes, with no suppression or test weakening.
Full Flutter suite: 1010/1010 PASS. Web, Windows debug and Android debug
builds PASS (unchanged file_picker Kotlin compatibility warning).
Local security advisor: no errors; two historical mutable-search-path warnings
for prevent_book_id_change / prevent_book_identity_change (unchanged).
Latest review explicitly prevents silently removing unavailable historical
trade links; user must confirm removal or cancel. Changed Dart files formatted.
Implementation commit and normal push succeeded: 8ac408b155ae5e3d3db7dd71152e5fa4c067effb.
HEAD == origin/main and clean worktree verified before this documentation update.
Next: owner-authorized hosted rollout/runtime acceptance, or architect resolution
of the separate Interest accounting policy. Do not invent another feature item.
Owner acceptance remains NOT RUN. This follow-up records completion on 2026-09-16.

Date/instrument review changes are published under the owner's 2026-09-14
commit/push instruction. This documentation-only follow-up records the verified
implementation push and clean post-push status. Settlement semantics are resolved;
Interest remains separate in ARCH-20260914-01; do not reinterpret these
labels as trades, dividends or fees. Owner runtime acceptance remains NOT RUN.

## PT-BETA-08N-RC rollout result

```text
project: pilgrim-tracker-dev (jylclfebdeaywfdwabph)
authorized deployed chain: 20260908124412 -> 20260910054452
clean local replay: PASS
focused pgTAP: M0 23/23; N0 24/24 PASS
full pgTAP: 314/314 PASS across 15 files
recovery point: pre-beta08nrc-20260911-172323 (five non-empty hashed artifacts)
hosted deployment: PASS
hosted migration history: exact through 20260910054452
business row preservation: PASS
RLS/ACL/sync verification: PASS
new severe advisor finding: no
owner acceptance: PENDING / NOT RUN
state: BLOCKED_OWNER
branch: main
documentation commit: 4e3e5384a2d37d7c44099a42af04aa1597acea47
push result: origin/main succeeded
post-push git status: clean
```

---

## Completed sprint records

### PT-BETA-08N1-R4 — Distinct Brokerage Interest Activity

```text
work item: PT-BETA-08N1-R4
verdict: COMPLETE
root cause / implementation: added distinct positive instrument-free Interest across the existing brokerage transaction, import, cash, performance, persistence, sync, backup and Health Check authorities; zero/negative values preserve sign and block
schema/version changes: SQLite 29 unchanged; backup v8 unchanged; one additive Supabase migration 20260916000331 created and remains UNDEPLOYED
focused tests: 123/123 PASS
full suite: 1014/1014 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged non-blocking file_picker warning
server/pgTAP: clean local replay PASS; focused 13/13 PASS; full 339/339 PASS across 17 files
git diff --check: PASS
owner acceptance status: PENDING / NOT RUN
branch: main
implementation commit: 1cd7543f0836e55f525b4fac4ec4039be31c8153
push result: origin/main succeeded
final git status: clean after implementation push; this durable-state record is the documentation follow-up
remaining limitations: settlement and Interest migrations remain undeployed; owner runtime acceptance pending; historical local lint false positive in begin_initial_download remains
next READY item: none; BLOCKED_OWNER under active feature freeze
```

### PT-BETA-08N-UI-R1 — Investment / Brokerage UI Navigation Gap

```text
work item: PT-BETA-08N-UI-R1
verdict: COMPLETE
root cause / implementation: the complete N0/N1 ledger was buried behind the desktop overflow/mobile More route and rendered as one undifferentiated page; Investments is now first-class after Assets with six responsive sections over existing authorities
files changed: application destination/router/shell/navigation composition, Investments presentation widgets, account-editor initial type support, focused navigation/investment regressions, and targeted architecture/progress/limitations/checkpoint/handoff docs
schema/version changes: none; SQLite 28; backup v7; no SQL/Supabase migration
focused tests: 33/33 PASS
historical regressions: included app navigation, BETA-08H destination index, and BETA-08N0 investment coverage
full suite: 989/989 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged non-blocking file_picker warning
server/pgTAP if applicable: not applicable; no SQL/Supabase change
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: fd5c03d42c4949eb8db9818ab01cd605da073eec
status/documentation commit if any: this durable-state record is included in the sprint Git completion
push result: pending explicit external push authorization; local main is ahead of origin/main
final git status: clean at implementation commit before PT-BETA-08N1-R1 repair began
remaining limitations: UTF-8 CSV statements only; no broker institution metadata, APIs, advanced return metrics, or cross-currency aggregation; owner visual/runtime acceptance pending
next READY item: none; PT-BETA-08N-RC remains BLOCKED_OWNER and feature freeze is active
```

### PT-BETA-08N1 — Brokerage Statement CSV Import

```text
work item: PT-BETA-08N1
verdict: COMPLETE
root cause / implementation: added a brokerage-specific reviewed CSV adapter over the authoritative N0 ledger; explicit mapping and unresolved activity/instrument review feed deterministic event/child identities and one atomic definition/transaction/transfer/outbox commit
files changed: brokerage import domain/planner/posting/commit/controller/UI, native/web atomic repositories, Investments entry point, focused tests, and targeted architecture/import/schema/sync/checkpoint/roadmap documentation
schema/version changes: none; SQLite 28; backup v7; no N1 Supabase migration
focused tests: 14/14 PASS
historical regressions: focused N0 14/14 PASS; affected import/investment tranche 120/120 PASS; final full suite 983/983 PASS
full suite: 983/983 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS with unchanged non-blocking file_picker warning
server/pgTAP if applicable: not applicable; N1 adds no SQL; no hosted action
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: 23a5e453c1856376b1b601859918134397d407e4
status/documentation commit if any: follow-up durable-state commit containing this record
push result: origin/main succeeded
final git status: clean after implementation push; durable-state update pending its follow-up commit
remaining limitations: CSV only; explicit exact instrument mapping; no cross-currency conversion; review state is in-memory; N0 hosted migration remains undeployed; owner acceptance pending
next READY item: none; accepted roadmap exhausted and feature freeze active
```

### PT-BETA-08N0 — Investment / Brokerage Ledger Foundation

```text
work item: PT-BETA-08N0
verdict: COMPLETE
root cause / implementation: added nullable brokerage attribution to the authoritative transaction ledger; reused existing asset, account, canonical-transfer, budget, Tithe, backup, and sync authorities
files changed: brokerage domain/service/UI, transaction/account/asset/reporting/backup/sync/health integration, SQLite v28 migration, one undeployed Supabase migration, focused Flutter/pgTAP tests, and targeted docs
schema/version changes: SQLite 27 -> 28; backup v6 -> v7; one additive Supabase migration remains undeployed
focused tests: 14/14 PASS
historical regressions: affected tranche 203/203 PASS
full suite: 969/969 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS
server/pgTAP if applicable: local reset PASS; focused 24/24 PASS; full 314/314 PASS; hosted deployment NOT RUN
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: 403dde8383f9e9d6e49ed7faa5e360f172527cf9
status/documentation commit if any: follow-up durable-state commit containing this record
push result: origin/main succeeded; HEAD == origin/main after implementation push
final git status: clean after implementation push; durable-state update pending its follow-up commit
remaining limitations: hosted migration undeployed; no broker CSV/API/extraction/trading/tax/advanced instruments; no cross-currency total; owner runtime acceptance pending
next READY item: PT-BETA-08N1, moved to IN_PROGRESS
```

### PT-BETA-08M-R1 — Category-commit compatibility repair

```text
work item: PT-BETA-08M-R1
verdict: COMPLETE
root cause / implementation: _prepareCategoryCommit treated every category ID as rule-backed; explicit Map provenance is now durable and only that path requires ImportRuleCategory stable-ID revalidation
files changed: BETA-08M category review/domain/controller/UI, native/web atomic repositories, focused tests, architecture/import/sync/checkpoint docs, and autonomy protocol docs
schema/version changes: none; SQLite 27; backup v6
focused tests: 294/294 PASS
historical regressions: included in 294/294; BETA-08B 9/9 and BETA-08L0 15/15 PASS
full suite: 954/954 PASS
analyzer: PASS
builds: Web PASS; Windows debug PASS; Android debug APK PASS
server/pgTAP if applicable: not applicable; no SQL/Supabase change
git diff --check: PASS
owner acceptance status: NOT RUN
branch: main
implementation commit: 1e5a97c0d3c458f4519ec7528494a3a80e438a77
status/documentation commit if any: follow-up durable-state commit containing this record
push result: origin/main succeeded
final git status: clean after implementation push; durable-state update pending its follow-up commit
remaining limitations: exact category matching only; pending Inbox state remains excluded from backup; owner runtime acceptance pending
next READY item: none; PT-AUTO-NEXT is BLOCKED_ARCHITECT by ARCH-20260910-01
```

---

## Codex session update template

```text
timestamp: 2026-09-14
work item: PT-BETA-08N1-R2
state: BLOCKED_ARCHITECT (posting behavior only; independent review work validated)
branch: main
prior implementation commit: 2684254c814d1bef781ffe707ab3e625c08c2f60
current branch tip: follow-up durable-state commit containing this record; origin/main remains 83274479a3e00bda92d8e700a6fd983fbee736b9
dirty files intentionally belonging to task: brokerage review date/model/planner/posting/commit/controller/UI, focused tests and targeted documentation
last completed substep: focused 25/25, analyzer and full suite 1002/1002 PASS; diff review complete
tests already run: brokerage automation 10/10; existing N1 15/15; full Flutter 1002/1002 PASS
current failing tests: none
root cause known?: date analysis was per-row with an epoch fallback; instrument creation required repeated row actions
next exact command/action: commit and push validated review changes; resolve ARCH-20260914-01 before new posting semantics
architecture escalation needed?: ARCH-20260914-01 for settlement/interest posting only
owner action needed?: accounting decision and runtime acceptance; Git push is authorized
```

---

## Sprint completion template

Append one record per completed work item:

```text
work item:
verdict:
root cause / implementation:
files changed:
schema/version changes:
focused tests:
historical regressions:
full suite:
analyzer:
builds:
server/pgTAP if applicable:
git diff --check:
owner acceptance status:
branch:
implementation commit:
status/documentation commit if any:
push result:
final git status:
remaining limitations:
next READY item:
```
