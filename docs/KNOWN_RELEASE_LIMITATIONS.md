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

## BETA-07A/B limitations

- Budgets are monthly, household-level, expense-category limits only.
- Copying is explicit and add-missing-only; there is no bulk overwrite or
  automatic monthly copy.
- There is no rollover, weekly/yearly planning, per-member/account budgets,
  forecasting, suggestions, notifications, goals, or debt planning.
- Derived totals are calculated locally and are not persisted.
- Legacy transactions retain category-name snapshots rather than category UUIDs;
  a later category rename does not rewrite historical transactions.
- Web budget persistence remains an in-memory development preview.
- The BETA-07 schema is hosted and configured release artifacts exist, but
  BETA-07A/B are unreleased until Windows/Android owner runtime acceptance is
  complete.

These limitations do not change the version-21 financial or accounting model.

- Hosted reconnect is deliberately download-first. Local-only changes made
  after a replacement restore are not merged or uploaded; retain the mandatory
  pre-reconnect encrypted backup if those changes may need manual recovery.
- BETA-07C1 requires owner validation on both Windows and Android before the
  broader BETA-07C acceptance checkpoint can pass.

- Legacy transactions contain a category-name snapshot rather than a category
  UUID. When its current definition is absent, exports preserve the snapshot
  after an explicit warning; they cannot reconstruct a deleted UUID.

## BETA-08A recovery limitations

- Recovery is same-household only; it does not merge independent households.
- Changed records keep current state and hosted tombstones cannot be explicitly
  resurrected in this milestone.
- Household/member authority and manual market prices are preview-only.
- Linked recovery cannot commit offline because hosted inspection is mandatory.
- CSV, receipt, statement, Telegram, and automatic categorization ingestion are
  deferred to later reviewed-import milestones.

## BETA-08A1 restore lifecycle limitations

- Restore and Reconnect do not merge independently modified histories.
- Create new shared household intentionally clones to a separate identity; it
  does not repurpose or overwrite the historical hosted household.
- A linked clone whose initial upload is interrupted uses the existing resumable
  initial-upload flow; it is not presented as Synced until completion.
- v1 backups retain the existing pre-budget compatibility behavior.
# BETA-08B limitations

- CSV v1 imports only income and expense into one selected account.
- Projects, transfers, automatic FX conversion, OCR/PDF, and merchant learning
  are not imported.
- Reference and note are review metadata because schema v21 has no separate
  transaction columns for them.
- The “current import” transaction filter is session-only.
- Unconfirmed review drafts are discarded when the app closes.
- Duplicate comparison uses the account-name snapshot after stable-ID checks,
  matching the current transaction schema.

## BETA-08C/D limitations

- Receipt and statement extraction needs connectivity, a signed-in Supabase
  session, deployed Edge Function, and configured provider secrets.
- Pilgrim does not retain documents, queue offline extraction, crop images,
  split receipt line items, classify categories with AI, or store extraction
  sessions.
- Password-protected PDFs and mixed PDF/image sessions are unsupported.
- Provider extraction is advisory and may require manual correction; balance
  mismatch is review evidence rather than accounting authority.
- Owner runtime acceptance for BETA-08A1, BETA-08B, BETA-08C, and BETA-08D
  remains deferred.

## BETA-08E limitations

- Rules apply only to reviewed ingestion drafts, not manual entry or existing
  transactions.
- Matching is deliberately limited to contains, equals, and starts-with; there
  is no regex, fuzzy/semantic matching, AI categorization, or automatic learning.
- A deleted category/account disables active suggestion until the user edits
  the retained historical rule.
- Rules are in encrypted backup v3 but intentionally absent from reporting CSV.
- BETA-08E owner runtime acceptance is NOT RUN. BETA-08A1/B/C/D owner runtime
  acceptance also remains deferred.

## BETA-08F0 limitations

- Automatic internal-transfer matching is intentionally not implemented.
- Legacy one-row transfers are not automatically converted because their route
  text cannot prove durable source/destination identities.
- Canonical v1 pairs require equal amounts and one shared currency; exchange
  rate and fee-split transfer models are future work.
- Conflict resolution is conservative and may require explicit user review
  instead of merging a partially edited pair.
- Owner runtime acceptance for BETA-08F0 remains **NOT RUN**.

## BETA-08F1 limitations

- Matching is one-to-one, exact-amount, same-currency, and limited to ±2 local
  calendar days; FX, fee inference, and split transfers are deferred.
- Suggestions use current device data and are never auto-confirmed.
- “Not a transfer” is session-only; review decisions are not persisted.
- Existing-review bulk conversion is pair-atomic and reports per pair.
- Owner runtime acceptance for BETA-08F1 and consolidated BETA-08F is **NOT RUN**.

## BETA-08G limitations

- Import Inbox stores normalized sensitive drafts but not original CSV, PDF, or
  image files; a secondary device cannot reopen the original source.
- Pending/completed inbox workflow is excluded from encrypted backup v4 and
  Recover missing records; local-only inboxes are therefore device-persistent,
  not portable disaster recovery.
- Card counts are lightweight saved summaries; detailed duplicate/transfer/rule
  analysis refreshes only when review opens.
- Completed normalized drafts are retained for reconciliation and audit; user
  deletion of completed history is deferred.
- Hosted BETA-08E, BETA-08F0, and BETA-08G migrations and the extraction Edge
  Function remain undeployed.
- Telegram ingestion is documentation-only. No bot, webhook, login, chat ID,
  command, or token handling exists.
- Owner runtime acceptance for BETA-08A1 through BETA-08G remains **NOT RUN**.

## BETA-08G1 limitations

- Owner/runtime acceptance remains **NOT RUN** and is intentionally deferred.
- Hosted BETA-08E, BETA-08F0, BETA-08G, and BETA-08G1 migrations remain
  undeployed; local engineering verification does not claim hosted readiness.
- A migrated v24 bank-statement draft retains its existing final ID, but cannot
  safely change accounts if its original extractor row key was not persisted;
  reimport the source instead.
- Unresolved drafts cannot run account-specific rules, exact-ID duplicate
  analysis, or transfer matching until an account is selected.
- Telegram engineering is implemented but undeployed; owner acceptance is NOT
  RUN and no real bot credentials or webhook are configured.
- Telegram v1 supports private chats only and does not reconstruct media groups;
  multi-page image statements require one PDF or direct app import.
- Telegram accepts only canonical Pilgrim CSV; arbitrary column mapping remains
  an in-app workflow.

## BETA-08H1 deployment limitations

- The expected hosted project was inactive during the 2026-08-31 read-only
  preflight, so remote migration ancestry and schema drift could not be
  verified.
- No hosted recovery point was listed (PITR disabled; no managed backups), so
  the database deployment safety gate is blocked.
- The required OpenAI model/key and Telegram bot/webhook secrets are not
  configured. No secret values are stored in the repository.
- BETA-08E/F0/G/G1/H migrations and the extraction/Telegram Edge Functions
  remain undeployed; no Telegram webhook is registered by this milestone run.
- Telegram supports private chats only, canonical Pilgrim CSV, one image or one
  unlocked PDF source, and no Telegram media-group reconstruction.
- Hosted Deployment PASS and consolidated BETA-08A1 through BETA-08H Owner
  Runtime PASS remain pending and must not be inferred from engineering tests.

## BETA-08I statement limitations

- Historical year-end asset/liability valuation is not reliable enough for an
  as-of net-worth figure, so Annual Statements omit it explicitly.
- Very large Annual Account PDFs summarize the ledger by month; generate
  Monthly Account statements for complete transaction-level PDF detail.
- On-screen preview caps very large ledgers for responsiveness; PDF behavior is
  stated explicitly as detailed or summarized.
- A linked household with pending/incomplete synchronization can only report
  records currently available on the device and is labelled accordingly.
- Statements are derived exports and are not stored, synchronized, or included
  in encrypted backup v4.
- Owner runtime acceptance is **NOT RUN**.

## BETA-08J diagnostic limitations

- Health Check is diagnostic only; it does not repair records, retry sync,
  resolve conflicts, or validate a user-selected backup file.
- Recent backup creation time is not persisted reliably, so the screen reports
  backup format v4 support and says recent backup status is not tracked.
- Sync diagnostics use local outbox/cursor/conflict state and do not contact or
  reactivate the currently inactive hosted Supabase project.
- Owner runtime acceptance on Windows and Android is **NOT RUN**.
- Continuous background sync is not promised while Android or Windows has
  suspended or killed Pilgrim; pending work retries on startup/foreground or a
  later mutation/manual wake-up.
- Pending local changes are not recoverable from a different device until they
  successfully synchronize. Local-only households require encrypted backups
  for device-loss recovery.
- BETA-08K owner runtime acceptance is **NOT RUN**. The owner temporarily
  lifted feature freeze only for BETA-08K through BETA-08N; freeze resumes after
  BETA-08N.
