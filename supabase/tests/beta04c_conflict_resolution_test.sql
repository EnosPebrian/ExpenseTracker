begin;
set local role postgres;
select set_config(
  'search_path',
  format('public,%I', namespace.nspname),
  true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(9);

select has_function('public', 'resolve_sync_conflict', array['uuid','text','uuid','bigint','uuid','text','jsonb'], 'resolution RPC exists');
select function_privs_are('public', 'resolve_sync_conflict', array['uuid','text','uuid','bigint','uuid','text','jsonb'], 'authenticated', array['EXECUTE'], 'authenticated may execute');
select function_privs_are('public', 'resolve_sync_conflict', array['uuid','text','uuid','bigint','uuid','text','jsonb'], 'anon', array[]::text[], 'anonymous cannot execute');
select ok(
  exists(
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_changes'
  ),
  'app_changes is published for Realtime wake-up'
);

insert into auth.users(id, email) values ('10000000-0000-0000-0000-000000000001', 'beta04c@example.test');
insert into public.books(id, name, created_by_user_id, base_currency_code, created_at, updated_at, version, device_id)
values ('20000000-0000-0000-0000-000000000001', 'Resolution book', '10000000-0000-0000-0000-000000000001', 'IDR', now(), now(), 1, 'test');
insert into public.book_memberships(id, book_id, user_id, role, status, created_at, updated_at)
values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner', 'active', now(), now());
insert into public.book_sync_initializations(book_id, status, completed_at)
values ('20000000-0000-0000-0000-000000000001', 'complete', now());

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select is((public.resolve_sync_conflict('20000000-0000-0000-0000-000000000001','books','20000000-0000-0000-0000-000000000001',1,'40000000-0000-0000-0000-000000000001','keepDevice','{"id":"20000000-0000-0000-0000-000000000001","name":"Chosen","base_currency_code":"IDR","created_at":"2026-07-27T00:00:00Z","updated_at":"2026-07-27T00:00:00Z","version":1,"device_id":"test"}'::jsonb)->>'status'), 'resolved', 'member resolves own book');
select is((select version from public.books where id='20000000-0000-0000-0000-000000000001'), 2::bigint, 'resolution increments version');
select is((select count(*) from public.processed_sync_operations where operation_id='40000000-0000-0000-0000-000000000001'), 1::bigint, 'one idempotency row');
select is((public.resolve_sync_conflict('20000000-0000-0000-0000-000000000001','books','20000000-0000-0000-0000-000000000001',1,'40000000-0000-0000-0000-000000000001','keepDevice','{}'::jsonb)->>'status'), 'alreadyResolved', 'duplicate resolution is idempotent');
select is((public.resolve_sync_conflict('20000000-0000-0000-0000-000000000001','books','20000000-0000-0000-0000-000000000001',1,'40000000-0000-0000-0000-000000000002','keepServer',null)->>'status'), 'staleResolution', 'stale expected version rejected');

select * from finish();
rollback;
