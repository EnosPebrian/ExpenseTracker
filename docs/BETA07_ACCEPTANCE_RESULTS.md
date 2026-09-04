# BETA-07 Owner Acceptance Results

**Execution date:** 2026-08-03  
**Verdict:** BETA-07C FAIL — required owner runtime acceptance is not yet run.

This result does not reverse the historical D14 approval. BETA-07A/B remain
engineering-complete and unreleased. No production Dart or SQL source was
changed during this deployment run.

## Deployment and artifact gates

| Check | Result | Evidence |
| --- | --- | --- |
| Existing private hosted project | PASS | Linked project `pilgrim-tracker-dev` (`jylclfebdeaywfdwabph`) is active and was already linked to this workspace. |
| Local migration reset | PASS | All migrations through `202608020001_beta07a_monthly_category_budgets.sql` applied. |
| Local pgTAP | PASS | 81 assertions across five SQL test files passed. |
| Hosted migration push | PASS | Only `202608020001` was pending and it applied successfully. |
| Local/remote migration parity | PASS | Six local and remote migration versions agree through `202608020001`. |
| Remote budget table and RLS | PASS | Remote schema contains `monthly_category_budgets`, RLS is enabled, and all four row policies require `authenticated` active household membership. Supabase's default `anon` table privilege is present, but RLS provides no anonymous row policy; the anonymous-denial pgTAP assertion passed locally against the deployed schema. |
| Existing hosted data safety | PASS | The deployed migration is additive DDL and the push completed transactionally; no hosted reset, manual insert, update, or delete was run. Runtime record inventory was not modified or used for testing. |
| Configured Windows release | PASS | `build\windows\x64\runner\Release\pilgrim_tracker.exe`, 70,144 bytes. |
| Configured release APK | PASS | `build\app\outputs\flutter-apk\app-release.apk`, 65,400,675 bytes. |
| Configured release AAB | PASS | `build\app\outputs\bundle\release\app-release.aab`, 63,716,567 bytes. |
| APK certificate | PASS | One RSA-4096 signer: `CN=Enos Pebrian, OU=Pilgrim Tracker, O=Tebu Nai, L=Denpasar, ST=Bali, C=ID`; APK Signature Scheme v2 verifies and the signer is not Android Debug. |

The release helper obtained the linked project's public publishable key in
memory. Neither the Supabase URL value nor key value was printed by the helper.

## Required owner runtime acceptance

| Acceptance area | Result | Reason or evidence required |
| --- | --- | --- |
| Existing Windows database v20 to v21 | NOT RUN | Install/open the release over the existing synthetic household, verify all prior entity and sync/backup state, then close/reopen. |
| Existing Android database v20 to v21 with `install -r` | NOT RUN | Requires the owner's connected device and matching installed signature; do not uninstall. |
| No duplicate seed data or budgets after reopen | NOT RUN | Must be observed on both upgraded owner installations. |
| Budget create/edit/remove/re-add and duplicate blocking | NOT RUN | Requires the specified Groceries, Transport, and Utilities workflow on Windows and Android. |
| Spending calculations and all six display states | NOT RUN | Requires the specified synthetic income, expense, transfer, opening-balance, conversion, fee, deletion, month, and attribution cases. |
| Month navigation and local-calendar boundaries | NOT RUN | Requires current/previous/next/current action and UTC-boundary observation. |
| Copy preview, cancel, add-missing, repeat/no-op | NOT RUN | Requires source/target data and outbox observation on an owner installation. |
| Cross-device budget synchronization | NOT RUN | Requires distinct Windows and Android local databases and both household sessions. |
| Offline queue and convergence | NOT RUN | Requires disconnect/reconnect testing on both devices. |
| Budget conflict and delete-versus-update review | NOT RUN | Requires divergent offline edits, conflict UI review, resolution, reopen, and convergence. |
| Encrypted backup v2 and restore-as-new | NOT RUN | Requires owner file-picker, password, manifest, restored calculation, and outbox checks. |
| Authentic backup v1 compatibility | NOT RUN | No authentic v1 owner backup was supplied; automated compatibility coverage remains the engineering evidence. |
| CSV ZIP and `budgets.csv` inspection | NOT RUN | Requires owner export and manual inspection of exact values, ordering, UTF-8, and formula neutralization. |
| Historical category lifecycle and cross-book protection | NOT RUN | Requires synthetic archived/deleted category acceptance without corrupting a real household. |

## Automated baseline

- Flutter engineering baseline retained from BETA-07B: **616 passing tests**,
  clean analyzer, web/Wasm pass, Windows debug pass, and Android debug pass.
- No Flutter tests, analyzer, web build, or debug build was rerun because no
  production Dart code changed.
- Local SQL verification was rerun because this milestone deployed SQL:
  `supabase db reset` passed and `supabase test db` passed **81 assertions**.

## Defects and blockers

No production defect was reproduced by the automated deployment and artifact
steps, so no production file or migration was changed. The completion blocker
is missing owner runtime evidence for every required acceptance area above.
Until those checks pass, BETA-07A/B must not be marked released for controlled
private deployment.

## BETA-07C1 recovery repair

The owner-reproduced post-restore local-only dead end is repaired in code.
Configured, initialized, signed-in users with a safe local-member mapping now
receive **Reconnect cloud sharing** and may choose only active hosted
memberships returned through existing RLS. Recovery is download-only, requires
an encrypted safety backup, and creates no outbox mutations. BETA-07C is not
marked passed; Windows/Android owner retesting remains required.
