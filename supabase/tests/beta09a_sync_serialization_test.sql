begin;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true)
from pg_extension e join pg_namespace n on n.oid=e.extnamespace
where e.extname='pgtap';
select plan(8);
select ok(position('pg_advisory_xact_lock(hashtextextended(p_book_id::text, 0))'
  in pg_get_functiondef('public.push_book_changes_pre_beta08n0(uuid,jsonb)'::regprocedure)) > 0,
  'push serializes base version check and write using initialization lock');
select ok(position('pg_advisory_xact_lock(hashtextextended(p_book_id::text, 0))'
  in pg_get_functiondef('public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure)) > 0,
  'resolution shares the same household lock');
select function_privs_are('public','push_book_changes',array['uuid','jsonb'],
  'authenticated',array['EXECUTE'],'authenticated public push boundary retained');
select function_privs_are('public','push_book_changes_pre_beta08n0',array['uuid','jsonb'],
  'authenticated',array[]::text[],'implementation remains inaccessible');
select function_privs_are('public','resolve_sync_conflict',
  array['uuid','text','uuid','bigint','uuid','text','jsonb'],
  'anon',array[]::text[],'anonymous resolution remains denied');
select ok((select relrowsecurity from pg_class where oid='public.transactions'::regclass),
  'transaction RLS retained');
select is((public.resolve_sync_conflict('e2000000-0000-0000-0000-000000000001',
  'transactions','e5000000-0000-0000-0000-000000000001',1,
  'e6000000-0000-0000-0000-000000000001','keepServer',null)->>'status'),
  'unauthorized','no identity cannot resolve');
select throws_ok($$select public.push_book_changes(
  'e2000000-0000-0000-0000-000000000001','[]'::jsonb)$$,
  'P0001','Active book membership required','no membership cannot push');
select * from finish();
rollback;
