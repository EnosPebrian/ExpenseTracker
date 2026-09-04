begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path', format('public,%I', namespace.nspname), true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(16);

select has_table('public', 'transfer_links', 'transfer link table exists');
select is(
  (select relrowsecurity from pg_class
    where oid = 'public.transfer_links'::regclass),
  true,
  'RLS is enabled'
);

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('f0100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner08f0@example.test', now(), now(), now()),
  ('f0100000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'member08f0@example.test', now(), now(), now()),
  ('f0100000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other08f0@example.test', now(), now(), now());
insert into public.books(id, name, base_currency_code, created_by_user_id, device_id)
values
  ('f0200000-0000-0000-0000-000000000001', 'Transfer Household', 'IDR', 'f0100000-0000-0000-0000-000000000001', 'server'),
  ('f0200000-0000-0000-0000-000000000002', 'Other Household', 'IDR', 'f0100000-0000-0000-0000-000000000003', 'server');
insert into public.book_memberships(book_id, user_id, role, status)
values
  ('f0200000-0000-0000-0000-000000000001', 'f0100000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('f0200000-0000-0000-0000-000000000001', 'f0100000-0000-0000-0000-000000000002', 'member', 'active'),
  ('f0200000-0000-0000-0000-000000000002', 'f0100000-0000-0000-0000-000000000003', 'owner', 'active');
insert into public.book_sync_initializations(book_id, status, completed_at)
values
  ('f0200000-0000-0000-0000-000000000001', 'complete', now()),
  ('f0200000-0000-0000-0000-000000000002', 'complete', now());

select set_config('app.initial_sync_mode', 'on', true);
insert into public.accounts(
  id, book_id, name, account_type, currency_code,
  created_at, updated_at, version, device_id
) values
  ('f0300000-0000-0000-0000-000000000001', 'f0200000-0000-0000-0000-000000000001', 'Cash', 'cash', 'IDR', now(), now(), 1, 'server'),
  ('f0300000-0000-0000-0000-000000000002', 'f0200000-0000-0000-0000-000000000001', 'Bank', 'bank', 'IDR', now(), now(), 1, 'server'),
  ('f0300000-0000-0000-0000-000000000003', 'f0200000-0000-0000-0000-000000000002', 'Other', 'bank', 'IDR', now(), now(), 1, 'server');
insert into public.transactions(
  id, book_id, title, category, account, transaction_date, amount,
  transaction_type, created_at, updated_at, version, device_id
) values
  ('f0400000-0000-0000-0000-000000000001', 'f0200000-0000-0000-0000-000000000001', 'Move cash', 'Transfer', 'Cash', now(), 100000, 'expense', now(), now(), 1, 'device-a'),
  ('f0400000-0000-0000-0000-000000000002', 'f0200000-0000-0000-0000-000000000001', 'Move cash', 'Transfer', 'Bank', now(), 100000, 'income', now(), now(), 1, 'device-a'),
  ('f0400000-0000-0000-0000-000000000003', 'f0200000-0000-0000-0000-000000000002', 'Other', 'Transfer', 'Other', now(), 100000, 'income', now(), now(), 1, 'device-c');
select set_config('app.initial_sync_mode', 'off', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select lives_ok(
  $$insert into public.transfer_links(
    id, book_id, outgoing_transaction_id, incoming_transaction_id,
    source_account_id, destination_account_id, currency_code, amount,
    created_at, updated_at, version, device_id
  ) values (
    'f0500000-0000-0000-0000-000000000001',
    'f0200000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000002',
    'f0300000-0000-0000-0000-000000000001',
    'f0300000-0000-0000-0000-000000000002',
    'IDR', 100000, now(), now(), 1, 'device-a'
  )$$,
  'member can create a valid same-book pair'
);
select is(
  (select count(*) from public.transfer_links),
  1::bigint,
  'member reads the own-household pair'
);
select throws_ok(
  $$insert into public.transfer_links(
    id, book_id, outgoing_transaction_id, incoming_transaction_id,
    source_account_id, destination_account_id, currency_code, amount,
    created_at, updated_at, version, device_id
  ) values (
    'f0500000-0000-0000-0000-000000000002',
    'f0200000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000002',
    'f0300000-0000-0000-0000-000000000001',
    'f0300000-0000-0000-0000-000000000002',
    'IDR', 100000, now(), now(), 1, 'device-a'
  )$$,
  '23505', null,
  'a leg cannot belong to two active pairs'
);
select throws_ok(
  $$update public.transfer_links
    set incoming_transaction_id = 'f0400000-0000-0000-0000-000000000003'
    where id = 'f0500000-0000-0000-0000-000000000001'$$,
  null, null,
  'relation direction and identity are immutable'
);
select throws_ok(
  $$insert into public.transfer_links(
    id, book_id, outgoing_transaction_id, incoming_transaction_id,
    source_account_id, destination_account_id, currency_code, amount,
    created_at, updated_at, version, device_id
  ) values (
    'f0500000-0000-0000-0000-000000000003',
    'f0200000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000003',
    'f0300000-0000-0000-0000-000000000001',
    'f0300000-0000-0000-0000-000000000003',
    'IDR', 100000, now(), now(), 1, 'device-a'
  )$$,
  null, null,
  'cross-household legs and accounts are rejected'
);

select is(
  (public.push_book_changes(
    'f0200000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'f0600000-0000-0000-0000-000000000001',
      'entityType', 'transfer_links',
      'entityId', 'f0500000-0000-0000-0000-000000000001',
      'operationType', 'delete', 'baseVersion', 1, 'deviceId', 'device-a',
      'payload', jsonb_build_object(
        'id', 'f0500000-0000-0000-0000-000000000001',
        'book_id', 'f0200000-0000-0000-0000-000000000001',
        'outgoing_transaction_id', 'f0400000-0000-0000-0000-000000000001',
        'incoming_transaction_id', 'f0400000-0000-0000-0000-000000000002',
        'source_account_id', 'f0300000-0000-0000-0000-000000000001',
        'destination_account_id', 'f0300000-0000-0000-0000-000000000002',
        'currency_code', 'IDR', 'amount', 100000,
        'created_at', now(), 'updated_at', now(), 'deleted_at', now(),
        'version', 2, 'device_id', 'device-a'
      )
    ))
  ))->0->>'status',
  'applied',
  'ordinary incremental push tombstones a pair'
);
select is(
  (public.push_book_changes(
    'f0200000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'f0600000-0000-0000-0000-000000000001',
      'entityType', 'transfer_links', 'entityId', 'f0500000-0000-0000-0000-000000000001',
      'operationType', 'delete', 'baseVersion', 1, 'deviceId', 'device-a',
      'payload', '{}'::jsonb
    ))
  ))->0->>'status',
  'already_applied',
  'pair push retry is idempotent'
);
select isnt(
  (select deleted_at from public.transfer_links
    where id = 'f0500000-0000-0000-0000-000000000001'),
  null::timestamptz,
  'pair tombstone is retained'
);
select ok(
  exists(
    select 1 from jsonb_array_elements(
      public.pull_book_changes(
        'f0200000-0000-0000-0000-000000000001', 0, 100
      )->'changes'
    ) change where change->>'entity_type' = 'transfer_links'
  ),
  'incremental pull includes transfer links'
);

set local role postgres;
select is(
  (public.initial_sync_manifest(
    'f0200000-0000-0000-0000-000000000001', 0, 'download', null
  )->'counts'->>'transfer_links')::integer,
  1,
  'initial manifest counts transfer links'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"f0100000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'app.beta08f0_download',
  public.begin_initial_download(
    'f0200000-0000-0000-0000-000000000001'
  )->>'session_id',
  true
);
select is(
  jsonb_array_length(
    public.pull_initial_snapshot_batch(
      current_setting('app.beta08f0_download')::uuid,
      'transfer_links', null, 100
    )->'rows'
  ),
  1,
  'initial download includes transfer links'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f0100000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.transfer_links),
  0::bigint,
  'RLS hides unrelated-household pairs'
);
select throws_ok(
  $$insert into public.transfer_links(
    id, book_id, outgoing_transaction_id, incoming_transaction_id,
    source_account_id, destination_account_id, currency_code, amount,
    created_at, updated_at, version, device_id
  ) values (
    'f0500000-0000-0000-0000-000000000099',
    'f0200000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000001',
    'f0400000-0000-0000-0000-000000000002',
    'f0300000-0000-0000-0000-000000000001',
    'f0300000-0000-0000-0000-000000000002',
    'IDR', 100000, now(), now(), 1, 'other'
  )$$,
  '42501', null,
  'RLS denies unrelated-household writes'
);

set local role anon;
select throws_ok(
  $$select * from public.transfer_links$$,
  '42501', null,
  'unauthenticated clients cannot read transfer links'
);

select * from finish();
rollback;
