begin;
create extension if not exists pgtap;
select plan(19);

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'enos@example.test', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'grace@example.test', now(), now(), now()),
  ('10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'other@example.test', now(), now(), now());

insert into public.user_profiles(user_id, display_name) values
  ('10000000-0000-0000-0000-000000000001', 'Enos'),
  ('10000000-0000-0000-0000-000000000002', 'Grace');
insert into public.books(id, name, base_currency_code, created_by_user_id) values
  ('20000000-0000-0000-0000-000000000001', 'Enos household', 'IDR', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', 'Other household', 'IDR', '10000000-0000-0000-0000-000000000003');
insert into public.book_memberships(id, book_id, user_id, role, status) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'member', 'active'),
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', 'owner', 'active');
insert into public.accounts(id, book_id, name, account_type, currency_code, created_at, updated_at, version, device_id)
values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Cash', 'cash', 'IDR', now(), now(), 1, 'test'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Other cash', 'cash', 'IDR', now(), now(), 1, 'test');

set local role anon;
select throws_ok(
  $$select count(*) from public.books$$,
  '42501', null, 'unauthenticated books denied'
);
select throws_ok(
  $$select count(*) from public.accounts$$,
  '42501', null, 'unauthenticated finance denied'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","email":"grace@example.test"}', true);
select is((select count(*) from public.user_profiles), 1::bigint, 'user reads own profile only');
select is((select count(*) from public.books), 1::bigint, 'member reads own book');
select is((select count(*) from public.accounts), 1::bigint, 'cross-book account read denied');
select lives_ok(
  $$insert into public.categories(id, book_id, name, category_type, created_at, updated_at, version, device_id)
    values ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Food', 'expense', now(), now(), 1, 'test')$$,
  'member writes own-book financial row'
);
select throws_ok(
  $$insert into public.categories(id, book_id, name, category_type, created_at, updated_at, version, device_id)
    values ('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Escape', 'expense', now(), now(), 1, 'test')$$,
  '42501', null, 'cross-book write denied'
);
select throws_ok(
  $$select public.create_book_invitation('20000000-0000-0000-0000-000000000001', 'friend@example.test', null, 'member')$$,
  null, null, 'non-owner cannot invite'
);
select is(
  (with changed as (
    update public.book_memberships set role = 'owner'
      where id = '30000000-0000-0000-0000-000000000002'
      returning 1
  ) select count(*) from changed),
  0::bigint, 'member cannot promote own membership'
);
select throws_ok(
  $$insert into public.book_invitations(
      book_id, email_normalized, role, status, invited_by_user_id, expires_at
    ) values (
      '20000000-0000-0000-0000-000000000001', 'friend@example.test',
      'member', 'pending', '10000000-0000-0000-0000-000000000002', now() + interval '1 day'
    )$$,
  null, null, 'member cannot insert invitation directly'
);

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","email":"enos@example.test"}', true);
select lives_ok(
  $$select public.create_book_invitation('20000000-0000-0000-0000-000000000001', 'grace@example.test', '60000000-0000-0000-0000-000000000001', 'member')$$,
  'owner can invite'
);
select is(
  (select count(*) from public.book_invitations where email_normalized = 'grace@example.test'),
  1::bigint, 'invitation creation is idempotent'
);
select set_config(
  'app.test_invitation_id',
  (select id::text from public.book_invitations where email_normalized = 'grace@example.test'),
  true
);

reset role;
delete from public.book_memberships where id = '30000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","email":"grace@example.test"}', true);
select lives_ok(
  $$select public.accept_book_invitation(current_setting('app.test_invitation_id')::uuid)$$,
  'verified matching invite is accepted'
);
select lives_ok(
  $$select public.accept_book_invitation(current_setting('app.test_invitation_id')::uuid)$$,
  'duplicate acceptance is idempotent'
);

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated","email":"other@example.test"}', true);
select throws_ok(
  $$select public.accept_book_invitation(current_setting('app.test_invitation_id')::uuid)$$,
  null, null, 'invite email mismatch denied'
);

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","email":"enos@example.test"}', true);
select throws_ok(
  $$update public.book_memberships set status = 'revoked'
    where id = '30000000-0000-0000-0000-000000000001'$$,
  null, null, 'final active owner is protected'
);
select throws_ok(
  $$update public.accounts set book_id = '20000000-0000-0000-0000-000000000002'
    where id = '40000000-0000-0000-0000-000000000001'$$,
  null, null, 'financial row book id cannot move'
);

update public.book_invitations set status = 'revoked'
  where email_normalized = 'grace@example.test';
insert into public.book_invitations(
  id, book_id, email_normalized, role, status, invited_by_user_id, expires_at
) values (
  '70000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'grace@example.test', 'member', 'pending',
  '10000000-0000-0000-0000-000000000001', now() - interval '1 hour'
);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","email":"grace@example.test"}', true);
select throws_ok(
  $$select public.accept_book_invitation(current_setting('app.test_invitation_id')::uuid)$$,
  null, null, 'revoked invitation denied'
);
select throws_ok(
  $$select public.accept_book_invitation('70000000-0000-0000-0000-000000000001')$$,
  null, null, 'expired invitation denied'
);

select * from finish();
rollback;
