# PT-BETA-09C — Deterministic CSV Date Handling

Status: COMPLETE. Owner acceptance PENDING / NOT RUN.
Starting clean main/origin: `1bf704fea93f54924e5d2bb54bfcadf802f1ba6a`.

Ordinary imports previously chose dates per row; brokerage detection was
whole-column but accepted impossible ISO shapes as detected. Both now share
one strict whole-column policy. ISO takes precedence; unambiguous slash columns
are inferred using all nonblank rows. Ambiguous columns require one explicit
session choice with interpretation examples. Mixed/invalid columns block.
Existing explicit formats and deterministic IDs are preserved.

Generated transaction CSV dates are local calendar YYYY-MM-DD; audit timestamps
remain unchanged. No money, accounting, SQLite, backup or sync change.
SQLite 29, backup v8, SQL/Supabase migration: NONE. Hosted action: NONE for 09C.

Focused regressions: **106/106 PASS**, including 13 new date-policy tests,
ordinary/receipt/statement/brokerage import, atomic import and CSV export.
One historical expected format label for February 30 was updated from ISO to
unresolved; date-null/raw-value/no-commit assertions were preserved.

Analyzer PASS; full Flutter suite **1052/1052 PASS**. Web, Windows debug and
Android debug APK builds PASS (unchanged file_picker Kotlin warning).
Diff review and git diff --check PASS. Commit
`a83c14986d58ab08cf380b2ff68eec5a4facfeb6` pushed to origin/main.
HEAD == origin/main and clean worktree verified after publication.
Next authorized sprint after publication: PT-BETA-09B1.
