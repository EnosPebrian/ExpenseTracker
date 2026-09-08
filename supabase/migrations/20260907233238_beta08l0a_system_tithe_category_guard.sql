create or replace function public.system_tithe_category_id(p_book_id uuid)
returns uuid
language sql
immutable
strict
parallel safe
security invoker
set search_path = ''
as $$
  select extensions.uuid_generate_v5(
    p_book_id,
    'system-category:tithe'
  );
$$;

comment on function public.system_tithe_category_id(uuid) is
  'Internal canonical identity: UUIDv5(book_id, system-category:tithe).';

revoke execute on function public.system_tithe_category_id(uuid)
  from public, anon, authenticated;

create or replace function public.guard_system_tithe_category()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  old_is_system_tithe boolean := false;
  new_is_system_tithe boolean := false;
begin
  if tg_op <> 'INSERT' then
    old_is_system_tithe := old.id = extensions.uuid_generate_v5(
      old.book_id,
      'system-category:tithe'
    );
  end if;

  if tg_op <> 'DELETE' then
    new_is_system_tithe := new.id = extensions.uuid_generate_v5(
      new.book_id,
      'system-category:tithe'
    );
  end if;

  if tg_op = 'INSERT' then
    if new_is_system_tithe and (
      new.name is distinct from 'Tithe'
      or new.category_type is distinct from 'expense'
      or new.deleted_at is not null
    ) then
      raise exception using
        errcode = '23514',
        message = 'System Tithe category must use canonical name, expense type, and live state';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old_is_system_tithe then
      raise exception using
        errcode = '23514',
        message = 'System Tithe category cannot be deleted';
    end if;
    return old;
  end if;

  if old_is_system_tithe then
    if new.id is distinct from old.id
      or new.book_id is distinct from old.book_id
      or new.name is distinct from 'Tithe'
      or new.category_type is distinct from 'expense'
      or new.deleted_at is not null then
      raise exception using
        errcode = '23514',
        message = 'System Tithe category identity and semantics are immutable';
    end if;
  elsif new_is_system_tithe then
    raise exception using
      errcode = '23514',
      message = 'Ordinary category cannot become System Tithe';
  end if;

  return new;
end;
$$;

comment on function public.guard_system_tithe_category() is
  'Invoker trigger enforcing the canonical System Tithe category invariant.';

revoke execute on function public.guard_system_tithe_category()
  from public, anon, authenticated;

create trigger guard_system_tithe_category_before_write
before insert or update or delete on public.categories
for each row execute function public.guard_system_tithe_category();
