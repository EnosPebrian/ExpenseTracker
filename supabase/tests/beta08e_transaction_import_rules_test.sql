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

select has_table(
  'public', 'transaction_import_rules', 'import-rule table exists'
);
select is(
  (select relrowsecurity from pg_class
    where oid = 'public.transaction_import_rules'::regclass),
  true,
  'RLS is enabled'
);

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('e1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner08e@example.test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'member08e@example.test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other08e@example.test', now(), now(), now());
insert into public.books(id, name, base_currency_code, created_by_user_id, device_id)
values
  ('e2000000-0000-0000-0000-000000000001', 'Rule Household', 'IDR', 'e1000000-0000-0000-0000-000000000001', 'server'),
  ('e2000000-0000-0000-0000-000000000002', 'Other Household', 'IDR', 'e1000000-0000-0000-0000-000000000003', 'server');
insert into public.book_memberships(book_id, user_id, role, status)
values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 'member', 'active'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000003', 'owner', 'active');
insert into public.book_sync_initializations(book_id, status, completed_at)
values
  ('e2000000-0000-0000-0000-000000000001', 'complete', now()),
  ('e2000000-0000-0000-0000-000000000002', 'complete', now());

select set_config('app.initial_sync_mode', 'on', true);
insert into public.categories(
  id, book_id, name, category_type, created_at, updated_at, version, device_id
) values
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Fuel', 'expense', now(), now(), 1, 'server'),
  ('e3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'Other', 'expense', now(), now(), 1, 'server');
insert into public.accounts(
  id, book_id, name, account_type, currency_code, created_at, updated_at, version, device_id
) values
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Bank', 'bank', 'IDR', now(), now(), 1, 'server'),
  ('e4000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'Other bank', 'bank', 'IDR', now(), now(), 1, 'server');
select set_config('app.initial_sync_mode', 'off', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select lives_ok(
  $$insert into public.transaction_import_rules(
    id, book_id, name, enabled, priority, transaction_type, match_field,
    match_operator, pattern, pattern_key, account_id, category_id,
    created_at, updated_at, version, device_id
  ) values (
    'e5000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001', 'Pertamina', true, 100,
    'expense', 'description', 'contains', 'PERTAMINA', 'pertamina',
    'e4000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001', now(), now(), 1, 'device-a'
  )$$,
  'member can create an own-household rule'
);
select is(
  (select count(*) from public.transaction_import_rules),
  1::bigint,
  'member reads own-household rules'
);
select throws_ok(
  $$insert into public.transaction_import_rules(
    id, book_id, name, enabled, priority, transaction_type, match_field,
    match_operator, pattern, pattern_key, account_id, category_id,
    created_at, updated_at, version, device_id
  ) values (
    'e5000000-0000-0000-0000-000000000002',
    'e2000000-0000-0000-0000-000000000001', 'Duplicate', true, 1,
    'expense', 'description', 'contains', 'pertamina', 'pertamina',
    'e4000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001', now(), now(), 1, 'device-a'
  )$$,
  '23505', null,
  'active semantic duplicates are rejected'
);
select throws_ok(
  $$insert into public.transaction_import_rules(
    id, book_id, name, enabled, priority, transaction_type, match_field,
    match_operator, pattern, pattern_key, category_id,
    created_at, updated_at, version, device_id
  ) values (
    'e5000000-0000-0000-0000-000000000003',
    'e2000000-0000-0000-0000-000000000001', 'Foreign category', true, 1,
    'expense', 'description', 'contains', 'foreign', 'foreign',
    'e3000000-0000-0000-0000-000000000002', now(), now(), 1, 'device-a'
  )$$,
  null, null,
  'cross-household category is rejected'
);
select throws_ok(
  $$insert into public.transaction_import_rules(
    id, book_id, name, enabled, priority, transaction_type, match_field,
    match_operator, pattern, pattern_key, account_id, category_id,
    created_at, updated_at, version, device_id
  ) values (
    'e5000000-0000-0000-0000-000000000004',
    'e2000000-0000-0000-0000-000000000001', 'Foreign account', true, 1,
    'expense', 'description', 'contains', 'foreign account', 'foreign account',
    'e4000000-0000-0000-0000-000000000002',
    'e3000000-0000-0000-0000-000000000001', now(), now(), 1, 'device-a'
  )$$,
  null, null,
  'cross-household account is rejected'
);
select throws_ok(
  $$update public.transaction_import_rules
    set book_id = 'e2000000-0000-0000-0000-000000000002'
    where id = 'e5000000-0000-0000-0000-000000000001'$$,
  null, null,
  'a rule cannot move households'
);

select is(
  (public.push_book_changes(
    'e2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'e6000000-0000-0000-0000-000000000001',
      'entityType', 'transaction_import_rules',
      'entityId', 'e5000000-0000-0000-0000-000000000005',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-b',
      'payload', jsonb_build_object(
        'id', 'e5000000-0000-0000-0000-000000000005',
        'book_id', 'e2000000-0000-0000-0000-000000000001',
        'name', 'PLN', 'enabled', true, 'priority', 90,
        'transaction_type', 'expense', 'match_field', 'description',
        'match_operator', 'startsWith', 'pattern', 'PLN', 'pattern_key', 'pln',
        'account_id', null,
        'category_id', 'e3000000-0000-0000-0000-000000000001',
        'created_at', now(), 'updated_at', now(), 'version', 1,
        'device_id', 'device-b'
      )
    ))
  ))->0->>'status',
  'applied',
  'incremental push applies a rule'
);
select is(
  (public.push_book_changes(
    'e2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'e6000000-0000-0000-0000-000000000001',
      'entityType', 'transaction_import_rules',
      'entityId', 'e5000000-0000-0000-0000-000000000005',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-b',
      'payload', '{}'::jsonb
    ))
  ))->0->>'status',
  'already_applied',
  'rule push retry is idempotent'
);
select ok(
  exists(
    select 1 from jsonb_array_elements(
      public.pull_book_changes(
        'e2000000-0000-0000-0000-000000000001', 0, 100
      )->'changes'
    ) change
    where change->>'entity_type' = 'transaction_import_rules'
  ),
  'incremental pull includes rules'
);

set local role postgres;
select is(
  (public.initial_sync_manifest(
    'e2000000-0000-0000-0000-000000000001', 0, 'download', null
  )->'counts'->>'transaction_import_rules')::integer,
  2,
  'initial manifest counts rules'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'app.beta08e_download',
  public.begin_initial_download(
    'e2000000-0000-0000-0000-000000000001'
  )->>'session_id',
  true
);
select is(
  jsonb_array_length(
    public.pull_initial_snapshot_batch(
      current_setting('app.beta08e_download')::uuid,
      'transaction_import_rules', null, 100
    )->'rows'
  ),
  2,
  'initial download includes rules'
);
update public.transaction_import_rules
set deleted_at = now(), updated_at = now(), version = version + 1
where id = 'e5000000-0000-0000-0000-000000000005';
select isnt(
  (select deleted_at from public.transaction_import_rules
    where id = 'e5000000-0000-0000-0000-000000000005'),
  null::timestamptz,
  'rule tombstone is retained'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.transaction_import_rules),
  0::bigint,
  'RLS hides unrelated-household rules'
);
select throws_ok(
  $$insert into public.transaction_import_rules(
    id, book_id, name, enabled, priority, transaction_type, match_field,
    match_operator, pattern, pattern_key, category_id,
    created_at, updated_at, version, device_id
  ) values (
    'e5000000-0000-0000-0000-000000000099',
    'e2000000-0000-0000-0000-000000000001', 'Denied', true, 1,
    'expense', 'description', 'contains', 'denied', 'denied',
    'e3000000-0000-0000-0000-000000000001', now(), now(), 1, 'other'
  )$$,
  '42501', null,
  'RLS denies unrelated-household writes'
);

set local role anon;
select throws_ok(
  $$select * from public.transaction_import_rules$$,
  '42501', null,
  'unauthenticated clients cannot read rules'
);

select * from finish();
rollback;
