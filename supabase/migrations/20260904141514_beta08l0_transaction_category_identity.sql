-- BETA-08L0: additive category identity; existing name remains a snapshot.
alter table public.transactions add column category_id uuid
  references public.categories(id);
create index transactions_category_id on public.transactions(category_id);

create function public.legacy_transaction_category_id(p_book_id uuid, p_type text, p_name text)
returns uuid language sql stable security invoker set search_path = '' as $$
  select case when count(*) = 1 then min(c.id::text)::uuid else null end
  from public.categories c
  where c.book_id = p_book_id and c.category_type = p_type
    and p_type in ('expense','income')
    and lower(trim(c.name)) = lower(trim(p_name));
$$;
revoke all on function public.legacy_transaction_category_id(uuid,text,text)
  from public, anon, authenticated;

-- Run under the existing migration-only initial-sync gate; preserve lifecycle,
-- timestamps and versions. Existing capture trigger publishes changed rows.
do $$
declare previous_mode text := current_setting('app.initial_sync_mode', true);
begin
  perform set_config('app.initial_sync_mode', 'on', true);
  update public.transactions t
  set category_id = public.legacy_transaction_category_id(t.book_id,t.transaction_type,t.category)
  where t.category_id is null
    and public.legacy_transaction_category_id(t.book_id,t.transaction_type,t.category) is not null;
  perform set_config('app.initial_sync_mode', coalesce(previous_mode,'off'), true);
end $$;

create function public.validate_transaction_category_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.category_id is not null and not exists (
    select 1 from public.categories c where c.id = new.category_id
      and c.book_id = new.book_id and c.category_type = new.transaction_type
  ) then raise exception 'Transaction category must belong to the same household and type.'; end if;
  return new;
end $$;
revoke all on function public.validate_transaction_category_identity()
  from public, anon, authenticated;
create trigger validate_transaction_category_identity
before insert or update on public.transactions
for each row execute function public.validate_transaction_category_identity();

-- Patch the existing RPC definitions in place, retaining their grants and all
-- prior milestones. No alternative synchronization protocol is introduced.
do $patch$
declare signature regprocedure;
declare definition text;
declare updated text;
begin
  foreach signature in array array[
    'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,
    'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure
  ] loop
    definition := pg_get_functiondef(signature);
    updated := replace(definition, 'project_id,title,category,account',
      'project_id,title,category,category_id,account');
    if updated = definition then raise exception 'Category column patch missing: %', signature; end if;
    execute updated;
  end loop;
  foreach signature in array array[
    'public.push_book_changes(uuid,jsonb)'::regprocedure,
    'public.initial_sync_allowed_fields(text)'::regprocedure
  ] loop
    definition := pg_get_functiondef(signature);
    updated := replace(definition, '''project_id'',''title'',''category'',',
      '''project_id'',''title'',''category'',''category_id'',');
    if updated = definition then raise exception 'Category payload patch missing: %', signature; end if;
    execute updated;
  end loop;
  signature := 'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure;
  definition := pg_get_functiondef(signature);
  updated := replace(definition, 'if p_entity_type = ''books'' then', $body$
  if p_entity_type = 'transactions' and not (p_payload ? 'category_id') then
    normalized := normalized || jsonb_build_object('category_id',
      case when existing is not null
        and p_payload->>'category' is not distinct from existing->>'category'
        and p_payload->>'transaction_type' is not distinct from existing->>'transaction_type'
      then existing->'category_id' else 'null'::jsonb end);
  end if;
  if p_entity_type = 'books' then$body$);
  if updated = definition then raise exception 'Legacy category patch missing'; end if;
  execute updated;
end $patch$;
