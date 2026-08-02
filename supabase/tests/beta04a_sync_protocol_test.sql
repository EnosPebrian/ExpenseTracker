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
select plan(16);

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('81000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@example.test', now(), now(), now()),
  ('81000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'member@example.test', now(), now(), now()),
  ('81000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other@example.test', now(), now(), now());

insert into public.books(id, name, base_currency_code, created_by_user_id, device_id)
values
  ('82000000-0000-0000-0000-000000000001', 'Household', 'IDR', '81000000-0000-0000-0000-000000000001', 'server'),
  ('82000000-0000-0000-0000-000000000002', 'Other', 'IDR', '81000000-0000-0000-0000-000000000003', 'server');
insert into public.book_memberships(book_id, user_id, role, status)
values
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002', 'member', 'active'),
  ('82000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000003', 'owner', 'active');
insert into public.book_sync_initializations(book_id, status, completed_at) values
  ('82000000-0000-0000-0000-000000000001', 'complete', now()),
  ('82000000-0000-0000-0000-000000000002', 'complete', now());
insert into public.processed_sync_operations(
  operation_id, book_id, entity_type, entity_id, result_status
) values (
  '83000000-0000-0000-0000-000000000099',
  '82000000-0000-0000-0000-000000000002',
  'transactions', '84000000-0000-0000-0000-000000000099', 'applied'
);

select set_config('app.sync_baseline', (select max(sequence)::text from public.app_changes), true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated","email":"member@example.test"}', true);

select throws_ok(
  $$select public.push_book_changes(
    '82000000-0000-0000-0000-000000000002', '[]'::jsonb
  )$$,
  null, null, 'non-member push is denied'
);

select throws_ok(
  $$select public.pull_book_changes(
    '82000000-0000-0000-0000-000000000002', 0, 100
  )$$,
  null, null, 'non-member pull is denied'
);

select is(
  (public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', '83000000-0000-0000-0000-000000000001',
      'entityType', 'transactions',
      'entityId', '84000000-0000-0000-0000-000000000001',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-a',
      'payload', jsonb_build_object(
        'id', '84000000-0000-0000-0000-000000000001',
        'book_id', '82000000-0000-0000-0000-000000000002',
        'title', 'Wrong', 'category', 'Food', 'account', 'Cash',
        'transaction_date', now(), 'amount', 100, 'transaction_type', 'expense',
        'fee_amount', 0, 'fee_treatment', 'none', 'relation_type', 'none',
        'created_at', now(), 'updated_at', now(), 'version', 1,
        'device_id', 'device-a'
      )
    ))
  ))->0->>'status',
  'validation_error', 'cross-book payload is rejected'
);

select is(
  (public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', '83000000-0000-0000-0000-000000000002',
      'entityType', 'transactions',
      'entityId', '84000000-0000-0000-0000-000000000002',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-a',
      'payload', jsonb_build_object(
        'id', '84000000-0000-0000-0000-000000000002',
        'book_id', '82000000-0000-0000-0000-000000000001',
        'title', 'Lunch', 'category', 'Food', 'account', 'Cash',
        'transaction_date', now(), 'amount', 100, 'transaction_type', 'expense',
        'fee_amount', 0, 'fee_treatment', 'none', 'relation_type', 'none',
        'created_at', now(), 'updated_at', now(), 'version', 1,
        'device_id', 'device-a'
      )
    ))
  ))->0->>'status',
  'applied', 'valid insert is applied'
);

select is(
  (public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', '83000000-0000-0000-0000-000000000002',
      'entityType', 'transactions',
      'entityId', '84000000-0000-0000-0000-000000000002',
      'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-a',
      'payload', '{}'::jsonb
    ))
  ))->0->>'status',
  'already_applied', 'duplicate operation returns already applied'
);
select is(
  (select count(*) from public.transactions where id = '84000000-0000-0000-0000-000000000002'),
  1::bigint, 'duplicate operation does not duplicate transaction'
);
select is(
  (select count(*) from public.app_changes
    where entity_table = 'transactions'
      and entity_id = '84000000-0000-0000-0000-000000000002'),
  1::bigint, 'duplicate operation creates one app change'
);

select is(
  (public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', '83000000-0000-0000-0000-000000000003',
      'entityType', 'transactions',
      'entityId', '84000000-0000-0000-0000-000000000002',
      'operationType', 'upsert', 'baseVersion', 1, 'deviceId', 'device-a',
      'payload', (select to_jsonb(t) || jsonb_build_object('amount', 150)
        from public.transactions t where id = '84000000-0000-0000-0000-000000000002')
    ))
  ))->0->>'status',
  'applied', 'valid update is applied'
);
select is(
  (public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', '83000000-0000-0000-0000-000000000004',
      'entityType', 'transactions',
      'entityId', '84000000-0000-0000-0000-000000000002',
      'operationType', 'upsert', 'baseVersion', 1, 'deviceId', 'device-b',
      'payload', (select to_jsonb(t) from public.transactions t
        where id = '84000000-0000-0000-0000-000000000002')
    ))
  ))->0->>'status',
  'version_conflict', 'stale base version preserves a conflict'
);
select is(
  (public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', '83000000-0000-0000-0000-000000000005',
      'entityType', 'transactions',
      'entityId', '84000000-0000-0000-0000-000000000002',
      'operationType', 'delete', 'baseVersion', 2, 'deviceId', 'device-a',
      'payload', (select to_jsonb(t) from public.transactions t
        where id = '84000000-0000-0000-0000-000000000002')
    ))
  ))->0->>'status',
  'applied', 'valid deletion is applied as tombstone'
);
select isnt(
  (select deleted_at from public.transactions
    where id = '84000000-0000-0000-0000-000000000002'),
  null::timestamptz, 'canonical deletion retains a tombstone'
);

select is(
  jsonb_array_length(public.push_book_changes(
    '82000000-0000-0000-0000-000000000001',
    jsonb_build_array(
      jsonb_build_object(
        'operationId', '83000000-0000-0000-0000-000000000006',
        'entityType', 'categories',
        'entityId', '85000000-0000-0000-0000-000000000001',
        'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-a',
        'payload', jsonb_build_object(
          'id', '85000000-0000-0000-0000-000000000001',
          'book_id', '82000000-0000-0000-0000-000000000001',
          'name', 'Food', 'category_type', 'expense', 'created_at', now(),
          'updated_at', now(), 'version', 1, 'device_id', 'device-a'
        )
      ),
      jsonb_build_object(
        'operationId', '83000000-0000-0000-0000-000000000007',
        'entityType', 'projects',
        'entityId', '85000000-0000-0000-0000-000000000002',
        'operationType', 'upsert', 'baseVersion', 0, 'deviceId', 'device-a',
        'payload', jsonb_build_object(
          'id', '85000000-0000-0000-0000-000000000002',
          'book_id', '82000000-0000-0000-0000-000000000001',
          'name', 'Life', 'status', 'active', 'created_at', now(),
          'updated_at', now(), 'version', 1, 'device_id', 'device-a'
        )
      )
    )
  )),
  2, 'batch returns one result per operation'
);

select ok(
  ((public.pull_book_changes(
    '82000000-0000-0000-0000-000000000001',
    current_setting('app.sync_baseline')::bigint, 100
  )->'changes'->0->>'sequence')::bigint <
  (public.pull_book_changes(
    '82000000-0000-0000-0000-000000000001',
    current_setting('app.sync_baseline')::bigint, 100
  )->>'final_sequence')::bigint),
  'pull changes are ordered and cursor ends at the final change'
);
select is(
  jsonb_array_length(public.pull_book_changes(
    '82000000-0000-0000-0000-000000000001', 999999999, 100
  )->'changes'),
  0, 'pull returns an empty batch safely'
);
select is(
  jsonb_array_length(public.pull_book_changes(
    '82000000-0000-0000-0000-000000000001',
    current_setting('app.sync_baseline')::bigint, 1
  )->'changes'),
  1, 'pull enforces pagination limit'
);
select is(
  (select count(*) from public.processed_sync_operations
    where book_id = '82000000-0000-0000-0000-000000000002'),
  0::bigint, 'processed operation RLS denies cross-book browsing'
);

select * from finish();
rollback;
