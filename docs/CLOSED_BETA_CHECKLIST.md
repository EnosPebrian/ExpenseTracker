# Closed-Beta Checklist

Status date: 2026-07-26

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
