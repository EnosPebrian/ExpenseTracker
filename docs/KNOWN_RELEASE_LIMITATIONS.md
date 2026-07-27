# Known Release Limitations

## Release blockers

- Android APK/AAB currently use the Android Debug certificate through an
  explicit technical-build opt-in. Owner production/upload signing is absent.
- Android runtime smoke and release database reopen have not been run because
  no device or configured emulator is available.
- Windows must be rebuilt after D14C identity/icon changes, then complete its
  interactive smoke and release database reopen checks.
- Web branding source is updated but the post-clean D14C web build remains
  unverified.
- Windows Authenticode signing is absent.

## Non-blocking after release gates pass

- Web is a development preview with in-memory storage and may reset on reload.
- Online quotes do not use a production backend proxy. Public client API keys
  are unsafe and must not be embedded in a distributable client.
- Manual pricing remains the supported offline/no-key fallback.
- Cloud identity, household authorization, invitations, and the guarded
  initial/incremental protocols are implemented when Supabase is configured.
  Remote deployment/pgTAP and real two-device proof remain owner acceptance
  work; there is no conflict-resolution UI or backup/restore workflow yet.
- There is no PIN or biometric application lock.
- There is no Windows installer or automatic updater.
- There are no app-store listing assets.
- There is no price history, historical bid/ask data, or order-book data.
- Historical tracked `.bak` source copies are not referenced by production
  builds; their cleanup remains deferred repository hygiene.

These limitations do not change the version-15 financial or accounting model.
