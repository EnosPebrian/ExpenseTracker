begin;
create extension if not exists pgtap;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true) from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgtap';
select plan(25);
select has_table('public','brokerage_settlements','separate nonfinancial evidence table');
select ok((select relrowsecurity from pg_class where oid='public.brokerage_settlements'::regclass),'RLS enabled');
select ok(has_table_privilege('authenticated','public.brokerage_settlements','SELECT'),'authenticated can read settlement evidence');
select ok(has_table_privilege('authenticated','public.brokerage_settlements','INSERT'),'authenticated can create settlement evidence');
select ok(has_table_privilege('authenticated','public.brokerage_settlements','UPDATE'),'authenticated can reconcile and tombstone settlement evidence');
select ok(not has_table_privilege('authenticated','public.brokerage_settlements','DELETE'),'authenticated cannot physically delete settlement evidence');
select ok(not has_table_privilege('anon','public.brokerage_settlements','SELECT')
  and not has_table_privilege('anon','public.brokerage_settlements','INSERT')
  and not has_table_privilege('anon','public.brokerage_settlements','UPDATE')
  and not has_table_privilege('anon','public.brokerage_settlements','DELETE'),'anonymous has no settlement access');
select ok('brokerage_account_id'=any(public.initial_sync_allowed_fields('brokerage_settlements')),'bootstrap permits evidence account');
insert into auth.users(id,aud,role,email,created_at,updated_at) values
 ('a1000000-0000-0000-0000-000000000001','authenticated','authenticated','settlement@example.test',now(),now()),
 ('a1000000-0000-0000-0000-000000000002','authenticated','authenticated','foreign-settlement@example.test',now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('a2000000-0000-0000-0000-000000000001','Settlement','IDR','a1000000-0000-0000-0000-000000000001','test'),
 ('a2000000-0000-0000-0000-000000000002','Foreign Settlement','IDR','a1000000-0000-0000-0000-000000000002','test');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','owner','active'),
 ('a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('a2000000-0000-0000-0000-000000000001','complete',now()),
 ('a2000000-0000-0000-0000-000000000002','complete',now());
insert into public.accounts(id,book_id,name,account_type,currency_code,opening_balance,created_at,updated_at,version,device_id) values
 ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Broker','brokerage','IDR',0,now(),now(),1,'test'),
 ('a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','Foreign Broker','brokerage','IDR',0,now(),now(),1,'test');
insert into public.asset_definitions(id,book_id,display_name,asset_kind,currency_code,unit,created_at,updated_at,version,device_id) values
 ('a4000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Fund','stock','IDR','share',now(),now(),1,'test');
insert into public.transactions(id,book_id,title,category,account,transaction_date,amount,transaction_type,quantity,unit,unit_price,asset_definition_id,asset_name,asset_action,fee_amount,fee_treatment,relation_type,brokerage_account_id,brokerage_activity_type,created_at,updated_at,version,device_id) values
 ('a4000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001','Buy Fund','Investment','Broker -> Fund',now(),100,'assetConversion',1,'share',100,'a4000000-0000-0000-0000-000000000001','Fund','buy',0,'none','none','a3000000-0000-0000-0000-000000000001','buy',now(),now(),1,'test');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.push_book_changes('a2000000-0000-0000-0000-000000000001', jsonb_build_array(jsonb_build_object(
  'operationId','a6000000-0000-0000-0000-000000000001','entityType','brokerage_settlements','entityId','a5000000-0000-0000-0000-000000000001','operationType','upsert','baseVersion',0,'deviceId','test',
  'payload',jsonb_build_object('id','a5000000-0000-0000-0000-000000000001','book_id','a2000000-0000-0000-0000-000000000001','brokerage_account_id','a3000000-0000-0000-0000-000000000001','statement_date',now(),'settlement_type','BUY_SETTLEMENT','amount',100,'currency_code','IDR','source_fingerprint','source','source_row_identity','row','source_row_fingerprint','fingerprint','reference','RDN','note','original','trade_ids_json','[]','created_at',now(),'updated_at',now(),'version',1,'device_id','test')
)))->0->>'status'),'applied','ordinary sync persists unmatched evidence');
select is((select count(*) from public.brokerage_settlements),1::bigint,'one evidence record');
select is((select count(*) from public.transactions),1::bigint,'settlement creates no financial transaction');
select is((select opening_balance from public.accounts where id='a3000000-0000-0000-0000-000000000001'),0::bigint,'account values unchanged');
select is((select count(*) from public.brokerage_settlements where id='a5000000-0000-0000-0000-000000000001'),1::bigint,'member can read settlement evidence');
select throws_ok($$update public.brokerage_settlements set amount=200$$,'P0001','Settlement source identity and evidence are immutable','source amount immutable');
select throws_ok($$update public.brokerage_settlements set trade_ids_json='["a9000000-0000-0000-0000-000000000001"]'$$,'P0001','Incompatible settlement trade reference','unknown trade rejected');
select lives_ok($$update public.brokerage_settlements
 set trade_ids_json='["a4000000-0000-0000-0000-000000000002"]',updated_at=now(),version=2
 where id='a5000000-0000-0000-0000-000000000001'$$,'member can reconcile settlement evidence by update');
select is((select trade_ids_json from public.brokerage_settlements where id='a5000000-0000-0000-0000-000000000001'),'["a4000000-0000-0000-0000-000000000002"]','reconciliation relationship persists');
select throws_ok($$insert into public.brokerage_settlements(id,book_id,brokerage_account_id,statement_date,settlement_type,amount,currency_code,source_fingerprint,source_row_identity,source_row_fingerprint,reference,note,trade_ids_json,created_at,updated_at,version,device_id) values
 ('a5000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','a3000000-0000-0000-0000-000000000002',now(),'BUY_SETTLEMENT',100,'IDR','foreign','row','fingerprint','','','[]',now(),now(),1,'test')$$,'P0001','Incompatible settlement account','cross-household settlement insert is denied');
select is((public.push_book_changes('a2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
  'operationId','a6000000-0000-0000-0000-000000000002','entityType','brokerage_settlements','entityId','a5000000-0000-0000-0000-000000000001','operationType','delete','baseVersion',2,'deviceId','test',
  'payload',(select to_jsonb(s)||jsonb_build_object('deleted_at',now(),'version',3,'updated_at',now()) from public.brokerage_settlements s where id='a5000000-0000-0000-0000-000000000001')
)))->0->>'status'),'applied','ordinary sync tombstones settlement evidence');
select ok((select deleted_at is not null and version=3 from public.brokerage_settlements where id='a5000000-0000-0000-0000-000000000001'),'versioned settlement tombstone persists');
select throws_ok($$delete from public.brokerage_settlements where id='a5000000-0000-0000-0000-000000000001'$$,'42501',null,'authenticated direct delete is denied');
select is((select count(*) from public.transactions),1::bigint,'reconciliation and tombstone have zero financial effect');
select is((select opening_balance from public.accounts where id='a3000000-0000-0000-0000-000000000001'),0::bigint,'reconciliation and tombstone leave account values unchanged');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000099","role":"authenticated"}',true);
select is((select count(*) from public.brokerage_settlements),0::bigint,'nonmember cannot read evidence');
set local role postgres;
select ok(exists(select 1 from public.app_changes where entity_table='brokerage_settlements'),'change feed captures evidence');
select * from finish();
rollback;
