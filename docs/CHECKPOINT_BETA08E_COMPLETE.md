# BETA-08E engineering checkpoint

Date: 2026-08-19

Milestone: Merchant & Category Rules / Deterministic Import Automation.

Engineering scope is implemented with SQLite schema 22, synchronized
household-level import rules, source-neutral deterministic matching, explicit
review provenance and confirmation, encrypted backup format v3, selective
recovery, and restore/new-household remapping. The existing reviewed ingestion
pipeline remains the only transaction commit path.

Rules are suggestions only. They do not create or retroactively modify
transactions, do not alter deterministic import identity, do not use AI, and do
not participate in normal CSV export.

Final validation evidence for this worktree run:

- BETA-08E focused tests: 23 passed;
- complete Flutter suite: 726 passed;
- `flutter analyze`: no issues;
- web, Windows debug, and Android debug builds: passed;
- local Supabase reset: passed, including the BETA-08E migration;
- local pgTAP: 98 assertions across 6 files passed.

No hosted Supabase migration or Edge Function deployment was performed.
Owner acceptance is **NOT RUN** and remains deferred for BETA-08A1/B/C/D/08E.

The next documented milestone is BETA-08F, reviewed internal-transfer matching
and conversion. It is not implemented here.
