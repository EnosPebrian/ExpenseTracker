# Known Release Limitations

## Cloud configuration and device-session behavior

Cloud-enabled releases require valid `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` compile-time values. A saved household link is local
metadata and can remain present while the device is signed out, offline, or
running an unconfigured build. None of those states deletes or hides local
financial data. Auth connectivity is checked only through existing repository
operations; the app does not continuously ping Supabase.

- Existing installations that received the legacy demo dataset are not cleaned
  automatically because its generated IDs do not safely prove ownership. Follow
  `FRESH_INSTALL_DATA_POLICY.md` to back up and reset the local database.

- Realtime is best-effort wake-up only; missed events rely on normal cursor sync.
  Hosted two-device synchronization is accepted for the controlled private
  deployment.

## Non-blocking limitations for controlled private deployment

- The Windows executable is not Authenticode-signed.
- Web remains an in-memory development preview and is not approved for
  production use.
- There is no scheduled or cloud-provider backup automation.
- Restore does not merge independently modified household histories.
- `file_picker` emits a forward-looking Kotlin compatibility warning.
- Backup and CSV filename extensions may later be appended automatically as UX
  polish; current application-level validation remains authoritative.

- Web is a development preview with in-memory storage and may reset on reload.
- Online quotes do not use a production backend proxy. Public client API keys
  are unsafe and must not be embedded in a distributable client.
- Manual pricing remains the supported offline/no-key fallback.
- Cloud identity, household authorization, invitations, and the guarded
  initial/incremental protocols are implemented when Supabase is configured.
  Backup restore deliberately returns to local-only state and does not
  automate cloud reconciliation or merge independently changed histories.
- Backup passwords cannot be recovered. Users must retain passwords and
  `.ptbackup` files; there is no provider-hosted or scheduled backup in BETA-06.
- Desktop export refuses to overwrite an existing selected file; choose a new
  filename. Web backup parity uses the non-durable in-memory preview.
- There is no PIN or biometric application lock.
- There is no Windows installer or automatic updater.
- There are no app-store listing assets.
- There is no price history, historical bid/ask data, or order-book data.
- Historical tracked `.bak` source copies are not referenced by production
  builds; their cleanup remains deferred repository hygiene.

These limitations do not change the version-20 financial or accounting model.

- Legacy transactions contain a category-name snapshot rather than a category
  UUID. When its current definition is absent, exports preserve the snapshot
  after an explicit warning; they cannot reconstruct a deleted UUID.
