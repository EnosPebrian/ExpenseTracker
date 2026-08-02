# D14 Complete Checkpoint

Closure date: 2026-08-02

## Verdict

**D14 PASS — Ready for controlled private deployment by Enos and Grace.**

## Deployment scope

Approved:

- private household use;
- Enos and Grace;
- Windows and Android;
- hosted Supabase synchronization;
- encrypted backup and restore;
- CSV export.

Not claimed:

- public production launch;
- Play Store publication;
- enterprise use;
- web production readiness;
- third-party security certification.

## Final release identities

- Product: Pilgrim Tracker.
- Version: `1.0.0+1`.
- Android application ID: `com.enospebrian.pilgrimtracker`.
- Windows product/company: Pilgrim Tracker / Enos Pebrian.
- Native database: SQLite version 20.

## Signed artifact status

- The owner-signed Android APK builds and its signature verifies.
- The owner-signed Android AAB builds.
- The APK is not Android Debug signed.
- Owner certificate identity:

```text
CN=Enos Pebrian
OU=Pilgrim Tracker
O=Tebu Nai
L=Denpasar
ST=Bali
C=ID
```

The Windows executable is not Authenticode-signed.

## Accepted runtime checks

- A configured Windows release builds and runs.
- The Android app installs and launches.
- Android authentication works and the existing household loads.
- Close/reopen preserves session, household, data, and synchronized state.

## Synchronization result

Android-to-Windows transaction synchronization works for the hosted Supabase
household. The accepted close/reopen check preserves the synchronized state.

## Backup and restore result

- Windows and Android backup workflows work.
- Encrypted backup creation succeeds.
- Backup validation succeeds.
- The replacement safety-backup workflow succeeds.
- Restore completes without crash or visible corruption.
- Invalid restore file extensions are rejected by application-level validation.

## CSV result

CSV ZIP export succeeds. The owner manually inspected the CSV contents and
accepted them.

## Automated baseline

- Full Flutter suite: 587 passing tests.
- `flutter analyze`: passed.
- Latest repair compilation gates: web, Windows debug, and Android debug passed.

These commands were not rerun for this documentation-only closure.

## Known non-blocking limitations

- The Windows executable is not Authenticode-signed.
- Web remains an in-memory development preview.
- There is no scheduled or cloud-provider backup automation.
- Restore does not merge independently modified household histories.
- `file_picker` emits a forward-looking Kotlin compatibility warning.
- Backup and CSV filename extensions may later be appended automatically as UX
  polish.

## Next development

D14 is closed for the approved deployment scope. Further development may begin.
