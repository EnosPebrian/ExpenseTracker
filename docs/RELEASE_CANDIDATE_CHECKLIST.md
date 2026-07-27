# Release-Candidate Checklist

Status date: 2026-07-24

## Identity and metadata

- [x] Product/display name is `Pilgrim Tracker`.
- [x] Android ID is `com.enospebrian.pilgrimtracker`.
- [x] Windows company metadata is `Enos Pebrian`.
- [x] Original product icon replaces Flutter template icons.
- [x] Version remains `1.0.0+1`.

## Engineering baseline

- [x] SQLite schema version is 10.
- [x] Analyzer baseline is clean.
- [x] Full-suite baseline is 401 passing tests.
- [x] No production Dart changed in D14C; expensive checks were not rerun.
- [x] No committed Alpha Vantage key or signing secret was found.
- [x] Missing API key remains supported through manual pricing.

## Android

- [x] NDK `28.2.13676358` is repaired and verified.
- [x] INTERNET permission and SDK 24/36/36 are configured.
- [x] Technical APK and AAB build with the permanent package identity.
- [x] Artifact identity and Android Debug certificate were inspected.
- [ ] Configure the owner-controlled upload key.
- [ ] Rebuild APK/AAB with the owner certificate.
- [ ] Run Android smoke steps 1-18 and release database reopen.

## Windows

- [x] D14B release build and process startup passed.
- [x] Permanent company/product metadata and new ICO are in source.
- [ ] Rebuild after D14C identity/icon changes.
- [ ] Run Windows smoke steps 1-16 and release database reopen.
- [ ] Apply Authenticode signing before broader distribution.

## Web preview

- [x] Title, manifest, colors, favicon, and icons are updated in source.
- [ ] Rebuild after D14C branding changes.
- [x] In-memory storage limitation remains documented.

## Verdict

- [ ] Controlled release candidate approved.
- [ ] D14 complete.

Android and Windows runtime/database proof plus owner Android signing remain the
critical gates. D14C Windows/web rebuilds also remain pending because build-tool
execution approval became unavailable after Android artifact generation.
