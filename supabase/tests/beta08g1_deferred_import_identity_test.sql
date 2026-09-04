begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path', format('public,%I', namespace.nspname), true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(12);

select is((select is_nullable from information_schema.columns
  where table_schema='public' and table_name='import_review_drafts'
    and column_name='deterministic_transaction_id'),'YES','final transaction ID is nullable');
select has_column('public','import_review_drafts','source_row_key','source row key persisted');
select has_column('public','import_review_drafts','deterministic_transaction_account_id','identity account binding exists');
select is((select relrowsecurity from pg_class
  where oid='public.import_review_drafts'::regclass),true,'draft RLS remains enabled');

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('b8100000-0000-0000-0000-000000000001','authenticated','authenticated','owner08g1@example.test',now(),now(),now()),
 ('b8100000-0000-0000-0000-000000000002','authenticated','authenticated','other08g1@example.test',now(),now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('b8200000-0000-0000-0000-000000000001','Deferred Household','IDR','b8100000-0000-0000-0000-000000000001','server'),
 ('b8200000-0000-0000-0000-000000000002','Other Household','IDR','b8100000-0000-0000-0000-000000000002','server');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('b8200000-0000-0000-0000-000000000001','b8100000-0000-0000-0000-000000000001','owner','active'),
 ('b8200000-0000-0000-0000-000000000002','b8100000-0000-0000-0000-000000000002','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('b8200000-0000-0000-0000-000000000001','complete',now()),
 ('b8200000-0000-0000-0000-000000000002','complete',now());
select set_config('app.initial_sync_mode','on',true);
insert into public.accounts(id,book_id,name,account_type,currency_code,created_at,updated_at,version,device_id) values
 ('b8300000-0000-0000-0000-000000000001','b8200000-0000-0000-0000-000000000001','Bank','bank','IDR',now(),now(),1,'server'),
 ('b8300000-0000-0000-0000-000000000002','b8200000-0000-0000-0000-000000000002','Other','bank','IDR',now(),now(),1,'server');
select set_config('app.initial_sync_mode','off',true);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b8100000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$insert into public.import_review_sessions(
 id,book_id,source_type,title,source_fingerprint,state,summary_json,
 created_at,updated_at,version,device_id
) values ('b8500000-0000-0000-0000-000000000001','b8200000-0000-0000-0000-000000000001',
 'csv','Unresolved','fingerprint','pendingReview','{}',now(),now(),1,'device-a')$$,
 'unresolved session inserts without destination account');
select lives_ok($$insert into public.import_review_drafts(
 id,session_id,book_id,source_row_identity,source_row_key,
 deterministic_transaction_id,deterministic_transaction_account_id,source_index,
 transaction_date,description,amount_minor,currency_code,transaction_type,
 category_provenance,created_at,updated_at,version,device_id
) values ('b8600000-0000-0000-0000-000000000001','b8500000-0000-0000-0000-000000000001',
 'b8200000-0000-0000-0000-000000000001','row-hash','row-key',null,null,1,
 now(),'Taxi',50000,'IDR','expense','unresolved',now(),now(),1,'device-a')$$,
 'unresolved draft inserts with paired null identity');
select throws_ok($$update public.import_review_drafts
 set deterministic_transaction_account_id='b8300000-0000-0000-0000-000000000001'
 where id='b8600000-0000-0000-0000-000000000001'$$,null,null,
 'account binding without final ID is rejected');

update public.import_review_sessions
set destination_account_id='b8300000-0000-0000-0000-000000000001',updated_at=now(),version=2
where id='b8500000-0000-0000-0000-000000000001';
select lives_ok($$update public.import_review_drafts set
 deterministic_transaction_id='b8700000-0000-0000-0000-000000000001',
 deterministic_transaction_account_id='b8300000-0000-0000-0000-000000000001',
 updated_at=now(),version=2
 where id='b8600000-0000-0000-0000-000000000001'$$,
 'resolved identity and matching account insert together');
select throws_ok($$update public.import_review_drafts set
 deterministic_transaction_id='b8700000-0000-0000-0000-000000000002',
 deterministic_transaction_account_id='b8300000-0000-0000-0000-000000000002',
 updated_at=now(),version=3
 where id='b8600000-0000-0000-0000-000000000001'$$,null,null,
 'cross-household identity account is rejected');
select ok(exists(select 1 from public.app_changes
  where entity_table='import_review_drafts'),
  'deferred identity changes remain in the change feed');

set local role postgres;
select ok('source_row_key'=any(public.initial_sync_allowed_fields('import_review_drafts')),
  'initial sync accepts source row key');
select ok('deterministic_transaction_account_id'=any(public.initial_sync_allowed_fields('import_review_drafts')),
  'initial sync accepts identity account binding');

select * from finish();
rollback;
