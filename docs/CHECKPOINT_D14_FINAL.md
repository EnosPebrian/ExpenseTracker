# D14 Final Checkpoint

## Closure — 2026-08-02

**D14 PASS — Ready for controlled private deployment by Enos and Grace.**

The owner accepts the completed D14 evidence for private household use on
Windows and Android with hosted Supabase synchronization, encrypted backup and
restore, and CSV export. This approval does not claim public production launch,
Play Store publication, enterprise use, web production readiness, or
third-party security certification.

Accepted closure evidence includes configured Windows release runtime;
owner-signed APK and AAB builds; APK verification against the Enos owner
certificate and confirmation that Android Debug did not sign it; Android
installation, launch, authentication, household loading, and close/reopen
persistence; Android-to-Windows transaction synchronization; Windows and
Android backup workflows; encrypted backup validation and safe replacement;
restore without crash or visible corruption; CSV ZIP export and owner content
inspection; and application-level rejection of invalid restore extensions.

The accepted automated baseline is 587 passing Flutter tests with a clean
`flutter analyze`. Web, Windows debug, and Android debug compilation gates also
passed during the latest repair. No verification command was rerun for this
documentation-only closure.

The July 30 failure and recovery notes below are retained as historical audit
records. They are superseded by this owner-approved closure.

## Cloud configuration and Auth-state repair — 2026-07-30

- Configuration validation distinguishes missing, invalid, and initialization
  failure without logging keys or tokens.
- Signed out, restoring, connectivity failure, expired session, and active
  linked membership have separate controller/UI states.
- A saved household link no longer implies that this device is signed in or
  synchronizing.
- Cloud failure never blocks local-first bootstrap or access to local data.
- Household explanatory copy now reflects the completed synchronization
  milestone.
- Release helper validation passes; 560 full tests pass; analyzer and web
  release build pass.

At that checkpoint, D14 remained incomplete because signed Android artifacts
and the owner runtime acceptance matrix were outstanding.

Date: 2026-07-30

## Historical July 30 verdict

**D14 FAIL — Critical blockers remain.**

The owner certificate identity is valid, Windows release compilation and
process startup pass, and the BETA-06 automated baseline remains green.
However, the sole signed Android APK attempt ended in a Gradle JVM
native-memory crash, no signed APK/AAB was produced, no Android target was
attached, and the required backup/restore/CSV/file-picker/runtime acceptance
matrix is incomplete.

## Historical July 30 release state

- SQLite remains version 20; no schema or production code changed.
- Android certificate preflight: PASS.
- Owner-signed APK: FAIL; no artifact.
- Owner-signed AAB: BLOCKED.
- Android runtime/reopen: BLOCKED.
- Windows release build/startup: PASS; interactive runtime NOT RUN;
  Authenticode absent.
- Web build baseline: PASS; interactive preview NOT RUN.
- Manual backup, restore, CSV, file-picker, same-email multi-device, and full
  hosted synchronization acceptance remain open.

See `RELEASE_ACCEPTANCE_RESULTS.md` for the historical evidence and the final
owner-accepted closure record.

## Historical D14A signed-artifact recovery

**D14A BLOCKED — controlled APK launch was interrupted by the execution
wrapper.**

- Effective Gradle JVM args: `-Xmx4096m`, `MaxMetaspaceSize=1024m`, heap dump
  on OOM, UTF-8 file encoding.
- Windows pagefile: 9479 MiB; free virtual memory at preflight: 15354 MiB.
- Owner keystore/alias/certificate preflight: PASS; debug fallback was not set.
- APK: not produced; the sole command was terminated before build output.
- APK signature/package/version verification: BLOCKED because no artifact exists.
- AAB: correctly not attempted because the APK gate did not pass.

No application architecture, calculation, schema, sync, or user-data behavior
changed. Android runtime acceptance may not begin until a later explicitly
authorized controlled build produces and verifies both owner-signed artifacts.

The D14 backup/export repair preserves unresolved historical category snapshots
behind explicit confirmation, places feedback beside each action, and validates
`.ptbackup`/`.zip` results after selection. Those configured owner Windows and
Android retests subsequently passed and are accepted in the closure above.
