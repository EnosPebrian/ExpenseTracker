# Supabase Setup for Cloud Sharing

Apply migrations through `202607270001_beta04c_conflict_resolution.sql`, run
`supabase db reset` and `supabase test db`, and enable Realtime for
`public.app_changes`. Flutter uses only the public URL/publishable key.

Local verification on 2026-07-27 applied the complete migration chain and
passed all 60 pgTAP assertions. Production deployment is still an owner action.

BETA-03 uses Supabase for email OTP identity, household authorization,
memberships, and invitations. BETA-04A adds secured incremental push/pull and
BETA-04B adds controlled initial upload/download. SQLite remains the
operational financial source of truth.

## Owner setup

1. Create or select the Pilgrim Tracker Supabase project.
2. In Authentication, enable Email sign-in and require verified email.
3. Edit the Email Magic Link template to show `{{ .Token }}` as a one-time
   verification code. Configure the production Site URL and allowed redirect
   URLs before distributing the app.
4. Link this repository to the project and apply
   `supabase/migrations/202607260001_beta03_remote_authorization.sql`, followed
   by `202607260002_beta04a_sync_protocol.sql` and
   `202607260003_beta04b_initial_sync.sql`.
5. Configure the Edge Function server environment with
   `SUPABASE_SECRET_KEY`. Use `SUPABASE_SERVICE_ROLE_KEY` only as a legacy
   server-side fallback. Never place either value in Flutter configuration.
6. Deploy `create-book-invitation` with JWT verification enabled.
7. Run Flutter with the public client configuration:

   ```text
   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co
   --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
   ```

   `SUPABASE_ANON_KEY` is accepted only as a legacy public-key fallback.
8. Sign in as Enos, keep Enos selected as the active local member, and choose
   **Link this household**.
9. Choose the Grace local member, enter Grace's verified email, and send the
   invitation. Grace signs in with that exact email and accepts the pending
   invitation.

For a linked CLI with a working local Docker runtime, verify with:

```text
supabase db reset
supabase test db
```

Missing public configuration is supported and displays “Cloud sharing is not
configured”. Cloud failures do not block local startup or local finance.

The BETA-04A pgTAP protocol suite is
`supabase/tests/beta04a_sync_protocol_test.sql`. It covers membership denial,
cross-book validation, insert/update/delete, idempotent retry, version conflict,
tombstones, batch results, ordered pull, empty pull, pagination, and processed-
operation RLS. `supabase/tests/beta04b_initial_sync_test.sql` covers owner
claims, occupied-remote rejection, idempotent batches/completion, authorized
download, and cross-book denial. Do not mark a local book `ready` manually or
run initialization tests with real financial history.

## Secret handling

The Flutter app receives only the Supabase URL and publishable/legacy anon key.
The Edge Function reads the server secret from its environment and never
returns it. Do not commit `.env` files, function secret output, access tokens,
or production dashboard screenshots containing credentials.
