begin;
create extension if not exists pgtap;
set local role postgres;
select set_config('search_path',format('public,%I',n.nspname),true)
from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgtap';
select plan(17);
select has_column('public','transactions','category_id','nullable identity column');
select is((select is_nullable from information_schema.columns where table_schema='public'
 and table_name='transactions' and column_name='category_id'),'YES','legacy null permitted');
select ok(not has_function_privilege('anon','public.validate_transaction_category_identity()','EXECUTE'),'anon cannot execute helper');
select ok((select relrowsecurity from pg_class where oid='public.transactions'::regclass),'RLS remains enabled');
insert into auth.users(id,aud,role,email,created_at,updated_at) values
 ('a1000000-0000-0000-0000-000000000001','authenticated','authenticated','l0@example.test',now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('a2000000-0000-0000-0000-000000000001','L0','IDR','a1000000-0000-0000-0000-000000000001','test'),
 ('a2000000-0000-0000-0000-000000000002','Other','IDR','a1000000-0000-0000-0000-000000000001','test');
insert into public.book_memberships(book_id,user_id,role,status) values
 ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('a2000000-0000-0000-0000-000000000001','complete',now());
select set_config('app.initial_sync_mode','on',true);
insert into public.categories(id,book_id,name,category_type,created_at,updated_at,version,device_id) values
 ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','Food','expense',now(),now(),1,'test'),
 ('a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','Food','expense',now(),now(),1,'test');
select is(public.legacy_transaction_category_id('a2000000-0000-0000-0000-000000000001','expense',' FOOD '),
 'a3000000-0000-0000-0000-000000000001'::uuid,'unique normalized same-household match');
update public.categories set deleted_at=now() where id='a3000000-0000-0000-0000-000000000001';
select is(public.legacy_transaction_category_id('a2000000-0000-0000-0000-000000000001','expense','Food'),
 'a3000000-0000-0000-0000-000000000001'::uuid,'archived identity remains valid');
insert into public.categories(id,book_id,name,category_type,created_at,updated_at,version,device_id) values
 ('a3000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001','food','expense',now(),now(),1,'test');
select is(public.legacy_transaction_category_id('a2000000-0000-0000-0000-000000000001','expense','Food'),null::uuid,'collision never guessed');
select is(public.legacy_transaction_category_id('a2000000-0000-0000-0000-000000000001','expense','Unknown'),null::uuid,'unmatched remains null');
select ok('category_id'=any(public.initial_sync_allowed_fields('transactions')),'initial sync includes category identity');
select set_config('app.initial_sync_mode','off',true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((public.push_book_changes('a2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','a5000000-0000-0000-0000-000000000001','entityType','transactions',
 'entityId','a4000000-0000-0000-0000-000000000001','operationType','upsert','baseVersion',0,'deviceId','test',
 'payload',jsonb_build_object('id','a4000000-0000-0000-0000-000000000001','book_id','a2000000-0000-0000-0000-000000000001',
 'title','Lunch','category','Food','category_id','a3000000-0000-0000-0000-000000000001','account','Cash',
 'transaction_date',now(),'amount',100,'transaction_type','expense','fee_amount',0,'fee_treatment','none','relation_type','none',
 'created_at',now(),'updated_at',now(),'version',1,'device_id','test')))))->0->>'status','applied','push accepts authoritative ID');
select is((select category_id from public.transactions where id='a4000000-0000-0000-0000-000000000001'),
 'a3000000-0000-0000-0000-000000000001'::uuid,'RPC persists identity');
select ok(exists(select 1 from jsonb_array_elements(public.pull_book_changes('a2000000-0000-0000-0000-000000000001',0,200)->'changes') c
 where c->'snapshot'->>'category_id'='a3000000-0000-0000-0000-000000000001'),'change feed pull carries identity');
select is((public.push_book_changes('a2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','a5000000-0000-0000-0000-000000000002','entityType','transactions','entityId','a4000000-0000-0000-0000-000000000001',
 'operationType','upsert','baseVersion',1,'deviceId','old','payload',(select to_jsonb(t)-'category_id' from public.transactions t where id='a4000000-0000-0000-0000-000000000001')))))->0->>'status','applied','old unchanged update accepted');
select is((select category_id from public.transactions where id='a4000000-0000-0000-0000-000000000001'),
 'a3000000-0000-0000-0000-000000000001'::uuid,'old unchanged snapshot preserves ID');
select is((public.push_book_changes('a2000000-0000-0000-0000-000000000001',jsonb_build_array(jsonb_build_object(
 'operationId','a5000000-0000-0000-0000-000000000003','entityType','transactions','entityId','a4000000-0000-0000-0000-000000000001',
 'operationType','upsert','baseVersion',2,'deviceId','old','payload',(select (to_jsonb(t)-'category_id')||'{"category":"Dining"}'::jsonb from public.transactions t where id='a4000000-0000-0000-0000-000000000001')))))->0->>'status','applied','old changed category accepted');
select is((select category_id from public.transactions where id='a4000000-0000-0000-0000-000000000001'),null::uuid,'old changed snapshot clears stale ID');
select throws_ok($$update public.transactions set category_id='a3000000-0000-0000-0000-000000000002'
 where id='a4000000-0000-0000-0000-000000000001'$$,null,null,'cross-household binding denied');
select * from finish();
rollback;
