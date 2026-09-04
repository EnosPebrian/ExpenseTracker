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
select plan(20);

select has_table('public', 'monthly_category_budgets', 'budget table exists');

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('a1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner07a@example.test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'member07a@example.test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other07a@example.test', now(), now(), now());

insert into public.books(id, name, base_currency_code, created_by_user_id, device_id)
values
  (
    'a2000000-0000-0000-0000-000000000001', 'Budget Household', 'IDR',
    'a1000000-0000-0000-0000-000000000001', 'server'
  ),
  (
    'a2000000-0000-0000-0000-000000000002', 'Second Household', 'IDR',
    'a1000000-0000-0000-0000-000000000001', 'server'
  );
insert into public.book_memberships(book_id, user_id, role, status)
values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'member', 'active'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'member', 'active');
insert into public.book_sync_initializations(book_id, status, completed_at)
values
  ('a2000000-0000-0000-0000-000000000001', 'complete', now()),
  ('a2000000-0000-0000-0000-000000000002', 'complete', now());

select set_config('app.initial_sync_mode', 'on', true);
insert into public.categories(
  id, book_id, name, category_type, created_at, updated_at, version, device_id
) values
  (
    'a3000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'Food', 'expense', now(), now(), 1, 'server'
  ),
  (
    'a3000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000002',
    'Food', 'expense', now(), now(), 1, 'server'
  );
select set_config('app.initial_sync_mode', 'off', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

insert into public.monthly_category_budgets(
  id, book_id, category_id, month_start, limit_minor, currency_code, note,
  created_at, updated_at, version, device_id
) values (
  'a4000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001',
  '2026-08-01', 750000, 'IDR', 'Food budget', now(), now(), 1, 'device-a'
);
select is(
  (select count(*) from public.monthly_category_budgets),
  1::bigint,
  'active household member can create a monthly budget'
);

select throws_ok(
  $$insert into public.monthly_category_budgets(
    id, book_id, category_id, month_start, limit_minor, currency_code,
    created_at, updated_at, version, device_id
  ) values (
    'a4000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    '2026-08-01', 1, 'IDR', now(), now(), 1, 'device-a'
  )$$,
  '23505', null,
  'one active budget per household, category, and month is enforced'
);

update public.monthly_category_budgets
set deleted_at = now(), updated_at = now(), version = 2
where id = 'a4000000-0000-0000-0000-000000000001';
insert into public.monthly_category_budgets(
  id, book_id, category_id, month_start, limit_minor, currency_code,
  created_at, updated_at, version, device_id
) values (
  'a4000000-0000-0000-0000-000000000002',
  'a2000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001',
  '2026-08-01', 800000, 'IDR', now(), now(), 1, 'device-a'
);
select is(
  (select count(*) from public.monthly_category_budgets where deleted_at is null),
  1::bigint,
  'a tombstone does not block a replacement active budget'
);

select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000001',
      'entityType', 'monthly_category_budgets',
      'entityId', 'a4000000-0000-0000-0000-000000000003',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-b',
      'payload', jsonb_build_object(
        'id', 'a4000000-0000-0000-0000-000000000003',
        'book_id', 'a2000000-0000-0000-0000-000000000001',
        'category_id', 'a3000000-0000-0000-0000-000000000001',
        'month_start', '2026-09-01', 'limit_minor', 900000,
        'currency_code', 'IDR',
        'created_at', now(), 'updated_at', now(), 'version', 1,
        'device_id', 'device-b'
      )
    ))
  ))->0->>'status',
  'applied',
  'incremental push applies a monthly budget'
);

select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000001',
      'entityType', 'monthly_category_budgets',
      'entityId', 'a4000000-0000-0000-0000-000000000003',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-b',
      'payload', '{}'::jsonb
    ))
  ))->0->>'status',
  'already_applied',
  'a retried budget operation is idempotent'
);
select is(
  (select count(*) from public.monthly_category_budgets
    where id = 'a4000000-0000-0000-0000-000000000003'),
  1::bigint,
  'an idempotent retry does not duplicate the budget'
);

select ok(
  exists(
    select 1
    from jsonb_array_elements(
      public.pull_book_changes(
        'a2000000-0000-0000-0000-000000000001', 0, 100
      )->'changes'
    ) change
    where change->>'entity_type' = 'monthly_category_budgets'
  ),
  'incremental pull includes monthly budget changes'
);

set local role postgres;
select is(
  (public.initial_sync_manifest(
    'a2000000-0000-0000-0000-000000000001', 0, 'download', null
  )->'counts'->>'monthly_category_budgets')::integer,
  3,
  'initial synchronization manifest includes budget tombstones and active rows'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select set_config(
  'app.beta07a_download',
  public.begin_initial_download(
    'a2000000-0000-0000-0000-000000000001'
  )->>'session_id',
  true
);
select is(
  jsonb_array_length(
    public.pull_initial_snapshot_batch(
      current_setting('app.beta07a_download')::uuid,
      'monthly_category_budgets', null, 100
    )->'rows'
  ),
  3,
  'secondary initial download includes active budgets and tombstones'
);

select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000002',
      'entityType', 'monthly_category_budgets',
      'entityId', 'a4000000-0000-0000-0000-000000000003',
      'operationType', 'upsert', 'baseVersion', 1, 'deviceId', 'device-b',
      'payload', (select to_jsonb(b) || jsonb_build_object('limit_minor', 950000)
        from public.monthly_category_budgets b
        where id = 'a4000000-0000-0000-0000-000000000003')
    ))
  ))->0->>'status',
  'applied',
  'a budget update advances the canonical version'
);
select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000003',
      'entityType', 'monthly_category_budgets',
      'entityId', 'a4000000-0000-0000-0000-000000000003',
      'operationType', 'upsert', 'baseVersion', 1, 'deviceId', 'device-c',
      'payload', (select to_jsonb(b) || jsonb_build_object('limit_minor', 960000)
        from public.monthly_category_budgets b
        where id = 'a4000000-0000-0000-0000-000000000003')
    ))
  ))->0->>'status',
  'version_conflict',
  'a stale budget update creates an explicit conflict'
);
select is(
  (public.resolve_sync_conflict(
    'a2000000-0000-0000-0000-000000000001',
    'monthly_category_budgets',
    'a4000000-0000-0000-0000-000000000003',
    2,
    'a5000000-0000-0000-0000-000000000004',
    'keepDevice',
    (select to_jsonb(b) || jsonb_build_object('limit_minor', 960000)
      from public.monthly_category_budgets b
      where id = 'a4000000-0000-0000-0000-000000000003')
  )->>'status'),
  'resolved',
  'budget conflicts use the existing explicit resolution RPC'
);
select is(
  (select limit_minor from public.monthly_category_budgets
    where id = 'a4000000-0000-0000-0000-000000000003'),
  960000::bigint,
  'the chosen budget conflict value becomes canonical'
);
select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000005',
      'entityType', 'monthly_category_budgets',
      'entityId', 'a4000000-0000-0000-0000-000000000003',
      'operationType', 'delete', 'baseVersion', 3, 'deviceId', 'device-b',
      'payload', (select to_jsonb(b) from public.monthly_category_budgets b
        where id = 'a4000000-0000-0000-0000-000000000003')
    ))
  ))->0->>'status',
  'applied',
  'budget deletion synchronizes as a tombstone'
);
select isnt(
  (select deleted_at from public.monthly_category_budgets
    where id = 'a4000000-0000-0000-0000-000000000003'),
  null::timestamptz,
  'the canonical budget tombstone is retained'
);
select throws_ok(
  $$update public.monthly_category_budgets
    set book_id = 'a2000000-0000-0000-0000-000000000002',
        category_id = 'a3000000-0000-0000-0000-000000000002'
    where id = 'a4000000-0000-0000-0000-000000000002'$$,
  null, null,
  'a client cannot move a budget between households'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.monthly_category_budgets),
  0::bigint,
  'RLS hides another household budgets'
);
select throws_ok(
  $$insert into public.monthly_category_budgets(
    id, book_id, category_id, month_start, limit_minor, currency_code,
    created_at, updated_at, version, device_id
  ) values (
    'a4000000-0000-0000-0000-000000000099',
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    '2026-10-01', 1, 'IDR', now(), now(), 1, 'other-device'
  )$$,
  '42501', null,
  'RLS rejects another household budget write'
);

set local role anon;
select throws_ok(
  $$select * from public.monthly_category_budgets$$,
  '42501', null,
  'unauthenticated clients cannot read monthly budgets'
);

select * from finish();
rollback;
