create extension if not exists pgcrypto;

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.books (
  id uuid primary key,
  name text not null check (length(trim(name)) > 0),
  base_currency_code text not null default 'IDR'
    check (base_currency_code = upper(base_currency_code)),
  created_by_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1 check (version > 0)
);

create table public.book_memberships (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id),
  user_id uuid not null references auth.users(id),
  household_member_id uuid,
  role text not null check (role in ('owner', 'member')),
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index book_memberships_one_active_user_book
  on public.book_memberships(book_id, user_id) where status = 'active';

create table public.book_invitations (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id),
  email_normalized text not null
    check (email_normalized = lower(trim(email_normalized))),
  household_member_id uuid,
  role text not null default 'member' check (role in ('owner', 'member')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  invited_by_user_id uuid not null references auth.users(id),
  accepted_by_user_id uuid references auth.users(id),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index book_invitations_one_pending_email_book
  on public.book_invitations(book_id, email_normalized)
  where status = 'pending';

create table public.accounts (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  owner_member_id uuid,
  name text not null,
  account_type text not null,
  currency_code text not null,
  opening_balance bigint not null default 0,
  opening_balance_date timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null,
  device_id text not null
);

create table public.categories (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  name text not null,
  category_type text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null,
  device_id text not null
);

create table public.projects (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  name text not null,
  status text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null,
  device_id text not null
);

create table public.asset_definitions (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  display_name text not null,
  asset_kind text not null,
  symbol text,
  provider_code text,
  provider_symbol text,
  exchange_code text,
  currency_code text not null,
  unit text not null,
  lot_size integer not null default 1,
  online_pricing_enabled boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null,
  device_id text not null
);

create table public.transactions (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  entered_by_member_id uuid,
  project_id uuid,
  title text not null,
  category text not null,
  account text not null,
  transaction_date timestamptz not null,
  amount bigint not null,
  transaction_type text not null,
  quantity double precision,
  unit text,
  unit_price bigint,
  asset_definition_id uuid,
  asset_name text,
  asset_symbol text,
  asset_action text,
  fee_amount bigint not null default 0,
  fee_treatment text not null default 'none',
  related_transaction_id uuid,
  relation_type text not null default 'none',
  market_reference_unit_price bigint,
  market_reference_currency_code text,
  market_reference_unit text,
  market_reference_source text,
  market_reference_quoted_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null,
  device_id text not null
);

create table public.app_changes (
  sequence bigint generated always as identity primary key,
  book_id uuid not null references public.books(id),
  entity_table text not null,
  entity_id uuid not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  changed_at timestamptz not null default now()
);

create or replace function public.is_active_book_member(p_book_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.book_memberships m
    where m.book_id = p_book_id and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

create or replace function public.is_active_book_owner(p_book_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.book_memberships m
    where m.book_id = p_book_id and m.user_id = auth.uid()
      and m.status = 'active' and m.role = 'owner'
  );
$$;

create or replace function public.protect_final_owner()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if old.status = 'active' and old.role = 'owner'
     and (tg_op = 'DELETE' or new.status <> 'active' or new.role <> 'owner')
     and not exists (
       select 1 from public.book_memberships m
       where m.book_id = old.book_id and m.id <> old.id
         and m.status = 'active' and m.role = 'owner'
     ) then
    raise exception 'A financial book must keep an active owner';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger protect_final_owner_before_update
before update or delete on public.book_memberships
for each row execute function public.protect_final_owner();

create or replace function public.prevent_book_id_change()
returns trigger language plpgsql as $$
begin
  if new.book_id <> old.book_id then
    raise exception 'book_id cannot be changed';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_book_identity_change()
returns trigger language plpgsql as $$
begin
  if new.id <> old.id or new.created_by_user_id <> old.created_by_user_id then
    raise exception 'Book identity cannot be changed';
  end if;
  return new;
end;
$$;

create trigger prevent_book_identity_change_before_update
before update on public.books for each row
execute function public.prevent_book_identity_change();

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'accounts', 'categories', 'projects', 'transactions', 'asset_definitions'
  ] loop
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.prevent_book_id_change()',
      'prevent_' || table_name || '_book_move', table_name
    );
  end loop;
end $$;

create or replace function public.capture_financial_change()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    insert into public.app_changes(book_id, entity_table, entity_id, operation)
    values (old.book_id, tg_table_name, old.id, lower(tg_op));
    return old;
  end if;
  insert into public.app_changes(book_id, entity_table, entity_id, operation)
  values (new.book_id, tg_table_name, new.id, lower(tg_op));
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'accounts', 'categories', 'projects', 'transactions', 'asset_definitions'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete '
      'on public.%I for each row execute function public.capture_financial_change()',
      'capture_' || table_name || '_change', table_name
    );
  end loop;
end $$;

create or replace function public.link_local_household(
  p_book_id uuid,
  p_book_name text,
  p_base_currency_code text,
  p_household_member_id uuid,
  p_member_display_name text
) returns jsonb language plpgsql security definer
set search_path = public, auth, pg_temp as $$
declare
  caller uuid := auth.uid();
  existing_creator uuid;
  membership_row public.book_memberships;
  linked_at timestamptz := now();
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select created_by_user_id into existing_creator from public.books
    where id = p_book_id for update;
  if existing_creator is not null and existing_creator <> caller
     and not public.is_active_book_owner(p_book_id) then
    raise exception 'This financial book already belongs to another owner';
  end if;

  insert into public.user_profiles(user_id, display_name)
  values (caller, trim(p_member_display_name))
  on conflict (user_id) do update set
    display_name = excluded.display_name, updated_at = now();
  insert into public.books(
    id, name, base_currency_code, created_by_user_id, version
  ) values (
    p_book_id, trim(p_book_name), upper(trim(p_base_currency_code)), caller, 1
  ) on conflict (id) do nothing;

  select * into membership_row from public.book_memberships
    where book_id = p_book_id and user_id = caller and status = 'active';
  if membership_row.id is null then
    insert into public.book_memberships(
      book_id, user_id, household_member_id, role, status
    ) values (
      p_book_id, caller, p_household_member_id, 'owner', 'active'
    ) returning * into membership_row;
  elsif membership_row.role <> 'owner' then
    raise exception 'An existing non-owner membership cannot claim ownership';
  elsif membership_row.household_member_id is null then
    update public.book_memberships set
      household_member_id = p_household_member_id,
      updated_at = now()
      where id = membership_row.id
      returning * into membership_row;
  end if;

  return jsonb_build_object(
    'book_id', p_book_id,
    'membership_id', membership_row.id,
    'user_id', caller,
    'household_member_id', membership_row.household_member_id,
    'linked_at', linked_at
  );
end;
$$;

create or replace function public.create_book_invitation(
  p_book_id uuid,
  p_email text,
  p_household_member_id uuid default null,
  p_role text default 'member'
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  caller uuid := auth.uid();
  normalized_email text := lower(trim(p_email));
  invitation_row public.book_invitations;
begin
  if caller is null or not public.is_active_book_owner(p_book_id) then
    raise exception 'Active owner membership required';
  end if;
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'A valid email is required';
  end if;
  if p_role not in ('owner', 'member') then raise exception 'Invalid role'; end if;

  select * into invitation_row from public.book_invitations
    where book_id = p_book_id and email_normalized = normalized_email
      and status = 'pending' and expires_at > now()
    for update;
  if invitation_row.id is null then
    update public.book_invitations set status = 'expired', updated_at = now()
      where book_id = p_book_id and email_normalized = normalized_email
        and status = 'pending' and expires_at <= now();
    insert into public.book_invitations(
      book_id, email_normalized, household_member_id, role, status,
      invited_by_user_id, expires_at
    ) values (
      p_book_id, normalized_email, p_household_member_id, p_role, 'pending',
      caller, now() + interval '7 days'
    ) returning * into invitation_row;
  end if;
  return to_jsonb(invitation_row) - 'invited_by_user_id' - 'accepted_by_user_id';
end;
$$;

create or replace function public.list_my_pending_invitations()
returns setof public.book_invitations language sql stable security definer
set search_path = public, auth, pg_temp as $$
  select invitation.* from public.book_invitations invitation
  join auth.users account on account.id = auth.uid()
  where invitation.status = 'pending'
    and invitation.expires_at > now()
    and account.email_confirmed_at is not null
    and invitation.email_normalized = lower(account.email);
$$;

create or replace function public.accept_book_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, auth, pg_temp as $$
declare
  caller uuid := auth.uid();
  caller_email text;
  invitation_row public.book_invitations;
  membership_row public.book_memberships;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select lower(email) into caller_email from auth.users
    where id = caller and email_confirmed_at is not null;
  if caller_email is null then raise exception 'Verified email required'; end if;

  select * into invitation_row from public.book_invitations
    where id = p_invitation_id for update;
  if invitation_row.id is null or invitation_row.email_normalized <> caller_email then
    raise exception 'Invitation not available for this user';
  end if;

  select * into membership_row from public.book_memberships
    where book_id = invitation_row.book_id and user_id = caller
      and status = 'active';
  if invitation_row.status = 'accepted'
     and invitation_row.accepted_by_user_id = caller
     and membership_row.id is not null then
    return to_jsonb(membership_row);
  end if;
  if invitation_row.status <> 'pending' or invitation_row.expires_at <= now() then
    raise exception 'Invitation is expired, revoked, or already accepted';
  end if;

  if membership_row.id is null then
    insert into public.book_memberships(
      book_id, user_id, household_member_id, role, status
    ) values (
      invitation_row.book_id, caller, invitation_row.household_member_id,
      invitation_row.role, 'active'
    ) returning * into membership_row;
  elsif membership_row.household_member_id is null
        and invitation_row.household_member_id is not null then
    update public.book_memberships set
      household_member_id = invitation_row.household_member_id,
      updated_at = now()
      where id = membership_row.id
      returning * into membership_row;
  end if;
  update public.book_invitations set
    status = 'accepted', accepted_by_user_id = caller, updated_at = now()
    where id = invitation_row.id;
  return to_jsonb(membership_row);
end;
$$;

alter table public.user_profiles enable row level security;
alter table public.books enable row level security;
alter table public.book_memberships enable row level security;
alter table public.book_invitations enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.projects enable row level security;
alter table public.transactions enable row level security;
alter table public.asset_definitions enable row level security;
alter table public.app_changes enable row level security;

create policy profiles_self_select on public.user_profiles for select
  to authenticated using (user_id = auth.uid());
create policy profiles_self_update on public.user_profiles for update
  to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy books_member_select on public.books for select
  to authenticated using (public.is_active_book_member(id));
create policy books_owner_update on public.books for update
  to authenticated using (public.is_active_book_owner(id))
  with check (public.is_active_book_owner(id));
create policy memberships_book_select on public.book_memberships for select
  to authenticated using (public.is_active_book_member(book_id));
create policy memberships_owner_manage on public.book_memberships for all
  to authenticated using (public.is_active_book_owner(book_id))
  with check (public.is_active_book_owner(book_id));
create policy invitations_owner_manage on public.book_invitations for all
  to authenticated using (public.is_active_book_owner(book_id))
  with check (public.is_active_book_owner(book_id));

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'accounts', 'categories', 'projects', 'transactions', 'asset_definitions'
  ] loop
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.is_active_book_member(book_id))',
      table_name || '_member_select', table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (public.is_active_book_member(book_id))',
      table_name || '_member_insert', table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.is_active_book_member(book_id)) '
      'with check (public.is_active_book_member(book_id))',
      table_name || '_member_update', table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (public.is_active_book_member(book_id))',
      table_name || '_member_delete', table_name
    );
  end loop;
end $$;

create policy changes_member_select on public.app_changes for select
  to authenticated using (public.is_active_book_member(book_id));

revoke all on all tables in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant usage on schema public to authenticated;
grant select, update on public.user_profiles to authenticated;
grant select, update on public.books to authenticated;
grant select, insert, update on public.book_memberships to authenticated;
grant select, insert, update on public.book_invitations to authenticated;
grant select, insert, update, delete on public.accounts, public.categories,
  public.projects, public.transactions, public.asset_definitions to authenticated;
grant select on public.app_changes to authenticated;
grant execute on function public.is_active_book_member(uuid) to authenticated;
grant execute on function public.is_active_book_owner(uuid) to authenticated;
grant execute on function public.link_local_household(uuid,text,text,uuid,text)
  to authenticated;
grant execute on function public.create_book_invitation(uuid,text,uuid,text)
  to authenticated;
grant execute on function public.list_my_pending_invitations() to authenticated;
grant execute on function public.accept_book_invitation(uuid) to authenticated;
