begin;
create extension if not exists pgtap;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true)
from pg_extension e join pg_namespace n on n.oid=e.extnamespace
where e.extname='pgtap';
select plan(13);

select ok((select relrowsecurity from pg_class
  where oid='public.transactions'::regclass),
  'transaction RLS remains enabled');
select is((select count(*) from pg_policies where schemaname='public'
  and tablename='transactions'),4::bigint,
  'transaction RLS policies remain unchanged');
select function_privs_are('public','validate_transaction_brokerage_reference',
 array[]::text[],'authenticated',array[]::text[],
 'brokerage validation helper remains non-client-callable');

insert into auth.users(id,aud,role,email,created_at,updated_at) values
 ('e1000000-0000-0000-0000-000000000001','authenticated','authenticated',
  'interest@example.test',now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id)
values ('e2000000-0000-0000-0000-000000000001','Interest','IDR',
 'e1000000-0000-0000-0000-000000000001','test');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('e2000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000001','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('e2000000-0000-0000-0000-000000000001','complete',now());
insert into public.accounts(id,book_id,name,account_type,currency_code,
 opening_balance,created_at,updated_at,version,device_id) values
 ('e3000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001','Brokerage','brokerage','IDR',0,
  now(),now(),1,'test');
insert into public.asset_definitions(id,book_id,display_name,asset_kind,
 currency_code,unit,created_at,updated_at,version,device_id) values
 ('e4000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001','Stock','stock','IDR','share',
  now(),now(),1,'test');

select lives_ok($$insert into public.transactions(id,book_id,title,category,
 account,transaction_date,amount,transaction_type,fee_amount,fee_treatment,
 relation_type,brokerage_account_id,brokerage_activity_type,created_at,
 updated_at,version,device_id) values
 ('e5000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001','Interest','Investment',
  'Brokerage',now(),10000,'investment',0,'none','none',
  'e3000000-0000-0000-0000-000000000001','interest',now(),now(),1,'test')$$,
 'positive instrument-free interest persists');
select ok(exists(select 1 from public.transactions
 where id='e5000000-0000-0000-0000-000000000001'
 and brokerage_activity_type='interest' and asset_definition_id is null),
 'interest persists without instrument attribution');
select throws_ok($$update public.transactions set amount=0
 where id='e5000000-0000-0000-0000-000000000001'$$,
 'P0001','Brokerage activity does not match its authoritative transaction',
 'zero interest is rejected');
select throws_ok($$update public.transactions set amount=-10000
 where id='e5000000-0000-0000-0000-000000000001'$$,
 'P0001','Brokerage activity does not match its authoritative transaction',
 'negative interest is rejected');
select throws_ok($$update public.transactions
 set asset_definition_id='e4000000-0000-0000-0000-000000000001'
 where id='e5000000-0000-0000-0000-000000000001'$$,
 'P0001','Brokerage activity does not match its authoritative transaction',
 'interest cannot reference an instrument');
select throws_ok($$update public.transactions set transaction_type='income'
 where id='e5000000-0000-0000-0000-000000000001'$$,
 'P0001','Brokerage activity does not match its authoritative transaction',
 'interest cannot masquerade as ordinary income');

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.push_book_changes(
 'e2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','e6000000-0000-0000-0000-000000000001',
 'entityType','transactions','entityId','e5000000-0000-0000-0000-000000000002',
 'operationType','upsert','baseVersion',0,'deviceId','interest-client','payload',
 jsonb_build_object('id','e5000000-0000-0000-0000-000000000002',
 'book_id','e2000000-0000-0000-0000-000000000001','title','Interest',
 'category','Investment','account','Brokerage','transaction_date',now(),
 'amount',2500,'transaction_type','investment','fee_amount',0,
 'fee_treatment','none','relation_type','none','brokerage_account_id',
 'e3000000-0000-0000-0000-000000000001','brokerage_activity_type','interest',
 'created_at',now(),'updated_at',now(),'version',1,
 'device_id','interest-client')))))->0->>'status','applied',
 'sync accepts positive interest');
select ok((select brokerage_activity_type='interest'
 and asset_definition_id is null from public.transactions
 where id='e5000000-0000-0000-0000-000000000002'),
 'synced interest round-trips without instrument');

set local role postgres;
select ok(exists(select 1 from jsonb_array_elements(public.pull_book_changes(
 'e2000000-0000-0000-0000-000000000001',0,200)->'changes') c
 where c->>'entity_type'='transactions'
 and c->'snapshot'->>'brokerage_activity_type'='interest'),
 'change feed includes interest activity');
select is((select count(*) from public.transactions
 where brokerage_activity_type='interest'),2::bigint,
 'interest persistence creates no duplicate rows');

select * from finish();
rollback;
