begin;
create extension if not exists pgtap;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true) from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgtap';
select plan(12);
select has_table('public','brokerage_settlements','separate nonfinancial evidence table');
select ok((select relrowsecurity from pg_class where oid='public.brokerage_settlements'::regclass),'RLS enabled');
select ok(not has_table_privilege('anon','public.brokerage_settlements','SELECT'),'anonymous denied');
select ok('brokerage_account_id'=any(public.initial_sync_allowed_fields('brokerage_settlements')),'bootstrap permits evidence account');
insert into auth.users(id,aud,role,email,created_at,updated_at) values ('a1000000-0000-0000-0000-000000000001','authenticated','authenticated','settlement@example.test',now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values ('a2000000-0000-0000-0000-000000000001','Settlement','IDR','a1000000-0000-0000-0000-000000000001','test');
insert into public.book_memberships(book_id,user_id,role,status) values ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values ('a2000000-0000-0000-0000-000000000001','complete',now());
insert into public.accounts(id,book_id,name,account_type,currency_code,opening_balance,created_at,updated_at,version,device_id) values ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Broker','brokerage','IDR',0,now(),now(),1,'test');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.push_book_changes('a2000000-0000-0000-0000-000000000001', jsonb_build_array(jsonb_build_object(
  'operationId','a6000000-0000-0000-0000-000000000001','entityType','brokerage_settlements','entityId','a5000000-0000-0000-0000-000000000001','operationType','upsert','baseVersion',0,'deviceId','test',
  'payload',jsonb_build_object('id','a5000000-0000-0000-0000-000000000001','book_id','a2000000-0000-0000-0000-000000000001','brokerage_account_id','a3000000-0000-0000-0000-000000000001','statement_date',now(),'settlement_type','BUY_SETTLEMENT','amount',100,'currency_code','IDR','source_fingerprint','source','source_row_identity','row','source_row_fingerprint','fingerprint','reference','RDN','note','original','trade_ids_json','[]','created_at',now(),'updated_at',now(),'version',1,'device_id','test')
)))->0->>'status'),'applied','ordinary sync persists unmatched evidence');
select is((select count(*) from public.brokerage_settlements),1::bigint,'one evidence record');
select is((select count(*) from public.transactions),0::bigint,'no financial transactions created');
select is((select opening_balance from public.accounts where id='a3000000-0000-0000-0000-000000000001'),0::bigint,'account values unchanged');
select throws_ok($$update public.brokerage_settlements set amount=200$$,'P0001','Settlement source identity and evidence are immutable','source amount immutable');
select throws_ok($$update public.brokerage_settlements set trade_ids_json='["a9000000-0000-0000-0000-000000000001"]'$$,'P0001','Incompatible settlement trade reference','unknown trade rejected');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000099","role":"authenticated"}',true);
select is((select count(*) from public.brokerage_settlements),0::bigint,'nonmember cannot read evidence');
set local role postgres;
select ok(exists(select 1 from public.app_changes where entity_table='brokerage_settlements'),'change feed captures evidence');
select * from finish();
rollback;
