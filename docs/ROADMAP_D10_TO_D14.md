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
- **BETA-04C:** conflict resolution UX and remaining synchronization polish.
- **BETA-05:** two-device acceptance testing with Enos and Grace.

**D14 status: Conditionally open.** Do not mark D14 complete until BETA-05,
owner Android signing, final native builds, and Android/Windows runtime database
smoke gates in `CLOSED_BETA_CHECKLIST.md` pass.
