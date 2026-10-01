# BETA-09B3 — Catalog-aware spreadsheet editing

State: Engineering PASS, 2026-10-01; Git publication tracked in handoff.
Owner acceptance PENDING / NOT RUN.
Baseline: main/origin 71be9eb33aebcbff06e215ff4cfbc6d348869f94, clean.

Root cause: bulk and inline grid editors used generic text fields even for
catalog-backed identities, requiring exact-name knowledge. Review exposed raw
storage keys instead of a useful old/new field table.

Shared searchable catalog picker serves bulk and inline editing. Discovery
delegates candidate eligibility to TransactionGridPolicy.prepare; explicit
stable-ID choices are revalidated through prepareChoice and the existing
reviewed per-row commit boundary. No new mapping engine, master-data creation,
SQL writes, financial semantics or authority is introduced. Mixed categories
block, accounts must work for every row, project clearing is explicit, and
Note/Reference retain free text with a Clear value checkbox. Friendly toolbar
labels and review table show description/field/old/new. Keyboard tests exposed
Tab routing through autocomplete; explicit Enter/Tab/Escape shortcuts repaired it.

Initial focused B3/B2/B1: 33/33 PASS. Expanded B3 and historical regressions:
162/162 PASS. Final grid group 40/40 PASS, including 22 dedicated B3 cases.
Analyzer PASS (no issues); full Flutter suite 1094/1094 PASS. The sole initial
test-braces info was fixed. Web PASS (190.7s), Windows debug PASS (48.8s),
Android debug APK PASS (135.0s), known file_picker Kotlin warning unchanged.
Diff review and git diff --check PASS. Publication pending; source frozen.
SQLite 29, backup v8 unchanged. No SQL/Supabase or hosted action.

Limits inherited from B2: reviewed per-row saves, not atomic bulk; only latest
supported single-cell undo; no master-data creation, no mobile spreadsheet UI.
After all gates: commit/push, restore freeze, leave owner matrix NOT RUN.
