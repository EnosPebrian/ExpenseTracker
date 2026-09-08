begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path', format('public,%I', namespace.nspname), true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(32);

-- No Telegram RPC may be reachable anonymously.
select ok(
  not has_function_privilege('anon', rpc.signature, 'EXECUTE'),
  format('anon cannot execute %s', rpc.name)
)
from (values
  ('telegram_connection_status',
    'public.telegram_connection_status(uuid)'),
  ('issue_telegram_pairing_token',
    'public.issue_telegram_pairing_token(uuid,uuid,text,timestamptz)'),
  ('disconnect_telegram_connection',
    'public.disconnect_telegram_connection(uuid)'),
  ('telegram_claim_ingestion_event',
    'public.telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text)'),
  ('telegram_consume_pairing_token',
    'public.telegram_consume_pairing_token(bigint,text,bigint,bigint)'),
  ('telegram_revoke_connection',
    'public.telegram_revoke_connection(bigint,bigint,bigint)'),
  ('telegram_finish_ingestion_event',
    'public.telegram_finish_ingestion_event(bigint,text,text)'),
  ('create_telegram_import_review',
    'public.create_telegram_import_review(bigint,uuid,jsonb,jsonb)')
) as rpc(name, signature);

-- PUBLIC must not be an indirect source of execution for any RPC.
select ok(
  not exists (
    select 1
    from pg_proc procedure
    cross join lateral aclexplode(
      coalesce(
        procedure.proacl,
        acldefault('f', procedure.proowner)
      )
    ) privilege
    where procedure.oid = to_regprocedure(rpc.signature)
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  format('PUBLIC cannot execute %s', rpc.name)
)
from (values
  ('telegram_connection_status',
    'public.telegram_connection_status(uuid)'),
  ('issue_telegram_pairing_token',
    'public.issue_telegram_pairing_token(uuid,uuid,text,timestamptz)'),
  ('disconnect_telegram_connection',
    'public.disconnect_telegram_connection(uuid)'),
  ('telegram_claim_ingestion_event',
    'public.telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text)'),
  ('telegram_consume_pairing_token',
    'public.telegram_consume_pairing_token(bigint,text,bigint,bigint)'),
  ('telegram_revoke_connection',
    'public.telegram_revoke_connection(bigint,bigint,bigint)'),
  ('telegram_finish_ingestion_event',
    'public.telegram_finish_ingestion_event(bigint,text,text)'),
  ('create_telegram_import_review',
    'public.create_telegram_import_review(bigint,uuid,jsonb,jsonb)')
) as rpc(name, signature);

-- Household-facing operations remain available to authenticated users and
-- server-side callers.
select ok(
  has_function_privilege('authenticated', rpc.signature, 'EXECUTE'),
  format('authenticated can execute %s', rpc.name)
)
from (values
  ('telegram_connection_status',
    'public.telegram_connection_status(uuid)'),
  ('issue_telegram_pairing_token',
    'public.issue_telegram_pairing_token(uuid,uuid,text,timestamptz)'),
  ('disconnect_telegram_connection',
    'public.disconnect_telegram_connection(uuid)')
) as rpc(name, signature);

select ok(
  has_function_privilege('service_role', rpc.signature, 'EXECUTE'),
  format('service_role can execute %s', rpc.name)
)
from (values
  ('telegram_connection_status',
    'public.telegram_connection_status(uuid)'),
  ('issue_telegram_pairing_token',
    'public.issue_telegram_pairing_token(uuid,uuid,text,timestamptz)'),
  ('disconnect_telegram_connection',
    'public.disconnect_telegram_connection(uuid)')
) as rpc(name, signature);

-- Webhook-only operations must remain denied to signed-in clients and
-- available only to the service role.
select ok(
  not has_function_privilege('authenticated', rpc.signature, 'EXECUTE'),
  format('authenticated cannot execute %s', rpc.name)
)
from (values
  ('telegram_claim_ingestion_event',
    'public.telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text)'),
  ('telegram_consume_pairing_token',
    'public.telegram_consume_pairing_token(bigint,text,bigint,bigint)'),
  ('telegram_revoke_connection',
    'public.telegram_revoke_connection(bigint,bigint,bigint)'),
  ('telegram_finish_ingestion_event',
    'public.telegram_finish_ingestion_event(bigint,text,text)'),
  ('create_telegram_import_review',
    'public.create_telegram_import_review(bigint,uuid,jsonb,jsonb)')
) as rpc(name, signature);

select ok(
  has_function_privilege('service_role', rpc.signature, 'EXECUTE'),
  format('service_role can execute %s', rpc.name)
)
from (values
  ('telegram_claim_ingestion_event',
    'public.telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text)'),
  ('telegram_consume_pairing_token',
    'public.telegram_consume_pairing_token(bigint,text,bigint,bigint)'),
  ('telegram_revoke_connection',
    'public.telegram_revoke_connection(bigint,bigint,bigint)'),
  ('telegram_finish_ingestion_event',
    'public.telegram_finish_ingestion_event(bigint,text,text)'),
  ('create_telegram_import_review',
    'public.create_telegram_import_review(bigint,uuid,jsonb,jsonb)')
) as rpc(name, signature);

select * from finish();
rollback;
