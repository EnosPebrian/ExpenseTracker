LEAD ARCHITECT / OWNER AUTHORIZATION
PILGRIM TRACKER — POST-BETA-08N RELIABILITY + SPREADSHEET UX PROGRAM

OWNER IS AWAY.
CONTINUE AUTONOMOUSLY THROUGH ALL READY WORK ITEMS BELOW.

This authorization explicitly and temporarily lifts the current FEATURE FREEZE
ONLY for the work items defined in this document.

Do not invent additional product scope.

Repository:
D:\ExpenseTracker

Start by following:
docs/AGENTS.md
docs/AUTONOMOUS_ENGINEERING_PROTOCOL.md
docs/CODEX_WORK_QUEUE.md
docs/ENGINEERING_HANDOFF.md
docs/ARCHITECT_ESCALATIONS.md
docs/ARCHITECTURE.md

============================================================
CURRENT OWNER-REPORTED ISSUES
============================================================

There are FOUR known items to address in order.

ITEM 0 — CURRENT BROKERAGE IMPORT SESSION BUG
---------------------------------------------
In the all-nine-activities brokerage test:

- PTST appears in several rows.
- One explicit "Create PTST" decision does NOT propagate to the other PTST rows.
- User must click Create PTST repeatedly.
- After manual creation:
  SELL 40 reports available quantity 0 even though an earlier same-file BUY
  created 100 shares.
- SPLIT reports no existing position even though the same statement contains
  the earlier BUY.

This is already understood as a session-replanning defect.

ITEM 1 — MULTI-DEVICE SYNC / CONFLICT FAILURE
---------------------------------------------
Owner reproduced:

Windows:
- imported brokerage CSV
- sync produced conflicts
- clicked manual merge
- nothing visibly happened
- conflicts then disappeared

Android:
- imported Windows records never appeared

This is unacceptable.

A conflict must NEVER disappear merely because UI state was cleared.
A resolution is complete only after the selected/merged state is durably
accepted and this device has reconciled with the hosted authority.

Multi-device convergence must become reliable and observable.

ITEM 2 — TRANSACTION UI SHOULD FEEL LIKE GOOGLE SHEETS
-------------------------------------------------------
Owner wants:

- transactions displayed in a real table/grid;
- direct editing in cells;
- fast keyboard-driven editing;
- ability to see many transactions at once;
- copy/paste where safe;
- sorting/filtering;
- visible synchronization/conflict state.

Pilgrim should combine finance-app integrity with spreadsheet speed.

Do NOT make Google Sheets or a CSV file the financial database.

SQLite remains immediate local authority and Supabase remains durable shared
hosted synchronization authority.

A future Google Sheets bridge may be considered later, but is NOT part of this
program.

ITEM 3 — CSV DATE AMBIGUITY / UX
---------------------------------
Owner encountered DD/MM vs MM/DD ambiguity in test CSVs.

Canonical Pilgrim-created/test CSV should use unambiguous ISO:

YYYY-MM-DD

Example:
2026-09-01

ISO dates must auto-detect without asking DD/MM vs MM/DD.

Slash dates such as:

09/01/2026

must NEVER be guessed if the entire source remains genuinely ambiguous.

If the entire column provides enough evidence to distinguish DD/MM from MM/DD,
detect it at the WHOLE-COLUMN level.

Otherwise ask ONCE for the statement/import session.

============================================================
AUTHORIZED EXECUTION ORDER
============================================================

Execute these as separate validated sprints:

SPRINT 0
PT-BETA-08N-R7
Brokerage Import Session Replanning

SPRINT 1
PT-BETA-09A
Sync Convergence & Conflict Reliability

SPRINT 2
PT-BETA-09C
Deterministic CSV Date Handling

SPRINT 3
PT-BETA-09B1
Spreadsheet Transaction Grid Foundation

SPRINT 4
PT-BETA-09B2
Spreadsheet Editing / Clipboard / Bulk Workflow

Commit and push each sprint independently after its validation gates pass.

After a sprint completes:
- update CODEX_WORK_QUEUE.md
- update ENGINEERING_HANDOFF.md
- update relevant architecture/checkpoint documentation
- commit
- push
- verify HEAD == origin/main
- verify clean worktree
- automatically begin the next READY sprint

STOP only for:
- genuine BLOCKED_ARCHITECT
- destructive or production-only operation requiring owner approval
- credentials/secrets unavailable
- physical-device-only acceptance
- external tool/service unavailable after reasonable diagnosis
- unexpected hosted migration chain/drift
- architecture conflict that cannot safely be inferred

Do NOT stop merely to ask whether to continue to the next authorized sprint.

============================================================
GLOBAL NON-NEGOTIABLE ARCHITECTURE
============================================================

Preserve existing Pilgrim authorities:

Transaction
= authoritative economic event

Account
= authoritative cash/account identity

AssetDefinition
= authoritative asset/instrument identity

AssetPortfolioCalculator
= authoritative weighted-average holding/P&L calculation

canonical transfer links
= authoritative owned-account transfer relationship

SQLite
= immediate local-first source of truth

Supabase
= durable shared hosted synchronization authority

ordinary outbox/change-feed/conflict machinery
= synchronization path

Do NOT:

- create a second transaction ledger;
- store authoritative finance data in UI state;
- replace SQLite with Google Sheets;
- replace Supabase with CSV;
- directly edit SQL rows from presentation;
- bypass existing transaction/business validation;
- weaken oversell checks;
- weaken category/Tithe/transfer protections;
- treat conflict resolution as UI-only;
- silently discard local or remote changes;
- silently guess ambiguous dates;
- add unrelated features.

============================================================
SPRINT 0
PT-BETA-08N-R7 — BROKERAGE IMPORT SESSION REPLANNING
============================================================

OWNER RUNTIME FAILURE

Test statement contains:

2026-09-02 BUY PTST 100 @ 1000
2026-09-03 DIVIDEND PTST
2026-09-07 SELL PTST 40 @ 1200
2026-09-08 SPLIT PTST 2:1

Current behavior:

- PTST resolution must be repeated for multiple rows;
- SELL sees available quantity zero;
- SPLIT sees no position.

ROOT CONTRACT

One imported statement is ONE planning/review session.

Instrument resolution key:

normalized symbol + currency

Example:

PTST + IDR

If user explicitly chooses:

Create PTST

then every compatible PTST/IDR row in that statement must reuse ONE planned
AssetDefinition.

Likewise:

Map PTST -> existing asset

must propagate to every compatible PTST/IDR row in the statement.

Do not propagate across different currencies or incompatible identities.

SESSION REPLAN

Any authoritative review action must rebuild the financial preview for the
complete statement while preserving explicit decisions.

Review actions include at least:

- create instrument;
- map instrument;
- change activity;
- include/exclude row;
- resolution action that changes posting semantics.

Replanning algorithm:

persisted baseline
+
explicit statement-level resolution decisions
+
included drafts
    ↓
canonical date order
    ↓
stable source-row order as tiebreaker
    ↓
simulate each valid planned posting
    ↓
later rows validate against evolving simulated state

DO NOT persist simulated rows until final commit.

EXPECTED RESULT

After ONE Create PTST:

BUY 100
→ simulated PTST quantity = 100

SELL 40
→ valid
→ simulated PTST quantity = 60

SPLIT 2:1
→ valid
→ simulated PTST quantity = 120

Cost basis remains governed by existing split/accounting authority.

Do not weaken AssetTradeValidator.

Instrument identity:
- one planned definition;
- stable deterministic ID;
- final atomic commit creates it once;
- all PTST rows reference same ID;
- exact reimport creates no duplicate asset or transaction effects.

TESTS

At minimum:

1. create instrument once propagates;
2. map existing once propagates;
3. BUY influences later same-session SELL;
4. SELL 40 succeeds after BUY 100;
5. SELL >100 still blocks;
6. SPLIT sees remaining position;
7. split result correct;
8. excluding earlier BUY re-blocks SELL/SPLIT;
9. changing earlier BUY activity replans later validity;
10. source row order differing from chronological order still analyzes by date;
11. same ticker/different currency does not share resolution;
12. trusted IDX staging still works;
13. exact reimport remains idempotent;
14. final commit atomic;
15. failed final commit creates no partial instrument.

No schema change expected.

============================================================
SPRINT 1
PT-BETA-09A — SYNC CONVERGENCE & CONFLICT RELIABILITY
============================================================

THIS IS P0.

DO NOT BUILD THE SPREADSHEET GRID BEFORE THIS SPRINT PASSES.

OWNER REPRO

Windows:
- local/import writes exist;
- Sync now;
- conflicts appear;
- user chooses manual merge;
- nothing visible happens;
- conflict count disappears.

Android:
- expected data does not arrive.

This must be diagnosed end-to-end.

============================================================
09A.1 — FIRST: TRACE THE REAL SYNC PIPELINE
============================================================

Before changing code, document the current sequence for:

local mutation
→ SQLite financial row
→ outbox
→ push
→ server validation
→ remote row/version
→ server change feed/cursor
→ local acknowledgement
→ remote-device pull
→ remote-device SQLite
→ controller/UI

Trace conflict path separately:

push detects version conflict
→ persisted conflict representation
→ UI conflict list
→ keep-local / keep-cloud / manual-merge
→ server resolution
→ local apply
→ outbox/cursor reconciliation
→ conflict cleared

Identify exactly where the reproduced failure can occur.

Inspect:
- whether conflict is persistent or merely controller state;
- whether "manual merge" button actually invokes a dialog;
- whether dialog result reaches resolver;
- whether resolver writes remotely;
- whether remote response is checked;
- whether conflict is cleared too early;
- whether cursor advances incorrectly;
- whether outbox is removed before server durability;
- whether imported transaction dependencies arrive in correct order;
- whether Android is subscribed/woken but fails to pull;
- whether Android cursor can get ahead of unconsumed change rows.

Write diagnosis to a dedicated engineering-analysis document before repair.

============================================================
09A.2 — DURABLE CONFLICT LIFECYCLE
============================================================

A conflict may have explicit states such as:

detected
reviewing
resolutionPending
resolved

Use existing persistence where possible.

Do not invent persistent state unless necessary.

INVARIANT:

CONFLICT != RESOLVED

until the authoritative server resolution has succeeded and this device has
reconciled the resulting row/version.

The UI must not remove a conflict because:
- dialog opened;
- button clicked;
- local state changed;
- RPC started.

If the network/server resolution fails:
- conflict remains;
- clear retryable error is shown;
- no local data is silently discarded.

============================================================
09A.3 — CONFLICT UI
============================================================

"Merge manually" must actually open a useful resolver.

For ordinary user-editable fields show:

FIELD       LOCAL                 CLOUD
Date        ...
Description ...
Amount      ...
Category    ...
Account     ...
Project     ...
Reference   ...
Note        ...

For each mergeable field allow:
- use Local
- use Cloud

Optionally allow direct merged text input only where semantically valid.

Provide whole-record shortcuts:
- Keep local version
- Keep cloud version

Do NOT expose generated/internal identity fields as editable choices.

Do NOT allow field-by-field merges that violate domain invariants.

For complex coordinated records such as:
- canonical transfer legs;
- managed fee children;
- asset trades;
- brokerage-linked records;
- protected System Tithe semantics;

route resolution through the existing domain coordinator or restrict merge
options appropriately.

Never create an invalid hybrid financial record.

============================================================
09A.4 — CONVERGENCE GUARANTEE
============================================================

After a successful sync cycle the current device should expose:

Pending local changes: N
Failed changes: N
Conflicts: N
Last successful push
Last successful pull
Current remote cursor/checkpoint if the architecture already exposes it

Add useful Data & Sync diagnostics without exposing secrets.

"Synced" means:
- no unsent local mutations;
- no unresolved conflict;
- local cursor reconciled through acknowledged remote state.

Do not claim another physical device is synced unless the system has evidence.

============================================================
09A.5 — IMPORT BATCH DEPENDENCIES
============================================================

Specifically test brokerage CSV/import-generated mutations.

Ensure dependency ordering is safe for:

AssetDefinition
before transactions that reference it

category/account/reference entities
before dependent transaction if required

transaction legs
before/with transfer relation according to existing atomic contract

brokerage settlement evidence
after compatible referenced data where required

Do not solve dependency failures with arbitrary sleeps.

Use deterministic sequencing/retry/idempotency.

============================================================
09A.6 — EXACT OWNER REGRESSION
============================================================

Create an automated scenario equivalent to:

DEVICE A / Windows

1. same hosted household;
2. import several financial rows atomically;
3. create a real version conflict on one editable transaction;
4. sync;
5. conflict becomes visible;
6. click/execute manual merge;
7. choose explicit field/record resolution;
8. server accepts it;
9. conflict remains visible until success is confirmed;
10. after success local A contains the authoritative resolved version;
11. outbox no longer contains completed operation.

DEVICE B / Android-equivalent repository fixture

12. pull from its previous cursor;
13. receives every imported non-conflicting row exactly once;
14. receives resolved conflicting row exactly once;
15. linked asset/category/account/reference identity remains valid;
16. next sync is idempotent;
17. no echo mutation;
18. no disappearing data.

Also test failures:

- network failure during merge;
- server rejection;
- stale retry;
- duplicate retry;
- app restart while conflict pending;
- simultaneous edits A and B;
- resolution chosen on A while B remains offline;
- B reconnects later and converges.

============================================================
09A.7 — GOOGLE SHEETS DECISION
============================================================

Do NOT implement Google Sheets as authoritative storage.

The goal is to make Pilgrim's own multi-device sync trustworthy.

At sprint completion document:

"Google Sheets is not required as primary storage for multi-device durability."

A future optional Sheets export/import bridge remains future scope only.

============================================================
09A.8 — SCHEMA / HOSTED RULES
============================================================

Prefer fixing the existing sync protocol without new schema.

If a new additive sync field/table/function is genuinely required:
- document why;
- create additive migrations only;
- no historical migration edits;
- RLS/ACL tests required;
- no service-role exposure to clients.

AUTHORIZED HOSTED PROJECT FOR THIS PROGRAM:

pilgrim-tracker-dev
jylclfebdeaywfdwabph

If an additive migration is required for 09A, this prompt authorizes deployment
ONLY to that existing DEV project after:

- clean local reset/replay;
- focused pgTAP;
- full pgTAP;
- exact pending migration review;
- recovery point/dump;
- destructive-DDL inspection;
- pre/post record counts;
- RLS/ACL verification;
- security-advisor comparison.

If ANY unexpected pending migration exists:
STOP BLOCKED_ARCHITECT.

No destructive hosted change is authorized.

============================================================
SPRINT 2
PT-BETA-09C — DETERMINISTIC CSV DATE HANDLING
============================================================

OWNER COMPLAINT

A test CSV using:
09/01/2026

was ambiguous between:
DD/MM/YYYY
MM/DD/YYYY.

That ambiguity is legitimate.

The UX should avoid ambiguity where possible, never guess when not possible.

============================================================
09C.1 — ISO FIRST
============================================================

Canonical Pilgrim-created CSV dates must be:

YYYY-MM-DD

Example:
2026-09-01

All Pilgrim test fixtures and exports created by current/future code should use
ISO dates unless a specific external source contract requires otherwise.

ISO year-first dates must auto-detect without prompting for DD/MM vs MM/DD.

============================================================
09C.2 — WHOLE-COLUMN DETECTION
============================================================

When mapping an external date column:

Analyze all relevant nonblank rows.

Examples:

01/02/2026
13/02/2026

The second value proves DD/MM.

Therefore choose DD/MM for the column if all values are consistent.

Similarly:

02/13/2026

proves MM/DD.

Do not decide from the first row only.

============================================================
09C.3 — GENUINELY AMBIGUOUS SOURCES
============================================================

Example:

01/02/2026
03/04/2026
05/06/2026

Both slash formats remain possible.

In this case:
- do not guess;
- show one statement-level choice;
- show examples of how sample dates will be interpreted;
- require user choice once;
- reanalyze entire statement.

Do not show per-row date questions.

============================================================
09C.4 — FORMAT SET
============================================================

Inspect existing CsvDateFormat enum/parser first.

Support current accepted formats without regression.

Ensure at minimum:
- ISO YYYY-MM-DD
- DD/MM/YYYY
- MM/DD/YYYY

Preserve other existing accepted explicit formats.

Invalid mixed-format columns should remain blocking rather than silently
normalizing unrelated formats.

============================================================
09C.5 — TESTS
============================================================

At minimum:

- ISO auto-detect;
- ISO never reports DD/MM ambiguity;
- whole-column DD/MM detection;
- whole-column MM/DD detection;
- all-ambiguous slash column requires one explicit choice;
- inconsistent/mixed column blocks;
- leap-year validation;
- invalid dates block;
- blank optional rows handled consistently with current parser;
- brokerage imports;
- ordinary transaction imports;
- generated/exported canonical CSV round-trips.

No financial/schema change expected.

============================================================
SPRINT 3
PT-BETA-09B1 — SPREADSHEET TRANSACTION GRID FOUNDATION
============================================================

PRODUCT GOAL

On Windows/desktop, Transactions should feel much closer to Google Sheets while
remaining a safe financial application.

This is a PRESENTATION/EDITING surface over the existing Transaction authority.

Do NOT create a second table/ledger.

============================================================
09B1.1 — DESKTOP GRID
============================================================

Create a first-class Table/Grid view for Transactions.

Responsive policy:

WINDOWS / wide desktop:
default to or prominently expose spreadsheet grid.

ANDROID / narrow:
retain appropriate mobile list/card UX.
Do not force desktop spreadsheet UX onto a phone.

Grid should support a large transaction history efficiently.

Core columns should include, subject to existing domain availability:

- Date
- Description
- Type
- Amount
- Category
- Account
- Project
- Asset / Instrument where applicable
- Reference
- Note
- Sync state

Do not duplicate calculated accounting truths as editable data.

Optional non-editable indicators:
- transfer
- generated/managed child
- brokerage/investment
- archived/deleted status where appropriate
- conflict/pending sync

============================================================
09B1.2 — COLUMN UX
============================================================

Desktop users should have:

- sticky header;
- horizontal/vertical scrolling;
- sortable columns;
- searchable/filterable view;
- column resizing;
- sensible numeric alignment;
- keyboard row/cell focus;
- clear selected row/cell;
- empty/loading/error states;
- performance appropriate for thousands of transactions.

If practical within current presentation architecture:
- hide/show columns;
- reorder columns.

Store purely visual grid preferences locally if needed.
Do not sync UI layout as financial data.

============================================================
09B1.3 — INLINE EDIT SAFETY
============================================================

Ordinary transactions should allow safe direct cell editing.

Likely inline-editable fields where domain permits:

- Date
- Description
- Amount
- Category
- Account
- Project
- Reference
- Note

But inspect existing transaction types first.

DO NOT assume all rows allow all fields.

For:
- generated managed fee children;
- canonical transfer legs;
- protected linked records;
- brokerage/asset trades;
- split events;
- system-managed transactions;

either:
- expose only safe fields inline; or
- open existing coordinated editor for the operation.

Never bypass:
- asset oversell validation;
- transfer pairing;
- fee child management;
- System Tithe category protections;
- account/currency validation;
- category identity;
- project semantics;
- brokerage metadata;
- note/reference sync behavior.

============================================================
09B1.4 — EDIT INTERACTION
============================================================

Desktop interaction target:

single click
→ select cell

Enter or double-click
→ edit

Enter
→ commit edit and move appropriately

Tab / Shift+Tab
→ next/previous editable cell

Escape
→ cancel current edit

Arrow keys
→ navigation when not editing

Edits must use existing controllers/usecases/repositories.

Never issue SQL directly from grid code.

While save is pending:
- show state;
- prevent accidental duplicate submission.

Validation errors should remain attached to the edited row/cell.

Do not make failed edits disappear.

============================================================
09B1.5 — SYNC VISIBILITY
============================================================

Because 09A precedes this sprint, integrate grid-level sync visibility.

At minimum distinguish:

Synced
Pending
Failed
Conflict

A conflict indicator should open the real 09A resolver.

Do not show "Synced" merely because the local edit saved.

============================================================
09B1.6 — PERFORMANCE
============================================================

Test at least:

1,000 rows
5,000 rows

Avoid rebuilding every visible cell on one-cell edit where architecture allows.

No O(N²) filtering/rendering.

Do not sacrifice correctness for virtualization.

============================================================
SPRINT 4
PT-BETA-09B2 — SPREADSHEET EDITING / CLIPBOARD / BULK
============================================================

Only start after B1 passes.

============================================================
09B2.1 — MULTI-CELL COPY
============================================================

Allow selecting/copying visible cells/rows into tabular clipboard text that can
paste naturally into Excel/Google Sheets.

Copy must not mutate anything.

============================================================
09B2.2 — SAFE PASTE
============================================================

Allow paste into a contiguous editable selection where field semantics are
unambiguous.

Examples:
- descriptions;
- references;
- notes;
- dates;
- amounts;
- categories/accounts when values resolve explicitly.

Before applying multi-row paste:

- parse entire rectangle;
- validate every intended edit;
- show blocking errors;
- do not silently skip invalid cells.

For financially meaningful bulk edits:
use an atomic or clearly reviewed commit strategy consistent with existing
transaction repository capability.

Never leave half a multi-row paste silently applied if the accepted contract is
all-or-nothing.

If existing repository cannot safely provide atomic bulk edit, document the
constraint and implement a reviewed plan with explicit per-row outcome rather
than pretending it is atomic.

============================================================
09B2.3 — BULK EDIT
============================================================

When multiple ordinary transactions are selected, support useful safe operations
such as:

- set category;
- set account only when currency/domain compatibility permits;
- set project;
- append/set note/reference if semantics are clear.

Do not bulk mutate:
- transaction identity;
- generated children independently;
- transfer pair relationship;
- asset quantity/accounting semantics;
- protected System Tithe identity;
unless an existing coordinated domain operation supports it.

============================================================
09B2.4 — UNDO
============================================================

Provide UI undo for the current editing session if it can be implemented safely
using normal transaction update operations.

Undo must create a valid new mutation through the same repository/sync path.

Do not rewind SQLite or mutate history outside normal business operations.

At minimum support undo of the most recent local grid edit(s) within the active
screen session.

If robust undo cannot safely be provided in this sprint, document and defer it
rather than implement unsafe state rollback.

============================================================
09B2.5 — FILTERING / BULK REVIEW
============================================================

Support practical spreadsheet workflows:

- text search;
- date range;
- account;
- category;
- project;
- type;
- sync state;
- conflict state.

Filters are presentation state only.

============================================================
GOOGLE SHEETS-LIKE DOES NOT MEAN GOOGLE SHEETS IS DATABASE
============================================================

The user wants the ergonomics of Google Sheets:

- dense table
- fast editing
- keyboard navigation
- copy/paste
- filters
- immediate visibility

while preserving Pilgrim financial correctness.

DO NOT implement direct Google Sheets live storage under this authorization.

Do not mount/share a CSV as a concurrent multi-device database.

============================================================
GLOBAL TEST REQUIREMENTS
============================================================

Every sprint:

dart format
focused tests
relevant historical regressions
flutter analyze
git diff --check

For meaningful application-code sprints also run:

full Flutter test suite
flutter build web
flutter build windows --debug
flutter build apk --debug

Where SQL changes:
- clean local Supabase replay
- focused pgTAP
- full pgTAP
- database lint/advisor as currently used

Do not suppress/remove valid historical tests just to pass.

============================================================
09A SPECIFIC REGRESSION GROUPS
============================================================

Run:
- sync/outbox
- realtime wakeup
- conflict resolution
- initial sync/bootstrap
- offline reconnect
- transaction note/reference
- categories
- transfers
- asset definitions
- brokerage import
- settlement evidence
- Interest
- account/household authorization
- Health Check

============================================================
09B SPECIFIC REGRESSION GROUPS
============================================================

Run:
- transaction create/edit/delete
- categories
- accounts
- projects
- transfers
- asset trades/fees
- brokerage metadata
- Tithe
- budgets
- notes/references
- sync/outbox/conflicts
- desktop navigation
- responsive mobile behavior

============================================================
DOCUMENTATION
============================================================

Create/update durable architecture documentation for:

1. sync convergence/conflict lifecycle;
2. transaction grid editing boundary;
3. deterministic CSV date policy.

Update:
docs/ARCHITECTURE.md
docs/CODEX_WORK_QUEUE.md
docs/ENGINEERING_HANDOFF.md
docs/ARCHITECT_ESCALATIONS.md if decisions/blockers arise
progress/checkpoint docs as appropriate

Do not falsify owner acceptance.

Automated engineering PASS != owner runtime PASS.

============================================================
GIT / AUTONOMY
============================================================

After each validated sprint:

- review diff
- git diff --check
- commit with bounded sprint subject
- push origin/main
- verify HEAD == origin/main
- verify clean worktree
- update durable queue/handoff
- continue to next authorized READY item

Do not wait for owner confirmation between these authorized sprints.

If usage/session stops, repository handoff must make the next Codex session able
to resume deterministically.

============================================================
FINAL PROGRAM STATE
============================================================

When all five authorized sprints are Engineering PASS:

- feature freeze resumes;
- do not invent a new feature;
- remaining physical Windows/Android acceptance = BLOCKED_OWNER;
- prepare a concise owner test matrix specifically covering:
    a. brokerage session replan;
    b. Windows import -> sync -> Android convergence;
    c. real manual conflict merge;
    d. ISO CSV auto-detection;
    e. transaction grid inline edit;
    f. copy/paste;
    g. offline grid edit -> reconnect -> convergence;
    h. restart persistence.

FINAL REPORT MUST INCLUDE:

For each sprint:
- diagnosis/root cause
- implementation summary
- schema/version changes
- SQLite version
- backup version
- Supabase migration(s)
- hosted deployment status
- focused tests
- full tests
- analyzer
- builds
- pgTAP if relevant
- commit hash(es)
- push result

Program-wide:
- final HEAD
- HEAD == origin/main yes/no
- final git status
- open architecture escalations
- owner-only remaining actions
- feature freeze restored yes/no

BEGIN NOW.

First reconcile repository state and record these authorized work items in the
queue.

If PT-BETA-08N-R7 is already IN_PROGRESS, RESUME it rather than restarting.
If it is not yet recorded, create it using the contract above and execute it.

Proceed autonomously.
