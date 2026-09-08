# BETA-08H1A1 Telegram RPC Privilege Correction

Date: 2026-09-07

## Verdict

**BETA-08H1A1 Security Correction PASS.**

**BETA-08H1A Hosted Schema Rollout PASS.**

This does not constitute BETA-08H1 full Hosted Deployment PASS or Owner
Runtime PASS. Edge Functions, secrets, webhook registration, and live owner
acceptance remain pending.

## Root cause and correction

The applied BETA-08H migration revoked function execution from PostgreSQL
`PUBLIC`, but the hosted project's role-specific default privileges had also
granted execution to `anon`, `authenticated`, and `service_role`. Revoking
`PUBLIC` alone therefore left every Telegram RPC anonymously executable and
left the five webhook-only RPCs executable by authenticated clients.

The new ordered, ACL-only migration
`20260907143317_beta08h1a1_telegram_rpc_privileges.sql` explicitly revokes
`PUBLIC` and `anon` execution from all eight Telegram RPC signatures, revokes
`authenticated` from the five service-only signatures, and explicitly grants
only the intended roles. It changes no function body, table, data, RLS policy,
application source, SQLite schema, or backup format. No applied migration was
edited or repaired for this correction.

## Final privilege matrix

| RPC class | `anon` | `authenticated` | `service_role` | `PUBLIC` ACL |
| --- | --- | --- | --- | --- |
| User-facing three | denied | execute | execute | denied |
| Service-only five | denied | denied | execute | denied |

User-facing RPCs:

- `telegram_connection_status(uuid)`
- `issue_telegram_pairing_token(uuid,uuid,text,timestamptz)`
- `disconnect_telegram_connection(uuid)`

Service-only RPCs:

- `telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text)`
- `telegram_consume_pairing_token(bigint,text,bigint,bigint)`
- `telegram_revoke_connection(bigint,bigint,bigint)`
- `telegram_finish_ingestion_event(bigint,text,text)`
- `create_telegram_import_review(bigint,uuid,jsonb,jsonb)`

Repository call sites confirm the classification. The authenticated
`telegram-connection` function invokes only the three user-facing operations
with the caller's JWT. The `telegram-webhook` function invokes the five
service-only operations through a service-role client. Existing user-facing
function bodies retain their internal authentication and household membership
checks.

## Verification

- Existing recovery point rechecked:
  `C:\Users\enosp\PilgrimTrackerBackups\pre-beta08h1a-20260907-201605`.
  Its five previously hashed SQL files remain present and non-empty.
- Local database reset: PASS through the corrective migration.
- Local pgTAP: 224/224 PASS across 12 files, including 32 new privilege
  assertions. Existing Telegram RLS, lifecycle, idempotency, rate-limit,
  membership, and zero-financial-write tests remain unchanged and passing.
- Remote dry run: exactly one pending migration, the BETA-08H1A1 correction.
- Hosted push: PASS.
- Migration history: local and hosted histories match through
  `20260907143317`; no gap, reset, seed, repair, or manual history mutation.
- Direct hosted ACL totals: anonymous executable 0; authenticated user-facing
  executable 3; authenticated service-only executable 0; service-role
  executable 8; `PUBLIC` executable ACL 0.
- Hosted authorization smoke: all eight anonymous invocations returned
  permission denied; all five authenticated service-only invocations returned
  permission denied; the three authenticated user-facing invocations reached
  normal internal authorization/business validation.
- Telegram pairing-token and ingestion-event client table-grant count: 0.
- Privacy-safe business counts remained users 2, books 1, memberships 2,
  accounts 3, categories 6, transactions 27, and budgets 8. The migration
  changed no business data.
- The security advisor no longer reports anonymous execution for any Telegram
  RPC or authenticated execution for service-only Telegram RPCs. It continues
  to report the three intentionally authenticated user APIs and two expected
  RLS/no-policy information notices for service-only tables.

The 849-test Flutter suite was not rerun because this milestone changed no Dart
source or product behavior.

## Deferred hosted work

- No Edge Function was deployed.
- No OpenAI or Telegram secret was configured.
- No Telegram webhook or external API call was made.
- Owner runtime and consolidated acceptance remain NOT RUN.
- BETA-08H1 full Hosted Deployment remains pending.

BETA-08L0 Engineering and BETA-08H1A Hosted Schema Rollout now pass. The
separately scoped BETA-08L milestone may begin.
