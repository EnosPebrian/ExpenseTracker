begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path', format('public,%I', namespace.nspname), true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(20);

select has_table('public','import_review_sessions','session table exists');
select has_table('public','import_review_drafts','draft table exists');
select is((select relrowsecurity from pg_class where oid='public.import_review_sessions'::regclass),true,'session RLS enabled');
select is((select relrowsecurity from pg_class where oid='public.import_review_drafts'::regclass),true,'draft RLS enabled');

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('a8100000-0000-0000-0000-000000000001','authenticated','authenticated','owner08g@example.test',now(),now(),now()),
 ('a8100000-0000-0000-0000-000000000002','authenticated','authenticated','member08g@example.test',now(),now(),now()),
 ('a8100000-0000-0000-0000-000000000003','authenticated','authenticated','other08g@example.test',now(),now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('a8200000-0000-0000-0000-000000000001','Inbox Household','IDR','a8100000-0000-0000-0000-000000000001','server'),
 ('a8200000-0000-0000-0000-000000000002','Other Household','IDR','a8100000-0000-0000-0000-000000000003','server');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('a8200000-0000-0000-0000-000000000001','a8100000-0000-0000-0000-000000000001','owner','active'),
 ('a8200000-0000-0000-0000-000000000001','a8100000-0000-0000-0000-000000000002','member','active'),
 ('a8200000-0000-0000-0000-000000000002','a8100000-0000-0000-0000-000000000003','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('a8200000-0000-0000-0000-000000000001','complete',now()),
 ('a8200000-0000-0000-0000-000000000002','complete',now());
select set_config('app.initial_sync_mode','on',true);
insert into public.accounts(id,book_id,name,account_type,currency_code,created_at,updated_at,version,device_id) values
 ('a8300000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-000000000001','Bank','bank','IDR',now(),now(),1,'server'),
 ('a8300000-0000-0000-0000-000000000002','a8200000-0000-0000-0000-000000000002','Other','bank','IDR',now(),now(),1,'server');
insert into public.categories(id,book_id,name,category_type,created_at,updated_at,version,device_id) values
 ('a8400000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-000000000001','Travel','expense',now(),now(),1,'server'),
 ('a8400000-0000-0000-0000-000000000002','a8200000-0000-0000-0000-000000000002','Other','expense',now(),now(),1,'server');
select set_config('app.initial_sync_mode','off',true);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8100000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select lives_ok($$insert into public.import_review_sessions(
 id,book_id,source_type,title,source_fingerprint,destination_account_id,state,
 summary_json,created_at,updated_at,version,device_id
) values ('a8500000-0000-0000-0000-000000000001','a8200000-0000-0000-0000-000000000001',
 'csv','August CSV','fingerprint','a8300000-0000-0000-0000-000000000001','pendingReview',
 '{"row_count":1}',now(),now(),1,'device-a')$$,'member creates own-household session');
select lives_ok($$insert into public.import_review_drafts(
 id,session_id,book_id,source_row_identity,deterministic_transaction_id,
 deterministic_transaction_account_id,source_index,
 transaction_date,description,amount_minor,currency_code,transaction_type,category_name,
 category_id,category_provenance,included,created_at,updated_at,version,device_id
) values ('a8600000-0000-0000-0000-000000000001','a8500000-0000-0000-0000-000000000001',
 'a8200000-0000-0000-0000-000000000001','row-1','a8700000-0000-0000-0000-000000000001',
 'a8300000-0000-0000-0000-000000000001',1,
 now(),'Taxi',50000,'IDR','expense','Travel','a8400000-0000-0000-0000-000000000001','manual',true,
 now(),now(),1,'device-a')$$,'member creates same-household draft');
select is((select count(*) from public.import_review_sessions),1::bigint,'member reads own session');
select is((select count(*) from public.import_review_drafts),1::bigint,'member reads own draft');
select throws_ok($$update public.import_review_sessions set destination_account_id='a8300000-0000-0000-0000-000000000002' where id='a8500000-0000-0000-0000-000000000001'$$,null,null,'foreign account rejected');
select throws_ok($$update public.import_review_drafts set category_id='a8400000-0000-0000-0000-000000000002' where id='a8600000-0000-0000-0000-000000000001'$$,null,null,'foreign category rejected');
select throws_ok($$update public.import_review_drafts set book_id='a8200000-0000-0000-0000-000000000002' where id='a8600000-0000-0000-0000-000000000001'$$,null,null,'draft cannot move household');
select throws_ok($$update public.import_review_sessions set state='completed',completed_at=now(),updated_at=now(),version=2 where id='a8500000-0000-0000-0000-000000000001'$$,null,null,'pending session cannot skip ready state');
update public.import_review_sessions set state='readyToCommit',updated_at=now(),version=2 where id='a8500000-0000-0000-0000-000000000001';
update public.import_review_sessions set state='completed',completed_at=now(),updated_at=now(),version=3 where id='a8500000-0000-0000-0000-000000000001';
select throws_ok($$update public.import_review_sessions set state='pendingReview',updated_at=now(),version=4 where id='a8500000-0000-0000-0000-000000000001'$$,null,null,'terminal session cannot reopen');
select ok(exists(select 1 from public.app_changes where entity_table='import_review_sessions'),'session appears in change feed');
select ok(exists(select 1 from public.app_changes where entity_table='import_review_drafts'),'draft appears in change feed');

set local role postgres;
select is((public.initial_sync_manifest('a8200000-0000-0000-0000-000000000001',0,'download',null)->'counts'->>'import_review_sessions')::integer,1,'manifest counts sessions');
select is((public.initial_sync_manifest('a8200000-0000-0000-0000-000000000001',0,'download',null)->'counts'->>'import_review_drafts')::integer,1,'manifest counts drafts');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8100000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select is((select count(*) from public.import_review_sessions),0::bigint,'unrelated household cannot read sessions');
select throws_ok($$insert into public.import_review_sessions(id,book_id,source_type,title,source_fingerprint,state,created_at,updated_at,version,device_id)
 values ('a8500000-0000-0000-0000-000000000099','a8200000-0000-0000-0000-000000000001','csv','Denied','denied','pendingReview',now(),now(),1,'other')$$,'42501',null,'unrelated household cannot write sessions');

set local role anon;
select throws_ok($$select * from public.import_review_sessions$$,'42501',null,'unauthenticated denied');

select * from finish();
rollback;
