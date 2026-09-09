begin;
create extension if not exists pgtap;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true)
from pg_extension e join pg_namespace n on n.oid=e.extnamespace
where e.extname='pgtap';
select plan(23);

select has_column('public','transactions','note','transaction note exists');
select has_column('public','transactions','reference','transaction reference exists');
select is((select is_nullable from information_schema.columns where table_schema='public'
 and table_name='transactions' and column_name='note'),'YES','note is nullable');
select is((select is_nullable from information_schema.columns where table_schema='public'
 and table_name='transactions' and column_name='reference'),'YES','reference is nullable');
select ok('note'=any(public.initial_sync_allowed_fields('transactions')),
 'initial sync allows note');
select ok('reference'=any(public.initial_sync_allowed_fields('transactions')),
 'initial sync allows reference');
select ok((select relrowsecurity from pg_class where oid='public.transactions'::regclass),
 'transaction RLS remains enabled');
select is((select count(*) from pg_policies where schemaname='public'
 and tablename='transactions'),4::bigint,'transaction RLS policies unchanged');

insert into auth.users(id,aud,role,email,created_at,updated_at) values
 ('c1000000-0000-0000-0000-000000000001','authenticated','authenticated',
  'm0@example.test',now(),now()),
 ('c1000000-0000-0000-0000-000000000002','authenticated','authenticated',
  'other-m0@example.test',now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('c2000000-0000-0000-0000-000000000001','M0','IDR',
  'c1000000-0000-0000-0000-000000000001','test'),
 ('c2000000-0000-0000-0000-000000000002','Other M0','IDR',
  'c1000000-0000-0000-0000-000000000002','test');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('c2000000-0000-0000-0000-000000000001',
  'c1000000-0000-0000-0000-000000000001','owner','active'),
 ('c2000000-0000-0000-0000-000000000002',
  'c1000000-0000-0000-0000-000000000002','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('c2000000-0000-0000-0000-000000000001','complete',now());

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);

select is((public.push_book_changes(
 'c2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','c5000000-0000-0000-0000-000000000001',
 'entityType','transactions','entityId','c4000000-0000-0000-0000-000000000001',
 'operationType','upsert','baseVersion',0,'deviceId','old-client','payload',
 jsonb_build_object('id','c4000000-0000-0000-0000-000000000001',
 'book_id','c2000000-0000-0000-0000-000000000001','title','Lunch',
 'category','Food','account','Cash','transaction_date',now(),'amount',100,
 'transaction_type','expense','fee_amount',0,'fee_treatment','none',
 'relation_type','none','created_at',now(),'updated_at',now(),
 'version',1,'device_id','old-client')))))->0->>'status','applied',
 'old-client create without metadata succeeds');
select ok((select note is null and reference is null from public.transactions
 where id='c4000000-0000-0000-0000-000000000001'),
 'old-client create stores null metadata');

select is((public.push_book_changes(
 'c2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','c5000000-0000-0000-0000-000000000002',
 'entityType','transactions','entityId','c4000000-0000-0000-0000-000000000001',
 'operationType','upsert','baseVersion',1,'deviceId','new-client','payload',
 (select to_jsonb(t)||jsonb_build_object('note','Trip dinner with Grace',
  'reference','INV-123') from public.transactions t
  where id='c4000000-0000-0000-0000-000000000001')))))->0->>'status','applied',
 'new-client metadata update succeeds');
select is((select note from public.transactions
 where id='c4000000-0000-0000-0000-000000000001'),
 'Trip dinner with Grace','new-client note round trips');
select is((select reference from public.transactions
 where id='c4000000-0000-0000-0000-000000000001'),
 'INV-123','new-client reference round trips');
select ok((select id='c4000000-0000-0000-0000-000000000001'::uuid
 and book_id='c2000000-0000-0000-0000-000000000001'::uuid
 from public.transactions where id='c4000000-0000-0000-0000-000000000001'),
 'metadata update preserves transaction and household identity');

select is((public.push_book_changes(
 'c2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','c5000000-0000-0000-0000-000000000003',
 'entityType','transactions','entityId','c4000000-0000-0000-0000-000000000001',
 'operationType','upsert','baseVersion',2,'deviceId','old-client','payload',
 (select (to_jsonb(t)-'note'-'reference')||jsonb_build_object('title','Dinner')
  from public.transactions t
  where id='c4000000-0000-0000-0000-000000000001')))))->0->>'status','applied',
 'old-client update omitting metadata succeeds');
select ok((select note='Trip dinner with Grace' and reference='INV-123'
 from public.transactions where id='c4000000-0000-0000-0000-000000000001'),
 'omitted properties preserve metadata');

select is((public.push_book_changes(
 'c2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','c5000000-0000-0000-0000-000000000004',
 'entityType','transactions','entityId','c4000000-0000-0000-0000-000000000001',
 'operationType','upsert','baseVersion',3,'deviceId','new-client','payload',
 (select to_jsonb(t)||'{"note":null,"reference":null}'::jsonb
  from public.transactions t
  where id='c4000000-0000-0000-0000-000000000001')))))->0->>'status','applied',
 'explicit null update succeeds');
select ok((select note is null and reference is null from public.transactions
 where id='c4000000-0000-0000-0000-000000000001'),
 'explicit null clears metadata');

select throws_ok($$select public.push_book_changes(
 'c2000000-0000-0000-0000-000000000002','[]'::jsonb)$$,
 'P0001','Active book membership required',
 'cross-household push remains rejected');

set local role postgres;
select is((select count(*) from public.transactions),1::bigint,
 'metadata sync creates no unintended financial rows');
select throws_ok($$update public.transactions set reference=repeat('x',257)
 where id='c4000000-0000-0000-0000-000000000001'$$,'23514',null,
 'reference length is constrained');
select throws_ok($$update public.transactions set note=repeat('x',4001)
 where id='c4000000-0000-0000-0000-000000000001'$$,'23514',null,
 'note length is constrained');
select ok(exists(select 1 from jsonb_array_elements(public.pull_book_changes(
 'c2000000-0000-0000-0000-000000000001',0,200)->'changes') c
 where c->>'entity_type'='transactions' and c->'snapshot' ? 'note'
 and c->'snapshot' ? 'reference'),'change feed includes metadata properties');

select * from finish();
rollback;
