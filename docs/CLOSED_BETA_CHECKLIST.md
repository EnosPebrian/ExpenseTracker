# Closed-Beta Checklist

## D14 closure — 2026-08-02

- [x] **D14 PASS — Ready for controlled private deployment by Enos and Grace.**
- [x] Private household use by Enos and Grace is approved on Windows and Android.
- [x] Hosted Supabase synchronization is approved for the controlled deployment.
- [x] Encrypted backup and restore are approved.
- [x] CSV export is approved.
- [x] Configured Windows release builds and runs.
- [x] Owner-signed Android APK and AAB build.
- [x] APK verifies with the Enos owner certificate and is not Android Debug signed.
- [x] Android installs, launches, authenticates, and loads the existing household.
- [x] Android-to-Windows transaction synchronization works.
- [x] Close/reopen preserves session, household, data, and synchronized state.
- [x] Windows and Android backup workflows work.
- [x] Encrypted backup creation, validation, and replacement safety backup work.
- [x] Restore completes without crash or visible corruption.
- [x] CSV ZIP export succeeds and owner inspection is accepted.
- [x] Invalid restore extensions are rejected by application-level validation.
- [x] Automated baseline: 587 tests passed; analyzer clean.
- [x] Latest repair compilation gates: web, Windows debug, and Android debug passed.

Not claimed: public production launch, Play Store publication, enterprise use,
web production readiness, or third-party security certification.

The dated incomplete checklists below are retained as historical evidence and
are superseded by this closure.

## D14 backup/export retest

- [ ] Windows backup warning confirms and saves `.ptbackup`.
- [ ] Android backup and CSV warning confirms and saves the correct extension.
- [ ] Restore rejects JPEG, PNG, ZIP, PDF, and wrong extensions.
- [ ] Cross-household reference remains blocked.

## D14 cloud/Auth state repair — 2026-07-30

- [x] Missing, whitespace, malformed URL, and missing-key builds are diagnosed.
- [x] Configured signed-out state does not show a false connection failure.
- [x] Session restoration, expiry, and real connectivity failure are distinct.
- [x] Saved household linkage and current device sign-in are shown separately.
- [x] Household synchronization copy reflects BETA-04 completion.
- [x] Local data remains accessible while signed out or offline.
- [x] Release helper rejects missing/placeholders without printing the key.
- [x] Focused tests pass; 560 full tests pass; analyzer clean; web build passes.
- [ ] Owner Windows/Android runtime checks remain required.
- [ ] D14 complete — NO.

- [x] BETA-04C conflict review/resolution and Realtime wake-up implemented locally.
- [ ] Deploy BETA-04C migration and complete Enos/Grace BETA-05 acceptance.

Status date: 2026-07-30

## BETA-01 product readiness

- [x] Accounts use stable structured records while legacy name-based forms remain compatible.
- [x] Starting balances are dated account metadata, not transactions.
- [x] Account balances apply active cash effects on/after the effective local date.
- [x] Starting balances are isolated from reporting, tithe, and portfolio accounting.
- [x] First-run local profile collects display name and default currency.
- [x] Existing native data migrates to SQLite version 11 with a safe local profile.
- [x] Web preview has equivalent in-memory account/profile behavior.

## BETA-02 household foundation

- [x] Existing data migrates into one financial book at SQLite version 12.
- [x] The local profile becomes the first owner member.
- [x] Active book and member persist locally.
- [x] Accounts support joint/member ownership without changing balances.
- [x] New transactions record active-member attribution without changing accounting.
- [x] Native and web stores scope applicable records by active book.
- [x] Cloud authentication, invitations, and RLS authorization are available.
- [x] Durable incremental outbox/push/pull protocol is implemented.
- [ ] Initial household upload/download is complete.
- [ ] Conflict review/resolution is complete.
- [ ] Enos/Grace two-device acceptance is complete.

## Identity and branding

- [x] Android ID is permanently `com.enospebrian.pilgrimtracker`.
- [x] Windows company is `Enos Pebrian`.
- [x] Product name is `Pilgrim Tracker`.
- [x] Original icon is integrated for Android, Windows, and web.
- [x] Version remains `1.0.0+1`.

## Build and signing

- [x] NDK `28.2.13676358` is complete and verified.
- [x] Technical release APK builds.
- [x] Technical release AAB builds.
- [ ] Owner upload keystore and untracked `key.properties` are configured.
- [ ] APK/AAB are rebuilt and verified with the owner certificate.
- [ ] Windows D14C identity/icon release rebuild succeeds.
- [x] Branded web D14C build succeeds.
- [ ] Windows signing remains optional only for a very small direct technical beta.

## Runtime smoke

- [ ] Android release launches on a physical device or emulator.
- [ ] Android checklist items 1-18 pass.
- [ ] Android fresh-data close/reopen persists and uses schema version 15.
- [ ] Windows D14C release launches with the new identity and icon.
- [ ] Windows checklist items 1-16 pass.
- [ ] Windows fresh-data close/reopen persists and uses schema version 15.

## Verified baseline

- [x] Analyzer clean.
- [x] 493 tests pass.
- [x] SQLite version 15.
- [x] No committed secret or private key found.
- [x] Manual pricing works without an API key in the verified application baseline.

## Verdict

- [ ] Controlled closed-beta ready.
- [ ] D14 complete.

Next owner action: generate and securely back up the Android upload keystore,
create untracked `android/key.properties`, connect an Android target, then run
the owner-signed Android builds and both platform smoke/reopen checklists.

## BETA-06 portability acceptance

- [ ] Create two encrypted backups with one password and confirm different files.
- [ ] Reject a wrong password and corrupt backup without local data changes.
- [ ] Restore as new and compare counts and accounting totals.
- [ ] Confirm an unrelated existing household remains unchanged.
- [ ] Cancel the safety-backup save and confirm replacement is cancelled.
- [ ] Complete matching replacement and verify cloud state is local-only.
- [ ] Inspect filtered CSV for UTF-8, exact money, dates, and formula safety.
- [ ] Verify scoped Windows and Android open/save behavior on owner devices.
- [ ] Relink only after explicit cloud reconciliation.

## D14 Final acceptance — 2026-07-30

- [x] Owner keystore and alias inspected without exposing credentials.
- [x] Owner certificate matches the expected Enos identity and is not Android Debug.
- [ ] Owner-signed release APK builds and passes `apksigner` verification — FAIL: Gradle JVM native-memory exhaustion.
- [ ] Owner-signed AAB builds — BLOCKED by APK failure.
- [ ] Android release installs, runs, and survives close/reopen — BLOCKED: no attached target or signed APK.
- [x] Windows release executable builds with correct product/company/version metadata.
- [x] Windows release process starts and responds.
- [ ] Windows interactive runtime, file-picker, portability, sync, and reopen checklist — NOT RUN.
- [ ] Backup creation/wrong-password/corruption owner acceptance — NOT RUN.
- [ ] Restore-as-new and replacement owner acceptance — NOT RUN.
- [ ] CSV/Excel/filter/formula owner acceptance — NOT RUN.
- [ ] Same-Enos-account independent-database two-device acceptance — NOT RUN.
- [ ] Complete Enos/Grace hosted-sync matrix — NOT RUN; earlier evidence is partial.
- [ ] Controlled closed-beta ready — FAIL.
- [ ] D14 complete — FAIL; critical blockers remain.

## D14A signed-artifact recovery — 2026-07-30

- [x] Gradle JVM limits reduced to 4096 MiB heap and 1024 MiB metaspace.
- [x] Windows pagefile confirmed at 9479 MiB.
- [x] Owner keystore, alias, certificate, and release-signing path pass preflight.
- [ ] Owner-signed APK produced — BLOCKED: sole build command was interrupted by the execution wrapper before build output.
- [ ] APK signature/package/label/version verified — BLOCKED: no artifact.
- [ ] Owner-signed AAB produced and verified — BLOCKED by APK gate.
- [ ] Android runtime acceptance may begin — NO.
