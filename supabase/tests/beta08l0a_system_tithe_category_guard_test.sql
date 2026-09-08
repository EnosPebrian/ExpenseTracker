begin;
create extension if not exists pgtap;
set local role postgres;
select set_config(
  'search_path', format('public,%I', namespace.nspname), true
) from pg_extension extension
join pg_namespace namespace on namespace.oid = extension.extnamespace
where extension.extname = 'pgtap';
select plan(43);

select has_function(
  'public', 'system_tithe_category_id', array['uuid'],
  'canonical System Tithe ID helper exists'
);
select has_function(
  'public', 'guard_system_tithe_category', array[]::text[],
  'System Tithe category guard function exists'
);
select is(
  public.system_tithe_category_id('00000000-0000-0000-0000-000000000000'),
  '974e8a60-8e63-5615-a4fd-b8acb4ecfec5'::uuid,
  'UUIDv5 golden vector 1 matches the Dart-compatible result'
);
select is(
  public.system_tithe_category_id('11111111-1111-1111-1111-111111111111'),
  '2a753de7-0888-5d83-ab12-de274b13c6f0'::uuid,
  'UUIDv5 golden vector 2 matches the Dart-compatible result'
);
select is(
  public.system_tithe_category_id('a2000000-0000-0000-0000-000000000001'),
  '2daf63af-1d0b-539b-be96-174948bb8ed0'::uuid,
  'UUIDv5 golden vector 3 matches the Dart-compatible result'
);

select ok(
  not has_function_privilege(
    'public', 'public.system_tithe_category_id(uuid)', 'EXECUTE'
  ),
  'PUBLIC cannot execute the canonical ID helper'
);
select ok(
  not has_function_privilege(
    'anon', 'public.system_tithe_category_id(uuid)', 'EXECUTE'
  ),
  'anon cannot execute the canonical ID helper'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.system_tithe_category_id(uuid)', 'EXECUTE'
  ),
  'authenticated cannot execute the canonical ID helper'
);
select ok(
  not has_function_privilege(
    'public', 'public.guard_system_tithe_category()', 'EXECUTE'
  ),
  'PUBLIC cannot execute the trigger function directly'
);
select ok(
  not has_function_privilege(
    'anon', 'public.guard_system_tithe_category()', 'EXECUTE'
  ),
  'anon cannot execute the trigger function directly'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.guard_system_tithe_category()', 'EXECUTE'
  ),
  'authenticated cannot execute the trigger function directly'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.categories'::regclass
      and tgname = 'guard_system_tithe_category_before_write'
      and tgenabled = 'O'
      and not tgisinternal
  ),
  'category guard trigger exists and is enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.categories'::regclass),
  'categories RLS remains enabled'
);
select is(
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename = 'categories'),
  4::bigint,
  'existing category RLS policies remain unchanged'
);

insert into auth.users(id, aud, role, email, created_at, updated_at)
values (
  'a1000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'l0a@example.test', now(), now()
);
insert into public.books(id, name, base_currency_code, created_by_user_id, device_id)
values
  ('a2000000-0000-0000-0000-000000000001', 'L0A', 'IDR',
   'a1000000-0000-0000-0000-000000000001', 'server'),
  ('b2000000-0000-0000-0000-000000000001', 'L0A initial', 'IDR',
   'a1000000-0000-0000-0000-000000000001', 'server');
insert into public.book_memberships(book_id, user_id, role, status)
values (
  'a2000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001', 'owner', 'active'
);
insert into public.book_sync_initializations(book_id, status, completed_at)
values
  ('a2000000-0000-0000-0000-000000000001', 'complete', now()),
  ('b2000000-0000-0000-0000-000000000001', 'complete', now());

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, version, device_id
    ) values (
      '2daf63af-1d0b-539b-be96-174948bb8ed0',
      'a2000000-0000-0000-0000-000000000001',
      'Tithe', 'expense', now(), now(), 1, 'client-old'
    )$$,
  'valid canonical System Tithe insert succeeds'
);
select throws_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, version, device_id
    ) values (
      public.system_tithe_category_id('b2000000-0000-0000-0000-000000000001'),
      'b2000000-0000-0000-0000-000000000001',
      'Church', 'expense', now(), now(), 1, 'initial'
    )$$,
  '42501', 'permission denied for function system_tithe_category_id',
  'authenticated cannot use the helper to attempt a malformed insert'
);

set local role postgres;
select throws_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, version, device_id
    ) values (
      public.system_tithe_category_id('b2000000-0000-0000-0000-000000000001'),
      'b2000000-0000-0000-0000-000000000001',
      'Church', 'expense', now(), now(), 1, 'old-client'
    )$$,
  '23514',
  'System Tithe category must use canonical name, expense type, and live state',
  'canonical insert with wrong name is rejected'
);
select throws_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, version, device_id
    ) values (
      public.system_tithe_category_id('b2000000-0000-0000-0000-000000000001'),
      'b2000000-0000-0000-0000-000000000001',
      'Tithe', 'income', now(), now(), 1, 'old-client'
    )$$,
  '23514',
  'System Tithe category must use canonical name, expense type, and live state',
  'canonical insert with wrong type is rejected'
);
select throws_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, deleted_at,
      version, device_id
    ) values (
      public.system_tithe_category_id('b2000000-0000-0000-0000-000000000001'),
      'b2000000-0000-0000-0000-000000000001',
      'Tithe', 'expense', now(), now(), now(), 1, 'old-client'
    )$$,
  '23514',
  'System Tithe category must use canonical name, expense type, and live state',
  'canonical deleted insert is rejected'
);

set local role authenticated;
select throws_ok(
  $$update public.categories set name = 'Church'
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category identity and semantics are immutable',
  'authenticated direct canonical rename is rejected'
);
select throws_ok(
  $$update public.categories set category_type = 'income'
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category identity and semantics are immutable',
  'canonical type change is rejected'
);
select throws_ok(
  $$update public.categories set deleted_at = now()
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category identity and semantics are immutable',
  'canonical soft delete is rejected'
);
select throws_ok(
  $$delete from public.categories
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category cannot be deleted',
  'canonical hard delete is rejected'
);
select throws_ok(
  $$update public.categories
    set book_id = 'b2000000-0000-0000-0000-000000000001'
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category identity and semantics are immutable',
  'canonical category cannot move household'
);
select throws_ok(
  $$update public.categories
    set id = 'a3000000-0000-0000-0000-000000000099'
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category identity and semantics are immutable',
  'canonical category identity cannot change'
);

select lives_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, version, device_id
    ) values (
      'a3000000-0000-0000-0000-000000000001',
      'a2000000-0000-0000-0000-000000000001',
      'Food', 'expense', now(), now(), 1, 'client'
    )$$,
  'ordinary category insert is unaffected'
);
select throws_ok(
  $$update public.categories
    set id = '2daf63af-1d0b-539b-be96-174948bb8ed0', name = 'Tithe'
    where id = 'a3000000-0000-0000-0000-000000000001'$$,
  '23514', 'Ordinary category cannot become System Tithe',
  'ordinary category cannot mutate into canonical identity'
);
select lives_ok(
  $$update public.categories
    set updated_at = now() + interval '1 minute', version = 2,
        device_id = 'sync-metadata'
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  'metadata-only canonical update succeeds'
);
select is(
  (select device_id from public.categories
   where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'),
  'sync-metadata',
  'metadata-only canonical update is persisted'
);
select lives_ok(
  $$insert into public.categories(
      id, book_id, name, category_type, created_at, updated_at, version, device_id
    ) values (
      'a3000000-0000-0000-0000-000000000002',
      'a2000000-0000-0000-0000-000000000001',
      'Tithe', 'expense', now(), now(), 1, 'custom'
    )$$,
  'random-ID custom category named Tithe remains ordinary'
);
select lives_ok(
  $$update public.categories set name = 'Giving'
    where id = 'a3000000-0000-0000-0000-000000000002'$$,
  'random-ID custom Tithe category remains editable'
);
select lives_ok(
  $$delete from public.categories
    where id = 'a3000000-0000-0000-0000-000000000002'$$,
  'random-ID custom Tithe category remains deletable'
);
select lives_ok(
  $$update public.categories
    set name = 'Salary', category_type = 'income'
    where id = 'a3000000-0000-0000-0000-000000000001'$$,
  'ordinary category update remains unaffected'
);
select lives_ok(
  $$delete from public.categories
    where id = 'a3000000-0000-0000-0000-000000000001'$$,
  'ordinary category delete remains unaffected'
);

set local role postgres;
grant select, update on public.categories to service_role;
set local role service_role;
select throws_ok(
  $$update public.categories set name = 'Service overwrite'
    where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'$$,
  '23514', 'System Tithe category identity and semantics are immutable',
  'service-role application write cannot bypass the guard'
);

set local role authenticated;
select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000001',
      'entityType', 'categories',
      'entityId', '2daf63af-1d0b-539b-be96-174948bb8ed0',
      'operationType', 'upsert',
      'baseVersion', 2,
      'deviceId', 'old-sync',
      'payload', (select to_jsonb(category) || '{"name":"Church"}'::jsonb
        from public.categories category
        where id = '2daf63af-1d0b-539b-be96-174948bb8ed0')
    ))
  ))->0->>'status',
  'validation_error',
  'sync path rejects canonical rename'
);
select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000002',
      'entityType', 'categories',
      'entityId', '2daf63af-1d0b-539b-be96-174948bb8ed0',
      'operationType', 'upsert',
      'baseVersion', 2,
      'deviceId', 'old-sync',
      'payload', (select to_jsonb(category) || '{"category_type":"income"}'::jsonb
        from public.categories category
        where id = '2daf63af-1d0b-539b-be96-174948bb8ed0')
    ))
  ))->0->>'status',
  'validation_error',
  'sync path rejects canonical type change'
);
select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000004',
      'entityType', 'categories',
      'entityId', '2daf63af-1d0b-539b-be96-174948bb8ed0',
      'operationType', 'upsert',
      'baseVersion', 2,
      'deviceId', 'old-sync',
      'payload', (select to_jsonb(category) || jsonb_build_object(
          'deleted_at', now()
        )
        from public.categories category
        where id = '2daf63af-1d0b-539b-be96-174948bb8ed0')
    ))
  ))->0->>'status',
  'validation_error',
  'sync path rejects canonical soft delete'
);
select is(
  (public.push_book_changes(
    'a2000000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'operationId', 'a5000000-0000-0000-0000-000000000005',
      'entityType', 'categories',
      'entityId', '2daf63af-1d0b-539b-be96-174948bb8ed0',
      'operationType', 'delete',
      'baseVersion', 2,
      'deviceId', 'old-sync',
      'payload', (select to_jsonb(category)
        from public.categories category
        where id = '2daf63af-1d0b-539b-be96-174948bb8ed0')
    ))
  ))->0->>'status',
  'validation_error',
  'sync delete path rejects canonical tombstoning'
);
select is(
  public.resolve_sync_conflict(
    'a2000000-0000-0000-0000-000000000001',
    'categories',
    '2daf63af-1d0b-539b-be96-174948bb8ed0',
    2,
    'a5000000-0000-0000-0000-000000000003',
    'keepDevice',
    (select to_jsonb(category) || '{"name":"Conflict overwrite"}'::jsonb
     from public.categories category
     where id = '2daf63af-1d0b-539b-be96-174948bb8ed0')
  )->>'status',
  'validationError',
  'conflict-resolution path rejects canonical mutation'
);

set local role postgres;
select set_config('app.initial_sync_mode', 'on', true);
select throws_ok(
  $$select public.apply_initial_snapshot_row(
      'categories',
      jsonb_build_object(
        'id', public.system_tithe_category_id(
          'b2000000-0000-0000-0000-000000000001'
        ),
        'book_id', 'b2000000-0000-0000-0000-000000000001',
        'name', 'Initial overwrite',
        'category_type', 'expense',
        'created_at', now(),
        'updated_at', now(),
        'version', 1,
        'device_id', 'old-initial-upload'
      )
    )$$,
  '23514',
  'System Tithe category must use canonical name, expense type, and live state',
  'initial-upload apply path rejects malformed canonical category'
);
select set_config('app.initial_sync_mode', 'off', true);
select is(
  (select row(name, category_type, deleted_at is null)::text
   from public.categories
   where id = '2daf63af-1d0b-539b-be96-174948bb8ed0'),
  '(Tithe,expense,t)',
  'failed direct and RPC mutations leave canonical shape unchanged'
);
select is(
  (select count(*) from public.processed_sync_operations
   where operation_id in (
     'a5000000-0000-0000-0000-000000000001',
     'a5000000-0000-0000-0000-000000000002',
     'a5000000-0000-0000-0000-000000000003',
     'a5000000-0000-0000-0000-000000000004',
     'a5000000-0000-0000-0000-000000000005'
   )),
  0::bigint,
  'rejected sync and conflict mutations create no processed operation'
);

select * from finish();
rollback;
