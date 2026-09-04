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

The D12 final engineering closure audit passed. Migration paths from versions
5, 7, 8, and 9 through version 10, combined accounting, fee-link lifecycle,
stock validation, and foreign-currency regression behavior are verified.

**D12 status: Complete.**

## D13 — Asset-management finalization

- D13A asset-definition integrity and duplicate protection: Complete.
- D13B archive/restore and linked-edit protection: Complete.
- D13C1 search, filters, sorting, presets, and UX finalization: Complete.
- D13C2 obsolete-seed retirement and D13 closure audit: Complete.

D13A adds normalized stock/exchange identity checks, stable non-stock market
identity protection, provider-code/symbol uniqueness across asset kinds, and
archived-definition conflict detection. Validation runs at save and seed time;
archive/restore UI was completed in D13B.

D13B adds transaction-derived usage, open-position archive protection,
same-row restore with complete D13A integrity checks, and read-only identity and
accounting fields for definitions linked to historical transactions. Archived
definitions remain available to historical portfolio resolution but are excluded
from new transaction selection.

D13C1 adds presentation-only local search, lifecycle/kind/pricing filters,
deterministic sorting, result counts, responsive empty states, and safe
create-form presets. Catalog state is not persisted, and presets remain subject
to D13A validation and D13B linked-field protection.

D13C2 permanently retires the exact `asset-stock-portfolio` system definition.
Fresh installations never seed it; unused or fully closed legacy rows are
soft-archived, while an open historical holding remains sell-only until it is
closed. Historical snapshots and portfolio accounting remain readable, and a
user-created definition with the same display name is unaffected.

The integrated D13 closure audit passed across integrity, lifecycle, linked
edits, catalog behavior, and legacy retirement. SQLite remains version 10.

**D13 status: Complete.**

## D14 — Regression, cleanup, documentation, and release hardening

**D14 status (2026-08-02): PASS — Ready for controlled private deployment by
Enos and Grace.**

The approved scope is private household use on Windows and Android with hosted
Supabase synchronization, encrypted backup and restore, and CSV export. It does
not claim public production launch, Play Store publication, enterprise use,
web production readiness, or third-party security certification.

- D14A persistence, migration, reopen, and integrated regression hardening:
  Complete.
- D14B platform runtime and release-candidate audit: Complete, with release
  gates still blocked.
- D14C permanent identity, branding, Android repair, signing readiness, and
  Android artifact generation: Complete, with runtime/signing gates open.

D14A verifies fresh version-10 creation, upgrades from versions 1, 3, 5, 7,
8, and 9, native close/reopen behavior, repeated bootstrap, native/web linked
fee atomicity, asset lifecycle persistence, and integrated accounting for gold,
stocks, cryptocurrency, inventory, USD, and SGD. Fresh-schema master-data index
parity and web transaction soft-delete timestamp parity were corrected.

The D14B audit confirmed a successful Windows release build/process startup and
a successful web build. At that checkpoint Android output was blocked by the
local NDK installation, interactive Windows smoke testing was incomplete,
Android runtime was unavailable, and permanent identity, icon, and signing
configuration remained outstanding.

The permanent Android and Windows identities and original cross-platform icon
are now applied. NDK r28c is repaired, and technical APK/AAB artifacts build
with the correct package, label, version, and SDK levels. They use an explicitly
opted-in debug certificate and are not Play-ready. Android runtime is
unavailable, while the post-clean Windows/web rebuild and Windows runtime proof
remain pending.

## Closed-beta sharing sequence

- **BETA-02 — Complete:** household, local members, ownership, attribution, and
  sync-ready local schema.
- **BETA-03 — Complete:** Supabase email OTP, PostgreSQL household membership,
  invitations, secure linking/acceptance, and Row Level Security authorization.
- **BETA-04A — Complete:** durable local outbox, idempotent/version-aware push,
  monotonic cursor pull, tombstones, durable conflicts, retry/recovery, and an
  explicit initial-sync guard.
- **BETA-04B — Complete locally:** controlled owner/empty-remote primary
  upload, stable staged secondary download, resume/cancel, integrity checks,
  and cursor handoff. Remote pgTAP execution awaits an available CLI/runtime.
- **BETA-04C:** conflict resolution, sync health, and Realtime wake-up are
  implemented locally; remote deployment verification remains.
- **BETA-05:** two-device acceptance testing with Enos and Grace.
- **BETA-06:** encrypted household backup, safe non-merge restore, CSV export,
  and recovery documentation implemented; owner acceptance remains required.

**Historical D14 Final status (2026-07-30): FAIL / open.** Owner-certificate preflight and
the Windows release build/startup pass, but the sole signed Android APK attempt
ended in a JVM native-memory crash. Signed APK/AAB artifacts, Android runtime,
interactive Windows portability/reopen, and the remaining owner acceptance
matrix were unresolved at that checkpoint. Subsequent owner evidence closed
those gates; the 2026-08-02 PASS above is authoritative.

## Post-D14 BETA-07A — Monthly category budgets

Implementation is complete but unreleased pending owner acceptance. It adds
shared monthly expense-category limits, derived progress and unbudgeted spend,
SQLite v21, synchronized tombstones/conflicts, backup format v2, and
`budgets.csv`. D14 remains historically complete and unchanged in scope.

## Post-D14 BETA-07B — Copy monthly budgets

Implementation is complete but unreleased pending owner acceptance. Users can
preview and explicitly copy active budget definitions from a selected source
month into the displayed target month. The only mode is add-missing: existing
target plans are preserved, unavailable categories are skipped safely, and
spending is never copied or rolled over. Local budget rows and ordinary linked
outbox entries commit atomically without a schema, backup-format, or Supabase
protocol change.

## Post-D14 BETA-07C — Deployment and owner acceptance

Deployment automation completed on 2026-08-03. Migration `202608020001` is
applied to the linked private Supabase project, local/remote histories agree,
81 pgTAP assertions pass, configured Windows/APK/AAB artifacts build, and the
APK verifies with the expected non-debug owner certificate. Owner runtime
acceptance subsequently closed BETA-07A, BETA-07B, BETA-07C, and corrective
BETA-07C2 on Windows and Android. BETA-07C1 is superseded by C2. Scope remains
controlled private deployment by Enos and Grace; D14 remains historically
complete.

## Post-D14 BETA-08 ingestion roadmap

- BETA-08A: same-household selective backup recovery and shared candidate,
  duplicate-review, dependency, and atomic commit foundations.
- BETA-08B: canonical/external CSV mapping, duplicate review, and normal outbox.
- BETA-08C: reviewed camera/gallery receipt and invoice extraction.
- BETA-08D: reviewed bank statement PDF/image extraction.
- Later: merchant/category rules, Telegram, and automated inbox ingestion after
  local import/review workflows are stable.
# Post-D14 ingestion milestones

- BETA-08B: CSV bulk transaction import and shared ingestion pipeline.
- BETA-08C: receipt/invoice photo source adapter using the same drafts/review.
- BETA-08D: bank statement PDF/image source adapter.
- BETA-08E: explicit merchant/category mapping rules.
- Later: Telegram attachment source adapter through the same pipeline.
# BETA-08C/D reviewed ingestion extension

Engineering adds receipt/invoice photo and bank-statement PDF/image sources to
the existing reviewed import pipeline. This establishes the bounded future
foundation for Telegram attachment classification (CSV, receipt, statement)
into the same review queue; Telegram is not implemented and may never write a
transaction directly without review. Engineering verification completed on
2026-08-19 with 48 focused tests, 703 full-suite tests, 7 local Edge Function
tests, a clean analyzer, and passing web, Windows debug, and Android debug build
gates. Owner runtime acceptance remains deferred.

# BETA-08E deterministic import automation

BETA-08E engineering implements explicit household merchant/category rules as
review-time suggestions across CSV, receipt, and statement drafts. It includes
SQLite v22, normal sync/conflicts/RLS, encrypted backup v3, recovery, and clone
remapping without AI or retroactive transaction changes. Owner runtime
acceptance remains deferred.

# BETA-08F — Internal Transfer Matching & Conversion (documented only)

The next candidate milestone may identify likely paired outgoing/incoming
drafts between owned accounts and let the user explicitly convert them into one
Pilgrim internal transfer. It should reuse import drafts, duplicate evidence,
review UI, and current account semantics. It must not silently distort income
or expense reporting. No BETA-08F implementation is included in BETA-08E.

# BETA-08F0 — Canonical transfer foundation

Engineering foundation implemented on 2026-08-20: two stable directional
transaction legs plus one explicit transfer relation, SQLite v23, ordinary
sync/conflict/Supabase coverage, backup v4/recovery/clone support, and financial
classification safeguards. This is not the BETA-08F matcher. Matching remains
blocked until the BETA-08F0 engineering gates pass; owner runtime acceptance is
documented and deferred.

# BETA-08F1 — Matcher and review

Engineering adds explicitly confirmed deterministic matching over BETA-08F0.
Consolidated BETA-08F owner runtime acceptance remains deferred.

# BETA-08G — Persistent Import Review Inbox (engineering complete)

Durable household-scoped sessions and normalized drafts now support restart and
cross-device review for CSV, receipt/invoice, and statement sources. Current
rules, duplicates, transfers, and references are reanalyzed on resume while
stable identity and manual provenance survive. Commit/discard remain explicit,
backup stays v4, source files are not stored, the new migration remains local,
and Telegram ingestion is deferred to BETA-08H. Owner acceptance is not run.

# BETA-08G1 — Deferred Final Transaction Identity

Engineering implementation separates stable review/source identity from the
nullable account-dependent financial UUID, adds SQLite v25 and one undeployed
Supabase migration, and preserves BETA-08B UUIDv5 compatibility. BETA-08H was
safety-blocked on this prerequisite and may resume after the G1 engineering
gate. Owner acceptance is **NOT RUN**. Telegram was not implemented in G1.

### BETA-08H — Secure Telegram ingestion gateway

Engineering implementation now uses G1 deferred identity to deliver private
Telegram attachments into the existing Inbox without financial authority.
Local migration/function deployment and security verification are required for
Engineering PASS. Hosted deployment and consolidated owner acceptance move to
BETA-08H1 and remain **NOT RUN**.

# BETA-08I — Monthly & Annual Financial Statements

Local implementation adds Monthly/Annual Household and Account statements,
responsive preview, and offline PDF export without persistence, sync, backup,
or Supabase changes. SQLite remains 25 and backup remains v4. Historical
year-end net worth is omitted until reliable as-of valuation exists. Hosted
BETA-08H1 remains safety-blocked and untouched. Engineering verification is
PASS; owner acceptance is NOT RUN.

# BETA-08J — Data Health & Sync Diagnostics Center

Read-only local diagnostics cover structural finance, canonical transfers,
Import Inbox/G1 identity, rules/planning, outbox/conflicts, cloud availability,
and encrypted-backup capability without repair or persistence. SQLite remains
25, backup remains v4, and no Supabase/SQL change is introduced. Owner
acceptance is NOT RUN.

**BETA-08J Engineering PASS.** The owner temporarily lifted feature freeze for
four bounded milestones: BETA-08K cloud durability/new-device bootstrap,
BETA-08L fixed tithe category/payment tracking, BETA-08M CSV unknown-category
resolution, and BETA-08N investment/brokerage ledger. BETA-08K is implemented
without a schema or hosted deployment change. BETA-08L/M/N remain
unimplemented; feature freeze resumes after BETA-08N.
