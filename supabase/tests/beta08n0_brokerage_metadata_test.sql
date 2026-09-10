begin;
create extension if not exists pgtap;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true)
from pg_extension e join pg_namespace n on n.oid=e.extnamespace
where e.extname='pgtap';
select plan(24);

select has_column('public','transactions','brokerage_account_id',
  'brokerage account identity exists');
select has_column('public','transactions','brokerage_activity_type',
  'brokerage activity type exists');
select has_column('public','transactions','split_numerator',
  'split numerator exists');
select has_column('public','transactions','split_denominator',
  'split denominator exists');
select is((select is_nullable from information_schema.columns
  where table_schema='public' and table_name='transactions'
    and column_name='brokerage_account_id'),'YES','brokerage metadata is additive');
select ok('brokerage_account_id'=any(public.initial_sync_allowed_fields('transactions')),
  'initial sync allows brokerage account identity');
select ok('brokerage_activity_type'=any(public.initial_sync_allowed_fields('transactions')),
  'initial sync allows brokerage activity type');
select ok('split_numerator'=any(public.initial_sync_allowed_fields('transactions'))
  and 'split_denominator'=any(public.initial_sync_allowed_fields('transactions')),
  'initial sync allows split ratio');
select ok((select relrowsecurity from pg_class
  where oid='public.transactions'::regclass),'transaction RLS remains enabled');
select is((select count(*) from pg_policies where schemaname='public'
  and tablename='transactions'),4::bigint,'transaction RLS policies unchanged');

insert into auth.users(id,aud,role,email,created_at,updated_at) values
 ('d1000000-0000-0000-0000-000000000001','authenticated','authenticated',
  'broker@example.test',now(),now()),
 ('d1000000-0000-0000-0000-000000000002','authenticated','authenticated',
  'other-broker@example.test',now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('d2000000-0000-0000-0000-000000000001','Broker','IDR',
  'd1000000-0000-0000-0000-000000000001','test'),
 ('d2000000-0000-0000-0000-000000000002','Other Broker','IDR',
  'd1000000-0000-0000-0000-000000000002','test');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('d2000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000001','owner','active'),
 ('d2000000-0000-0000-0000-000000000002',
  'd1000000-0000-0000-0000-000000000002','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('d2000000-0000-0000-0000-000000000001','complete',now()),
 ('d2000000-0000-0000-0000-000000000002','complete',now());
insert into public.accounts(id,book_id,name,account_type,currency_code,
 opening_balance,created_at,updated_at,version,device_id) values
 ('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001',
  'Brokerage','brokerage','IDR',0,now(),now(),1,'test'),
 ('d3000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000001',
  'Bank','bank','IDR',0,now(),now(),1,'test'),
 ('d3000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000002',
  'Foreign Brokerage','brokerage','IDR',0,now(),now(),1,'test');
insert into public.asset_definitions(id,book_id,display_name,asset_kind,
 currency_code,unit,created_at,updated_at,version,device_id) values
 ('d4000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001',
  'Fund','stock','IDR','share',now(),now(),1,'test');

insert into public.transactions(id,book_id,title,category,account,
 transaction_date,amount,transaction_type,quantity,unit,unit_price,
 asset_definition_id,asset_name,asset_action,fee_amount,fee_treatment,
 relation_type,brokerage_account_id,brokerage_activity_type,
 created_at,updated_at,version,device_id) values
 ('d5000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001',
  'Buy Fund','Investment','Brokerage -> Fund',now(),1000,'assetConversion',1,
  'share',1000,'d4000000-0000-0000-0000-000000000001','Fund','buy',0,
  'none','none','d3000000-0000-0000-0000-000000000001','buy',now(),now(),1,'test');
select ok(exists(select 1 from public.transactions
  where id='d5000000-0000-0000-0000-000000000001'
    and brokerage_activity_type='buy'),'valid brokerage trade persists');

select throws_ok($$update public.transactions
 set brokerage_account_id='d3000000-0000-0000-0000-000000000003'
 where id='d5000000-0000-0000-0000-000000000001'$$,
 'P0001','Brokerage account must belong to the transaction household',
 'cross-household brokerage attribution is rejected');
select throws_ok($$update public.transactions
 set brokerage_account_id='d3000000-0000-0000-0000-000000000002'
 where id='d5000000-0000-0000-0000-000000000001'$$,
 'P0001','Brokerage account must belong to the transaction household',
 'non-brokerage attribution is rejected');
select throws_ok($$update public.transactions
 set brokerage_activity_type='split',asset_action='split',amount=0
 where id='d5000000-0000-0000-0000-000000000001'$$,
 '23514',null,'split requires a positive paired ratio');

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.push_book_changes(
 'd2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','d6000000-0000-0000-0000-000000000001',
 'entityType','transactions','entityId','d5000000-0000-0000-0000-000000000002',
 'operationType','upsert','baseVersion',0,'deviceId','broker-client','payload',
 jsonb_build_object('id','d5000000-0000-0000-0000-000000000002',
 'book_id','d2000000-0000-0000-0000-000000000001','title','Dividend',
 'category','Investment','account','Brokerage','transaction_date',now(),
 'amount',500,'transaction_type','investment','fee_amount',0,
 'fee_treatment','none','relation_type','none','brokerage_account_id',
 'd3000000-0000-0000-0000-000000000001','brokerage_activity_type','dividend',
 'created_at',now(),'updated_at',now(),'version',1,
 'device_id','broker-client')))))->0->>'status','applied',
 'sync accepts valid brokerage metadata');
select ok((select brokerage_account_id=
  'd3000000-0000-0000-0000-000000000001'::uuid
  and brokerage_activity_type='dividend' from public.transactions
  where id='d5000000-0000-0000-0000-000000000002'),
  'sync metadata round trips');
select is((public.push_book_changes(
 'd2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','d6000000-0000-0000-0000-000000000002',
 'entityType','transactions','entityId','d5000000-0000-0000-0000-000000000002',
 'operationType','upsert','baseVersion',1,'deviceId','old-client','payload',
 (select to_jsonb(t)-'brokerage_account_id'-'brokerage_activity_type'
   -'split_numerator'-'split_denominator' from public.transactions t
  where id='d5000000-0000-0000-0000-000000000002')))))->0->>'status','applied',
 'old-client update succeeds');
select is((select brokerage_activity_type from public.transactions
 where id='d5000000-0000-0000-0000-000000000002'),'dividend',
 'omitted brokerage fields preserve current attribution');
select throws_ok($$select public.push_book_changes(
 'd2000000-0000-0000-0000-000000000002','[]'::jsonb)$$,
 'P0001','Active book membership required','cross-household sync remains rejected');

set local role postgres;
select ok(exists(select 1 from jsonb_array_elements(public.pull_book_changes(
 'd2000000-0000-0000-0000-000000000001',0,200)->'changes') c
 where c->>'entity_type'='transactions'
   and c->'snapshot' ? 'brokerage_account_id'
   and c->'snapshot' ? 'brokerage_activity_type'),
 'change feed includes brokerage metadata');
select is((select count(*) from public.transactions),2::bigint,
 'brokerage sync creates no duplicate financial rows');
select function_privs_are('public','apply_transaction_brokerage_sync_context',
 array[]::text[],'authenticated',array[]::text[],
 'sync context trigger helper is not client callable');
select function_privs_are('public','validate_transaction_brokerage_reference',
 array[]::text[],'authenticated',array[]::text[],
 'validation trigger helper is not client callable');
select function_privs_are('public','push_book_changes',array['uuid','jsonb'],
 'authenticated',array['EXECUTE'],'only authenticated clients can push changes');

select * from finish();
rollback;
