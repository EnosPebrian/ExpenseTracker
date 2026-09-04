# BETA-07C1 — Safe Hosted Household Reconnect

Date: 2026-08-09

## Verdict

Implementation complete; owner-device acceptance remains required. BETA-07C is
not automatically passed.

## Root cause and repair

Replacement restore correctly makes records local-only and clears remote
identity/cursors. The initial-sync context then classified a same-ID active
membership as the primary upload case, while populated targets were forbidden
from secondary download, leaving no safe recovery action.

Cloud Sharing now displays **Reconnect cloud sharing** only for a configured,
initialized, signed-in session with a resolvable local member and a local-only
or not-ready active book. Hosted choices come exclusively from active
memberships and RLS-protected manifests; raw IDs are not shown.

Recovery is download-only. It previews local/hosted totals, warns that local
changes are not merged, requires an encrypted safety-backup password and saved
backup, stages the hosted snapshot, validates manifest counts, identity, scope,
versions, and references, then activates atomically. Same-ID recovery replaces
the local copy and restores remote identity/cursor. An exact matching snapshot
only reattaches identity/cursor. Different-ID recovery preserves the current
local household and activates the hosted household only after the existing
secondary-download validation succeeds. Both paths keep the outbox empty.

## Owner retest

1. On Windows after replacement restore, sign in as Enos and open Household.
2. Confirm **Reconnect cloud sharing** is visible and **Sync now** is disabled.
3. Select the matching hosted household; confirm name, IDR, owner role, matching
   identity marker, counts, and no raw UUID.
4. Select a backup folder, enter an 8+ character password, and continue.
5. Confirm a `.ptbackup` file was saved, hosted data replaces the local copy,
   status becomes Synced, Pending is 0, and Last successful is current.
6. Repeat on Android as Grace and confirm member role/mapping and downloaded
   data; create a transaction on either device and verify normal sync resumes.
7. Cancel once before backup and once from the save picker; verify the original
   local-only household remains unchanged.
8. If an unrelated hosted membership is available, download it and confirm the
   prior local-only household is preserved as a separate household.

## Compatibility

SQLite remains version 21. No migration, Supabase SQL, backup-format,
encryption, CSV, financial-calculation, or sync-architecture change was made.

## Verification

- `dart format`: passed for all changed Dart and test files.
- Focused reconnect tests: 29 passed.
- `flutter analyze`: passed with no issues.
- Complete Flutter suite: 620 passed.
- Web compilation and Wasm dry run: passed.
- Windows debug build: passed.
- Android debug APK build: passed; the existing forward-looking `file_picker`
  Kotlin compatibility warning remains non-blocking.
- `git diff --check`: passed; line-ending notices only.
