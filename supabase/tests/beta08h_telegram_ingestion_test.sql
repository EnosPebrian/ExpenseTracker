begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path', format('public,%I', namespace.nspname), true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(29);

select has_table('public','telegram_connections','Telegram connections table exists');
select has_table('public','telegram_pairing_tokens','pairing token table exists');
select has_table('public','telegram_ingestion_events','ingestion event table exists');
select is((select relrowsecurity from pg_class where oid='public.telegram_connections'::regclass),true,'connection RLS enabled');
select is((select relrowsecurity from pg_class where oid='public.telegram_pairing_tokens'::regclass),true,'token RLS enabled');
select is((select relrowsecurity from pg_class where oid='public.telegram_ingestion_events'::regclass),true,'event RLS enabled');
select has_column('public','telegram_pairing_tokens','token_hash','hashed token field exists');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='telegram_pairing_tokens' and column_name='token_hash'),'bytea','token hash is binary');
select ok(not has_table_privilege('authenticated','public.telegram_pairing_tokens','SELECT'),'authenticated cannot read token hashes');
select ok(not has_table_privilege('authenticated','public.telegram_ingestion_events','SELECT'),'authenticated cannot read event operations');

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('c8100000-0000-0000-0000-000000000001','authenticated','authenticated','telegram@example.test',now(),now(),now()),
 ('c8100000-0000-0000-0000-000000000002','authenticated','authenticated','othertelegram@example.test',now(),now(),now());
insert into public.books(id,name,base_currency_code,created_by_user_id,device_id) values
 ('c8200000-0000-0000-0000-000000000001','Telegram Household','IDR','c8100000-0000-0000-0000-000000000001','server'),
 ('c8200000-0000-0000-0000-000000000002','Other Household','IDR','c8100000-0000-0000-0000-000000000002','server');
select set_config('app.initial_sync_mode','on',true);
insert into public.household_members(id,book_id,display_name,role,created_at,updated_at,version,device_id) values
 ('c8300000-0000-0000-0000-000000000001','c8200000-0000-0000-0000-000000000001','Owner','owner',now(),now(),1,'server'),
 ('c8300000-0000-0000-0000-000000000002','c8200000-0000-0000-0000-000000000002','Other','owner',now(),now(),1,'server');
select set_config('app.initial_sync_mode','off',true);
insert into public.book_memberships(book_id,user_id,household_member_id,role,status) values
 ('c8200000-0000-0000-0000-000000000001','c8100000-0000-0000-0000-000000000001','c8300000-0000-0000-0000-000000000001','owner','active'),
 ('c8200000-0000-0000-0000-000000000002','c8100000-0000-0000-0000-000000000002','c8300000-0000-0000-0000-000000000002','owner','active');
insert into public.book_sync_initializations(book_id,status,completed_at) values
 ('c8200000-0000-0000-0000-000000000001','complete',now()),
 ('c8200000-0000-0000-0000-000000000002','complete',now());

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"c8100000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select connected from public.telegram_connection_status('c8200000-0000-0000-0000-000000000001')),false,'status starts disconnected');
select lives_ok($$select public.issue_telegram_pairing_token(
 'c8200000-0000-0000-0000-000000000001','c8300000-0000-0000-0000-000000000001',
 encode(digest('first-high-entropy-token','sha256'),'hex'),now()+interval '10 minutes')$$,'active member can issue pairing token');
set local role postgres;
select is((select octet_length(token_hash) from public.telegram_pairing_tokens order by created_at desc limit 1),32,'only SHA-256 digest is stored');
set local role authenticated;
select lives_ok($$select public.issue_telegram_pairing_token(
 'c8200000-0000-0000-0000-000000000001','c8300000-0000-0000-0000-000000000001',
 encode(digest('second-high-entropy-token','sha256'),'hex'),now()+interval '10 minutes')$$,'new token revokes outstanding token');
set local role postgres;
select is((select count(*) from public.telegram_pairing_tokens where consumed_at is null and revoked_at is null),1::bigint,'only one outstanding token remains');

set local role service_role;
select is(public.telegram_consume_pairing_token(1,encode(digest('wrong-token','sha256'),'hex'),987654321,987654321),false,'wrong token rejected');
select is(public.telegram_consume_pairing_token(1,encode(digest('second-high-entropy-token','sha256'),'hex'),987654321,987654321),true,'valid token atomically links private identity');
select is(public.telegram_consume_pairing_token(2,encode(digest('second-high-entropy-token','sha256'),'hex'),987654321,987654321),false,'consumed token cannot be reused');
set local role postgres;
select set_config('test.telegram_connection_id',(select id::text from public.telegram_connections where revoked_at is null),true);
set local role authenticated;
select is((select connected from public.telegram_connection_status('c8200000-0000-0000-0000-000000000001')),true,'owner sees connected state');

set local role service_role;
select is((public.telegram_claim_ingestion_event(10,987654321,987654321,5,'attachment')->>'claimed')::boolean,true,'linked attachment event is claimed');
select is((public.telegram_claim_ingestion_event(10,987654321,987654321,5,'attachment')->>'claimed')::boolean,false,'duplicate update id is not reclaimed');
select lives_ok($$select public.create_telegram_import_review(
 10,current_setting('test.telegram_connection_id')::uuid,
 '{"id":"c8500000-0000-0000-0000-000000000001","source_type":"csv","title":"CSV — telegram.csv","source_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","summary":{"origin":"telegram"}}'::jsonb,
 '[{"id":"c8600000-0000-0000-0000-000000000001","source_row_identity":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","source_row_key":"2","source_index":2,"transaction_date":"2026-08-31T00:00:00Z","description":"Safe row","amount_minor":12000,"currency_code":"IDR","transaction_type":"expense","category_name":"","category_provenance":"unresolved","reference_text":"","note_text":"","merchant_hint":"","warnings":[]}]'::jsonb
)$$,'service gateway creates existing Inbox entities');
set local role postgres;
select is((select count(*) from public.import_review_sessions where id='c8500000-0000-0000-0000-000000000001'),1::bigint,'one Inbox session created');
select ok((select deterministic_transaction_id is null and deterministic_transaction_account_id is null from public.import_review_drafts where id='c8600000-0000-0000-0000-000000000001'),'Telegram draft leaves final identity unresolved');
select is((select count(*) from public.transactions where book_id='c8200000-0000-0000-0000-000000000001'),0::bigint,'Telegram ingestion performs zero financial transaction writes');
set local role authenticated;
select throws_ok($$select count(*) from public.telegram_ingestion_events$$,'42501',null,'authenticated client cannot inspect ingestion events');
select set_config('request.jwt.claims','{"sub":"c8100000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select * from public.telegram_connection_status('c8200000-0000-0000-0000-000000000001')$$,null,null,'unrelated household cannot inspect connection status');

set local role postgres;
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('c8100000-0000-0000-0000-000000000003','authenticated','authenticated','backupowner@example.test',now(),now(),now());
select set_config('app.initial_sync_mode','on',true);
insert into public.household_members(id,book_id,display_name,role,created_at,updated_at,version,device_id) values
 ('c8300000-0000-0000-0000-000000000003','c8200000-0000-0000-0000-000000000001','Backup Owner','owner',now(),now(),1,'server');
select set_config('app.initial_sync_mode','off',true);
insert into public.book_memberships(book_id,user_id,household_member_id,role,status) values
 ('c8200000-0000-0000-0000-000000000001','c8100000-0000-0000-0000-000000000003','c8300000-0000-0000-0000-000000000003','owner','active');
update public.book_memberships set status='revoked'
where book_id='c8200000-0000-0000-0000-000000000001' and user_id='c8100000-0000-0000-0000-000000000001';
set local role service_role;
select is(public.telegram_claim_ingestion_event(11,987654321,987654321,6,'attachment')->>'reason','membership_revoked','membership is revalidated for every attachment');
set local role postgres;
select ok((select revoked_at is not null from public.telegram_connections where telegram_user_id=987654321),'revoked membership makes connection unusable');

select * from finish();
rollback;
