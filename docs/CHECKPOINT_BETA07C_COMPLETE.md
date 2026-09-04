# BETA-07C Deployment and Acceptance Checkpoint

**Date:** 2026-08-03  
**Verdict:** **BETA-07C FAIL**  
**Blocker:** Required Windows/Android owner runtime acceptance has not been run.

## Completed work

- Confirmed the linked hosted project is the existing private Pilgrim Tracker
  project used by this workspace.
- Reset the local disposable Supabase database, applied all migrations through
  `202608020001`, and passed 81 pgTAP assertions.
- Deployed only the pending monthly-budget migration through the normal linked
  `supabase db push` workflow; local and remote histories now agree.
- Verified the remote budget table, triggers, RLS enablement, and four
  authenticated active-household-member policies. Anonymous row access remains
  denied by RLS.
- Built configured Supabase-aware Windows, APK, and AAB release artifacts with
  the existing release helper and without `flutter clean`.
- Verified the APK has the expected Enos owner certificate and is not debug
  signed.

## Artifact record

- Windows: `build\windows\x64\runner\Release\pilgrim_tracker.exe` — 70,144 bytes.
- APK: `build\app\outputs\flutter-apk\app-release.apk` — 65,400,675 bytes.
- AAB: `build\app\outputs\bundle\release\app-release.aab` — 63,716,567 bytes.
- APK signer: `CN=Enos Pebrian, OU=Pilgrim Tracker, O=Tebu Nai, L=Denpasar, ST=Bali, C=ID`.
- APK verification: one RSA-4096 signer; v2 signature verified.

## Preservation and compatibility

- SQLite remains version 21; no new local migration was added.
- Backup format remains v2 with existing v1 compatibility.
- Supabase migration `202608020001` is now deployed; no previously applied
  migration was edited.
- No hosted reset or data-changing manual SQL was run.
- No production Dart, SQLite, backup, restore, CSV, synchronization, or
  financial behavior changed during BETA-07C.
- The existing dirty worktree and all BETA-07A/B work were preserved.
- Historical D14 controlled-private-deployment approval remains unchanged.

## Acceptance state

The full status matrix is in `BETA07_ACCEPTANCE_RESULTS.md`. Existing-database
upgrade/reopen, CRUD, calculations, navigation, copy behavior, cross-device and
offline synchronization, conflicts, backup v2/v1, restore, CSV, and category
lifecycle acceptance are all **NOT RUN**. These are owner-device checks and
cannot be inferred from compilation or automated tests.

BETA-07A/B therefore remain engineering-complete but unreleased. They may be
closed for controlled private deployment only after every required owner check
passes and no critical defect remains.

## BETA-07C1 follow-up

Owner acceptance found that replacement restore correctly cleared cloud state
but offered no route back to the existing hosted household. BETA-07C1 adds a
safe, download-first reconnect with active-membership discovery, required
encrypted safety backup, staged validation, same-ID atomic replacement, and
different-ID secondary download. It never uploads or merges local-only data.
This checkpoint remains open pending the owner retest in the dedicated C1
checkpoint.
