# BETA-06 Checkpoint — Household Backup, Safe Restore, and CSV Export

Status: implementation complete; final gate results are recorded below after
the milestone verification run.

Delivered:

- household-scoped, consistent native snapshots and web parity;
- versioned encrypted `.ptbackup` format with PBKDF2-HMAC-SHA256,
  AES-256-GCM, random salt/nonce, per-file and aggregate checksums;
- structural, relationship, amount, lifecycle, and accounting validation;
- restore-as-new with collision rejection/remapped-copy alternative;
- advanced matching replacement with exact-name confirmation, mandatory
  encrypted safety backup, atomic SQLite activation, and no merge;
- local-only restore state without auth/session/sync protocol inheritance;
- filtered spreadsheet-safe UTF-8 CSV ZIP;
- Windows, Android, and web scoped file pick/save behavior;
- SQLite 20 migration scoping manual market-price keys by household.

D14 remains open. This checkpoint does not add cloud-storage providers,
scheduled backup, signing, installer work, or administrative Supabase download
inside Flutter.

## Verification

Final BETA-06 completion run on 29 July 2026:

- focused BETA-06 tests: 16 passed;
- full Flutter suite: 546 passed;
- `flutter analyze`: no issues found;
- `flutter build web`: passed, including the Wasm dry run;
- `flutter build windows --release`: passed;
- `flutter build apk --debug`: passed without signing or store submission;
- `git diff --check`: passed;
- `git status --short`: reviewed; the pre-existing dirty worktree was preserved.

Android currently emits Flutter's forward-looking warning that file_picker
10.3.10 still applies the Kotlin Gradle Plugin. The APK builds successfully
with the project's current Gradle configuration; upgrading that boundary is a
future tooling task, not a BETA-06 functional failure.

The 2026-07-31 owner retest found a transaction whose historical category
snapshot has no matching definition locally or in the authorized Supabase
household. Transactions in this schema do not store a category UUID. Backup/CSV
now classify the absent definition as a confirmable warning; cross-household
scope remains fatal. This repair does not mark D14 complete.
