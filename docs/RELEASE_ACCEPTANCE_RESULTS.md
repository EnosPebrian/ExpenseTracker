# D14 Final Release Acceptance Results

## Final owner acceptance — 2026-08-02

**D14 PASS — Ready for controlled private deployment by Enos and Grace.**

Approved scope: private household use by Enos and Grace on Windows and Android,
using hosted Supabase synchronization, encrypted backup and restore, and CSV
export.

This acceptance does not claim public production launch, Play Store
publication, enterprise use, web production readiness, or third-party security
certification.

| Area | Final status | Accepted owner evidence |
|---|---|---|
| Windows release | PASS | Configured release builds and runs. |
| Android packaging | PASS | Owner-signed APK and AAB build. |
| APK identity | PASS | Owner certificate verified; APK is not Android Debug signed. |
| Android runtime | PASS | Installs, launches, authenticates, and loads the existing household. |
| Reopen persistence | PASS | Session, household, data, and synchronized state remain after close/reopen. |
| Hosted synchronization | PASS | Android-to-Windows transaction synchronization works. |
| Backup | PASS | Windows and Android workflows create encrypted backups; validation and replacement safety-backup workflow succeed. |
| Restore | PASS | Restore completes without crash or visible corruption. |
| CSV export | PASS | CSV ZIP succeeds and the owner manually inspected and accepted its contents. |
| Restore selection validation | PASS | Invalid restore file extensions are rejected by application-level validation. |

Release identity: Pilgrim Tracker `1.0.0+1`; Android application ID
`com.enospebrian.pilgrimtracker`; Windows product `Pilgrim Tracker`, company
`Enos Pebrian`; SQLite version 20.

Owner certificate identity:

```text
CN=Enos Pebrian
OU=Pilgrim Tracker
O=Tebu Nai
L=Denpasar
ST=Bali
C=ID
```

Accepted automated baseline: 587 passing Flutter tests and clean
`flutter analyze`. Web, Windows debug, and Android debug compilation gates
passed during the latest repair. These gates were not rerun for this
documentation-only closure.

The July 30 results below describe an earlier blocked attempt and are retained
for audit history. They no longer represent the release verdict.

## D14 cloud/auth/Household repair — 2026-07-30

Configuration, Auth session, and connectivity are now independent states.
Missing, whitespace-only, malformed, or placeholder configuration is rejected
without exposing the publishable key. A configured build with no restored
session shows **Sign in required**, not a connection error. Session restoration
is neutral; an expired session is cleared remotely where possible while all
local household data is preserved; an actual Auth reachability failure is
retryable and does not block local startup.

Household Settings now separates a saved remote link from the current device
session and no longer claims multi-device sharing is a future milestone. Safe
diagnostics report configuration presence/validity, Auth initialization, and
session state only. Focused tests: 36 passed, followed by 29 affected cloud
tests after the final privacy adjustment. Full suite: 560 passed. Analyzer:
clean. Web release build with non-secret test defines: passed.

Owner runtime checks remain required: build through `tool\build_release.ps1`,
open Household Settings signed out and confirm no red connectivity error,
sign in and confirm linked/member state, test offline retry while local pages
remain usable, then close/reopen and confirm session/link state is accurate.

Date: 2026-07-30  
Build identity: Pilgrim Tracker `1.0.0+1`, SQLite 20  
Dataset: synthetic owner test household only (two members, three accounts,
categories, a project, ordinary transactions, fees, and a measured asset).

## Platform and device topology

- Windows: this Windows 10 host, independent native SQLite database, release
  executable built and process-started.
- Android: no physical device or emulator was attached during D14 Final.
- Hosted sync: earlier owner evidence used separate Windows and Android SQLite
  databases for the Enos and Grace members. The complete final matrix was not
  rerun in this acceptance pass.
- Web: the passing BETA-06 release build was retained. Browser runtime control
  was unavailable, so no interactive web claim is made.

## Owner acceptance matrix

| Area | Status | Evidence |
|---|---|---|
| Backup creation | NOT RUN | Two owner-created `.ptbackup` files were not manually compared. |
| Wrong-password rejection | NOT RUN | Automated coverage exists, but owner runtime proof is absent. |
| Corrupt-backup rejection | NOT RUN | No disposable backup was manually altered. |
| Restore as new household | NOT RUN | Owner runtime restore/reopen comparison is pending. |
| Replacement restore | NOT RUN | Disposable-household replacement flow is pending. |
| CSV export | NOT RUN | Excel/file-content and filter acceptance is pending. |
| Windows file picker | NOT RUN | Release executable started, but picker interaction was not performed. |
| Android file picker | BLOCKED | No Android target was attached. |
| Hosted synchronization | NOT RUN | Earlier initial download, transaction sync, offline queue, and session evidence is partial; the required final matrix was not completed. |
| Two-device reopen | NOT RUN | Earlier reopen evidence is partial and predates the final acceptance pass. |
| Release signing | FAIL | Owner certificate preflight passed; the only permitted signed APK attempt ended in a Gradle JVM native-memory crash. |
| Release installation | BLOCKED | No new signed APK exists and no Android target is attached. |

## Android signing and packaging

- `android/key.properties`: present and untracked; secret values were not
  printed.
- Configured keystore: present outside the repository at the path recorded in
  `key.properties`. The milestone's stated `D:\PilgrimTrackerReleaseKeys` copy
  was not present; the working owner copy was not moved or replaced.
- Alias: `pilgrimtracker`.
- Certificate identity: **PASS** — `CN=Enos Pebrian, OU=Pilgrim Tracker,
  O=Tebu Nai, L=Denpasar, ST=Bali, C=ID`; it is not Android Debug.
- Signed APK build: **FAIL** — exactly one `flutter build apk --release`
  attempt was made. Gradle's Java 21 daemon exhausted native memory while
  configured with an 8 GiB heap on a roughly 12 GiB machine with no pagefile
  capacity reported. This was not a password or certificate failure.
- Signed AAB build: **BLOCKED** — intentionally not attempted after APK failure.
- APK/AAB paths and sizes: none produced by D14 Final.

## Android runtime

Overall: **BLOCKED**. No device/emulator was attached. Installation, branding,
profile, household, accounting, oversell, pricing, sync, backup, CSV, and
close/reopen steps were not run against an owner-signed release.

## Windows release

- Build: **PASS**.
- Executable: `build\windows\x64\runner\Release\pilgrim_tracker.exe`, 70,144
  bytes.
- Metadata: Pilgrim Tracker / Enos Pebrian / `1.0.0+1`.
- Authenticode: `NotSigned`.
- Process startup/responding check: **PASS**.
- Interactive runtime, file-picker, accounting, synchronization, backup,
  restore, CSV, and close/reopen checklist: **NOT RUN**.

## Web preview

- BETA-06 web release build and Wasm dry run: **PASS** baseline reused.
- Interactive launch/navigation/backup/download/upload: **NOT RUN** because
  the browser-control runtime was unavailable.
- Production suitability: **BLOCKED** by intentional in-memory preview storage.

## Hosted synchronization and multi-device status

Earlier owner evidence confirms Enos and Grace authenticated separately,
shared one household, completed an initial upload/download, synchronized a
transaction, retained sessions after reopen, and exercised the offline queue.
This does not prove the full D14 matrix. Same-Enos-account dual sessions,
automatic post-fix UI refresh, synchronized deletes, conflict resolution,
cross-user denial, duplicate prevention, and final two-device reopen are all
**NOT RUN** in this pass.

## Automated baseline

Production code did not change during D14 Final. Per project instructions, the
BETA-06 baseline was reused: 16 focused tests passed, 546 full Flutter tests
passed, analyzer clean, web release/Wasm passed, and SQLite remained version
20. No automated suite was rerun for documentation-only changes.

## Defects and fixes

- **Platform packaging / BLOCKER:** the signed Android release build crashed
  from JVM native-memory exhaustion. No retry was made because the milestone
  permits exactly one attempt. Before the next attempt, free system memory and
  enable a Windows pagefile or deliberately lower Gradle JVM memory limits,
  then perform one controlled build and certificate verification.
- No production application defect was reproduced or changed.

## Historical July 30 release recommendation

**D14 FAIL — Critical blockers remain.** Do not deploy a private Android
release until a signed APK and AAB are produced, verified, installed, and pass
runtime/reopen acceptance. Windows may be used only as an unsigned technical
test build, not as a completed closed-beta release.

## Historical unresolved owner actions

1. Reboot or close memory-intensive applications and enable a Windows-managed
   pagefile; alternatively approve a deliberate reduction of Gradle JVM limits.
2. Run one controlled `flutter build apk --release` attempt.
3. Verify the resulting APK package/version and Enos certificate with
   `apksigner verify --print-certs`; do not continue if it is Android Debug.
4. After APK verification passes, run `flutter build appbundle --release` and
   record the APK/AAB paths and sizes.
5. Attach the intended Android test device. Back up any required synthetic data
   before uninstalling an incompatible debug-signed package.
6. Install the signed APK and complete every Android runtime, file-picker,
   backup, CSV, synchronization, and close/reopen step.
7. On Windows, launch the release executable visibly and complete the full
   interactive runtime, file-picker, backup/restore/CSV, sync, and reopen list.
8. Create two same-password backups, prove they differ, then manually prove
   wrong-password and disposable corruption rejection.
9. Complete restore-as-new and disposable matching-replacement acceptance.
10. Inspect the filtered CSV ZIP in Excel, including formula-neutralization
    rows and estimated-count agreement.
11. Complete the same-Enos-account Windows/phone topology and the full
    Enos/Grace hosted-sync, delete, conflict, offline, denial, and reopen matrix.
12. Record every result using PASS, FAIL, NOT RUN, or BLOCKED. Mark D14 complete
    only when all completion-gate items pass and no critical defect remains.

## Historical D14A recovery addendum — 2026-07-30

| Gate | Result |
|---|---|
| Effective Gradle memory | PASS — 4096 MiB heap, 1024 MiB metaspace |
| Windows virtual memory | PASS — 9479 MiB pagefile, 15354 MiB free virtual memory at preflight |
| Signing preflight | PASS — external store resolves, alias present, Enos owner certificate, no debug fallback |
| Owner-signed APK build | BLOCKED — the single command was terminated by the execution wrapper before Flutter/Gradle output; no artifact |
| APK signature and identity inspection | BLOCKED — no APK |
| Owner-signed AAB build | BLOCKED — intentionally not attempted because the APK gate failed |
| Android runtime acceptance | BLOCKED — verified signed artifacts are required first |

The exact remaining owner action is to authorize a new controlled artifact
recovery session whose command runner permits the release build to continue to
completion. That session must run one APK build, verify certificate/package/
label/version, and only then run and verify one AAB build. Do not regenerate or
replace the validated keystore.

The later owner retest completed the configured Windows and Android runtime,
backup/restore, CSV, extension-validation, synchronization, and reopen checks.
The final owner acceptance above supersedes this recovery addendum.
