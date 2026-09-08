-- BETA-08H1A1: make Telegram RPC execution explicitly opt-in.
--
-- Existing Supabase projects can grant EXECUTE to API roles through role-
-- specific default privileges. Revoking PUBLIC alone therefore does not
-- remove effective anon/authenticated access.

-- Authenticated household members call these through telegram-connection.
revoke execute on function public.telegram_connection_status(uuid)
  from public, anon;
revoke execute on function public.issue_telegram_pairing_token(
  uuid, uuid, text, timestamptz
) from public, anon;
revoke execute on function public.disconnect_telegram_connection(uuid)
  from public, anon;

grant execute on function public.telegram_connection_status(uuid)
  to authenticated, service_role;
grant execute on function public.issue_telegram_pairing_token(
  uuid, uuid, text, timestamptz
) to authenticated, service_role;
grant execute on function public.disconnect_telegram_connection(uuid)
  to authenticated, service_role;

-- The Telegram webhook is the sole caller of these service operations.
revoke execute on function public.telegram_claim_ingestion_event(
  bigint, bigint, bigint, bigint, text
) from public, anon, authenticated;
revoke execute on function public.telegram_consume_pairing_token(
  bigint, text, bigint, bigint
) from public, anon, authenticated;
revoke execute on function public.telegram_revoke_connection(
  bigint, bigint, bigint
) from public, anon, authenticated;
revoke execute on function public.telegram_finish_ingestion_event(
  bigint, text, text
) from public, anon, authenticated;
revoke execute on function public.create_telegram_import_review(
  bigint, uuid, jsonb, jsonb
) from public, anon, authenticated;

grant execute on function public.telegram_claim_ingestion_event(
  bigint, bigint, bigint, bigint, text
) to service_role;
grant execute on function public.telegram_consume_pairing_token(
  bigint, text, bigint, bigint
) to service_role;
grant execute on function public.telegram_revoke_connection(
  bigint, bigint, bigint
) to service_role;
grant execute on function public.telegram_finish_ingestion_event(
  bigint, text, text
) to service_role;
grant execute on function public.create_telegram_import_review(
  bigint, uuid, jsonb, jsonb
) to service_role;
