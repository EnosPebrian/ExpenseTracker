begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path',
  format('public,%I', namespace.nspname),
  true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(17);

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('91000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner04b@example.test', now(), now(), now()),
  ('91000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'member04b@example.test', now(), now(), now()),
  ('91000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other04b@example.test', now(), now(), now());

insert into public.books(id, name, base_currency_code, created_by_user_id, device_id)
values
  ('92000000-0000-0000-0000-000000000001', 'Initial Household', 'IDR', '91000000-0000-0000-0000-000000000001', 'server'),
  ('92000000-0000-0000-0000-000000000002', 'Occupied Household', 'IDR', '91000000-0000-0000-0000-000000000001', 'server'),
  ('92000000-0000-0000-0000-000000000003', 'Other Household', 'IDR', '91000000-0000-0000-0000-000000000003', 'server');

insert into public.book_memberships(book_id, user_id, role, status)
values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002', 'member', 'active'),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000003', 'owner', 'active');

select set_config('app.initial_sync_mode', 'on', true);
insert into public.categories(
  id, book_id, name, category_type, created_at, updated_at, version, device_id
) values (
  '93000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002',
  'Existing', 'expense', now(), now(), 1, 'server'
);
select set_config('app.initial_sync_mode', 'off', true);

select throws_ok(
  $$select public.begin_initial_upload(
    '92000000-0000-0000-0000-000000000001',
    '{"book_id":"92000000-0000-0000-0000-000000000001","counts":{"books":1}}'::jsonb
  )$$,
  null, null, 'unauthenticated initial upload is denied'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.begin_initial_upload(
    '92000000-0000-0000-0000-000000000001',
    '{"book_id":"92000000-0000-0000-0000-000000000001","counts":{"books":1}}'::jsonb
  )$$,
  null, null, 'non-owner cannot claim initial upload'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.begin_initial_upload(
    '92000000-0000-0000-0000-000000000002',
    '{"book_id":"92000000-0000-0000-0000-000000000002","counts":{"books":1}}'::jsonb
  )$$,
  null, null, 'occupied remote household rejects initial upload'
);

select set_config(
  'app.beta04b_manifest',
  '{"book_id":"92000000-0000-0000-0000-000000000001","book_name":"Initial Household","base_currency_code":"IDR","counts":{"books":1,"household_members":0,"categories":0,"projects":0,"accounts":0,"asset_definitions":0,"transactions":0},"snapshot_sequence":0}'::text,
  true
);
select set_config(
  'app.beta04b_session',
  public.begin_initial_upload(
    '92000000-0000-0000-0000-000000000001',
    current_setting('app.beta04b_manifest')::jsonb
  )->>'session_id',
  true
);

select ok(
  current_setting('app.beta04b_session')::uuid is not null,
  'owner claims an empty household initialization'
);
select is(
  public.begin_initial_upload(
    '92000000-0000-0000-0000-000000000001',
    current_setting('app.beta04b_manifest')::jsonb
  )->>'session_id',
  current_setting('app.beta04b_session'),
  'repeated begin returns the one active upload session'
);
select throws_ok(
  $$select public.upload_initial_snapshot_batch(
    current_setting('app.beta04b_session')::uuid,
    'books',
    '[{"id":"92000000-0000-0000-0000-000000000003","name":"Wrong","base_currency_code":"IDR","created_at":"2026-07-26T00:00:00Z","updated_at":"2026-07-26T00:00:00Z","version":1,"device_id":"device-a"}]'::jsonb
  )$$,
  null, null, 'cross-book snapshot row is denied'
);

select is(
  (public.upload_initial_snapshot_batch(
    current_setting('app.beta04b_session')::uuid,
    'books',
    '[{"id":"92000000-0000-0000-0000-000000000001","name":"Initial Household","base_currency_code":"IDR","created_at":"2026-07-26T00:00:00Z","updated_at":"2026-07-26T00:00:00Z","version":1,"device_id":"device-a"}]'::jsonb
  )->>'received_count')::integer,
  1, 'valid snapshot batch is staged'
);
select is(
  (public.upload_initial_snapshot_batch(
    current_setting('app.beta04b_session')::uuid,
    'books',
    '[{"id":"92000000-0000-0000-0000-000000000001","name":"Initial Household","base_currency_code":"IDR","created_at":"2026-07-26T00:00:00Z","updated_at":"2026-07-26T00:00:00Z","version":1,"device_id":"device-a"}]'::jsonb
  )->>'received_count')::integer,
  1, 'identical batch retry is idempotent'
);
set local role postgres;
select is(
  (select count(*) from public.initial_sync_items
    where session_id = current_setting('app.beta04b_session')::uuid),
  1::bigint, 'batch retry does not duplicate staged rows'
);
set local role authenticated;

select is(
  public.complete_initial_upload(
    current_setting('app.beta04b_session')::uuid
  )->>'status',
  'complete', 'complete validates and finalizes the snapshot'
);
set local role postgres;
select is(
  (select status from public.book_sync_initializations
    where book_id = '92000000-0000-0000-0000-000000000001'),
  'complete', 'remote initialization is marked complete'
);
set local role authenticated;
select set_config(
  'app.beta04b_change_count',
  (select count(*)::text from public.app_changes
    where book_id = '92000000-0000-0000-0000-000000000001'),
  true
);
select is(
  public.complete_initial_upload(
    current_setting('app.beta04b_session')::uuid
  )->>'status',
  'complete', 'completion retry is idempotent'
);
select is(
  (select count(*)::text from public.app_changes
    where book_id = '92000000-0000-0000-0000-000000000001'),
  current_setting('app.beta04b_change_count'),
  'completion retry does not duplicate app changes'
);
select throws_ok(
  $$select public.begin_initial_upload(
    '92000000-0000-0000-0000-000000000001',
    current_setting('app.beta04b_manifest')::jsonb
  )$$,
  null, null, 'completed household rejects another initial upload'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'app.beta04b_download',
  public.begin_initial_download(
    '92000000-0000-0000-0000-000000000001'
  )->>'session_id',
  true
);
select is(
  jsonb_array_length(
    public.pull_initial_snapshot_batch(
      current_setting('app.beta04b_download')::uuid, 'books', null, 100
    )->'rows'
  ),
  1, 'authorized member downloads the stable book snapshot'
);
select throws_ok(
  $$select public.begin_initial_download(
    '92000000-0000-0000-0000-000000000003'
  )$$,
  null, null, 'cross-book initial download is denied'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.pull_initial_snapshot_batch(
    current_setting('app.beta04b_download')::uuid, 'books', null, 100
  )$$,
  null, null, 'another household cannot read an active download session'
);

select * from finish();
rollback;
