# BETA-03 Complete — Remote Household Authorization

Date: 2026-07-26

## Delivered

- Optional Supabase Flutter bootstrap through public compile-time configuration.
- Email OTP request, code verification, automatic session restoration, and
  remote-only sign-out.
- Separate local profile, household member, Auth user, and book-membership
  identities.
- Idempotent household linking with local owner/Auth-user mapping.
- Idempotent owner invitation creation, signed-in invitation discovery, secure
  email-matched acceptance, and membership retry behavior.
- PostgreSQL authorization schema, remote financial mirror, monotonic change
  sequence, least-privilege grants, explicit authenticated RLS policies, final
  owner protection, and immutable financial `book_id` triggers.
- Cloud Sharing UI with configuration, auth, linking, invitation, membership,
  offline/error, and explicit no-financial-sync states.

## Persistence

- SQLite version: 13.
- Migration: additive v12-to-v13 columns `books.remote_linked_at` and
  `household_members.auth_user_id`.
- Fresh native schema and in-memory web mapping are equivalent for the new
  metadata. Financial records are neither uploaded nor rewritten.

## Verification

- Focused command: 25 tests passed, including 19 new BETA-03 controller, UI,
  migration, round-trip, and web-parity tests.
- Full Flutter suite: 461 tests passed.
- Flutter analyzer: no issues.
- Web release build and Wasm dry run: passed.
- SQL/RLS suite: 19 pgTAP assertions authored in
  `supabase/tests/beta03_rls_test.sql` but not executed because Supabase CLI is
  not installed in this environment.
- Supabase deployment/runtime auth flow: owner action required.

## Configuration and secrets

Flutter contains no project URL, private secret, service-role key, or secret
logging. It accepts `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, with legacy
`SUPABASE_ANON_KEY` support. Server invitation delivery reads its secret only
inside the Edge Function environment. `.env` and Supabase local temp files are
ignored.

## Open scope

BETA-04 remains open for the SQLite outbox, push/pull protocol, server cursor,
idempotent financial transfer, tombstones, conflicts, interruption/retry, and
recovery. Continue using one primary device. D14 remains open and was not
revisited by this milestone.
