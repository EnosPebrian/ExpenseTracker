alter table public.books
  add column if not exists device_id text not null default 'remote';

create table public.household_members (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  display_name text not null,
  role text not null check (role in ('owner', 'member')),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null
);

create table public.processed_sync_operations (
  operation_id uuid primary key,
  book_id uuid not null references public.books(id),
  entity_type text not null,
  entity_id uuid not null,
  result_status text not null,
  server_version bigint,
  server_sequence bigint,
  processed_at timestamptz not null default now()
);

create index processed_sync_operations_book
  on public.processed_sync_operations(book_id, processed_at);

create trigger prevent_household_members_book_move
before update on public.household_members for each row
execute function public.prevent_book_id_change();

create or replace function public.capture_book_change()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    insert into public.app_changes(book_id, entity_table, entity_id, operation)
    values (old.id, 'books', old.id, lower(tg_op));
    return old;
  end if;
  insert into public.app_changes(book_id, entity_table, entity_id, operation)
  values (new.id, 'books', new.id, lower(tg_op));
  return new;
end;
$$;

create trigger capture_books_change
after insert or update or delete on public.books for each row
execute function public.capture_book_change();

create trigger capture_household_members_change
after insert or update or delete on public.household_members for each row
execute function public.capture_financial_change();

create or replace function public.sync_entity_snapshot(
  p_entity_type text,
  p_entity_id uuid
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare result jsonb;
begin
  if p_entity_type not in (
    'books', 'household_members', 'accounts', 'categories', 'projects',
    'transactions', 'asset_definitions'
  ) then
    raise exception 'Unsupported sync entity';
  end if;
  execute format(
    'select to_jsonb(value) from public.%I value where id = $1',
    p_entity_type
  ) into result using p_entity_id;
  return result;
end;
$$;

create or replace function public.apply_sync_operation(
  p_entity_type text,
  p_operation_type text,
  p_payload jsonb,
  p_base_version bigint,
  p_device_id text
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  entity_id uuid := (p_payload->>'id')::uuid;
  existing jsonb;
  normalized jsonb;
  columns text;
begin
  existing := public.sync_entity_snapshot(p_entity_type, entity_id);
  if p_operation_type = 'delete' then
    if existing is null then raise exception 'Delete target does not exist'; end if;
    execute format(
      'update public.%I set deleted_at = now(), updated_at = now(), '
      'version = $1, device_id = $2 where id = $3',
      p_entity_type
    ) using p_base_version + 1, p_device_id, entity_id;
    return public.sync_entity_snapshot(p_entity_type, entity_id);
  end if;

  normalized := p_payload || jsonb_build_object(
    'version', p_base_version + 1,
    'device_id', p_device_id,
    'updated_at', now()
  );

  if p_entity_type = 'books' then
    if existing is null then
      normalized := normalized || jsonb_build_object(
        'created_by_user_id', auth.uid(),
        'created_at', coalesce(normalized->'created_at', to_jsonb(now()))
      );
      insert into public.books
      select value.* from jsonb_populate_record(null::public.books, normalized) value;
    else
      update public.books set
        name = normalized->>'name',
        base_currency_code = normalized->>'base_currency_code',
        updated_at = (normalized->>'updated_at')::timestamptz,
        deleted_at = (normalized->>'deleted_at')::timestamptz,
        version = (normalized->>'version')::bigint,
        device_id = normalized->>'device_id'
      where id = entity_id;
    end if;
    return public.sync_entity_snapshot(p_entity_type, entity_id);
  end if;

 case p_entity_type
  when 'household_members' then
    columns := 'id,book_id,display_name,role,created_at,updated_at,deleted_at,version,device_id';

  when 'accounts' then
    columns := 'id,book_id,owner_member_id,name,account_type,currency_code,opening_balance,opening_balance_date,created_at,updated_at,deleted_at,version,device_id';

  when 'categories' then
    columns := 'id,book_id,name,category_type,created_at,updated_at,deleted_at,version,device_id';

  when 'projects' then
    columns := 'id,book_id,name,status,created_at,updated_at,deleted_at,version,device_id';

  when 'asset_definitions' then
    columns := 'id,book_id,display_name,asset_kind,symbol,provider_code,provider_symbol,exchange_code,currency_code,unit,lot_size,online_pricing_enabled,created_at,updated_at,deleted_at,version,device_id';

  when 'transactions' then
    columns := 'id,book_id,entered_by_member_id,project_id,title,category,account,transaction_date,amount,transaction_type,quantity,unit,unit_price,asset_definition_id,asset_name,asset_symbol,asset_action,fee_amount,fee_treatment,related_transaction_id,relation_type,market_reference_unit_price,market_reference_currency_code,market_reference_unit,market_reference_source,market_reference_quoted_at,created_at,updated_at,deleted_at,version,device_id';

  else
    raise exception 'Unsupported sync entity: %', p_entity_type;
end case;

  if existing is null then
    execute format(
      'insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
      p_entity_type, columns, columns, p_entity_type
    ) using normalized;
  else
    execute format(
      'update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) where id = $2',
      p_entity_type, columns, columns, p_entity_type
    ) using normalized, entity_id;
  end if;
  return public.sync_entity_snapshot(p_entity_type, entity_id);
end;
$$;

create or replace function public.push_book_changes(
  p_book_id uuid,
  p_operations jsonb
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  operation jsonb;
  current_operation_id uuid;
  entity_type text;
  op_entity_id uuid;
  operation_type text;
  base_version bigint;
  payload jsonb;
  current_snapshot jsonb;
  applied_snapshot jsonb;
  processed public.processed_sync_operations;
  sequence_value bigint;
  allowed_fields text[];
  results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or not public.is_active_book_member(p_book_id) then
    raise exception 'Active book membership required';
  end if;
  if jsonb_typeof(p_operations) <> 'array' or jsonb_array_length(p_operations) > 50 then
    raise exception 'A batch must contain at most 50 operations';
  end if;

  for operation in select value from jsonb_array_elements(p_operations) loop
    begin
      current_operation_id := (operation->>'operationId')::uuid;
      entity_type := operation->>'entityType';
      op_entity_id := (operation->>'entityId')::uuid;
      operation_type := operation->>'operationType';
      base_version := (operation->>'baseVersion')::bigint;
      payload := operation->'payload';

      if entity_type not in (
        'books', 'household_members', 'accounts', 'categories', 'projects',
        'transactions', 'asset_definitions'
      ) or operation_type not in ('upsert', 'delete') or base_version < 0 then
        raise exception 'Invalid sync operation';
      end if;

      select * into processed from public.processed_sync_operations
        where processed_sync_operations.operation_id = current_operation_id;
      if processed.operation_id is not null then
        if processed.book_id <> p_book_id or
           processed.entity_type <> entity_type or
           processed.entity_id <> op_entity_id then
          raise exception 'Operation identity mismatch';
        end if;
        results := results || jsonb_build_array(jsonb_build_object(
          'operation_id', current_operation_id,
          'entity_type', processed.entity_type,
          'status', case when processed.result_status = 'applied'
            then 'already_applied' else processed.result_status end,
          'server_version', processed.server_version,
          'server_sequence', processed.server_sequence,
          'server_payload', public.sync_entity_snapshot(
            processed.entity_type, processed.entity_id
          )
        ));
        continue;
      end if;

      if payload is null or (payload->>'id')::uuid <> op_entity_id then
        raise exception 'Payload identity mismatch';
      end if;
      if (entity_type = 'books' and op_entity_id <> p_book_id) or
         (entity_type <> 'books' and (payload->>'book_id')::uuid <> p_book_id) then
        raise exception 'Payload book mismatch';
      end if;
      allowed_fields := case entity_type
        when 'books' then array[
          'id','name','base_currency_code','created_at','updated_at',
          'deleted_at','version','device_id'
        ]
        when 'household_members' then array[
          'id','book_id','display_name','role','created_at','updated_at',
          'deleted_at','version','device_id'
        ]
        when 'accounts' then array[
          'id','book_id','owner_member_id','name','account_type','currency_code',
          'opening_balance','opening_balance_date','created_at','updated_at',
          'deleted_at','version','device_id'
        ]
        when 'categories' then array[
          'id','book_id','name','category_type','created_at','updated_at',
          'deleted_at','version','device_id'
        ]
        when 'projects' then array[
          'id','book_id','name','status','created_at','updated_at','deleted_at',
          'version','device_id'
        ]
        when 'asset_definitions' then array[
          'id','book_id','display_name','asset_kind','symbol','provider_code',
          'provider_symbol','exchange_code','currency_code','unit','lot_size',
          'online_pricing_enabled','created_at','updated_at','deleted_at',
          'version','device_id'
        ]
        when 'transactions' then array[
          'id','book_id','entered_by_member_id','project_id','title','category',
          'account','transaction_date','amount','transaction_type','quantity',
          'unit','unit_price','asset_definition_id','asset_name','asset_symbol',
          'asset_action','fee_amount','fee_treatment','related_transaction_id',
          'relation_type','market_reference_unit_price',
          'market_reference_currency_code','market_reference_unit',
          'market_reference_source','market_reference_quoted_at','created_at',
          'updated_at','deleted_at','version','device_id'
        ]
      end;
      if exists (
        select 1 from jsonb_object_keys(payload) key
        where not (key = any(allowed_fields))
      ) then
        raise exception 'Payload contains unsupported fields';
      end if;

      current_snapshot := public.sync_entity_snapshot(entity_type, op_entity_id);
      if coalesce((current_snapshot->>'version')::bigint, 0) <> base_version then
        insert into public.processed_sync_operations(
          operation_id, book_id, entity_type, entity_id, result_status,
          server_version
        ) values (
          current_operation_id, p_book_id, entity_type, op_entity_id, 'version_conflict',
          coalesce((current_snapshot->>'version')::bigint, 0)
        );
        results := results || jsonb_build_array(jsonb_build_object(
          'operation_id', current_operation_id,
          'entity_type', entity_type,
          'status', 'version_conflict',
          'server_version', coalesce((current_snapshot->>'version')::bigint, 0),
          'server_payload', current_snapshot
        ));
        continue;
      end if;

      applied_snapshot := public.apply_sync_operation(
        entity_type, operation_type, payload, base_version,
        coalesce(operation->>'deviceId', 'unknown-device')
      );
      select max(sequence) into sequence_value from public.app_changes
        where book_id = p_book_id and entity_table = entity_type
          and app_changes.entity_id = op_entity_id;
      insert into public.processed_sync_operations(
        operation_id, book_id, entity_type, entity_id, result_status,
        server_version, server_sequence
      ) values (
        current_operation_id, p_book_id, entity_type, op_entity_id, 'applied',
        (applied_snapshot->>'version')::bigint, sequence_value
      );
      results := results || jsonb_build_array(jsonb_build_object(
        'operation_id', current_operation_id,
        'entity_type', entity_type,
        'status', 'applied',
        'server_version', (applied_snapshot->>'version')::bigint,
        'server_sequence', sequence_value,
        'server_payload', applied_snapshot
      ));
    exception when others then
      results := results || jsonb_build_array(jsonb_build_object(
        'operation_id', operation->>'operationId',
        'entity_type', operation->>'entityType',
        'status', 'validation_error',
        'error_code', 'invalid_operation'
      ));
    end;
  end loop;
  return results;
end;
$$;

create or replace function public.pull_book_changes(
  p_book_id uuid,
  p_after_sequence bigint default 0,
  p_limit integer default 100
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  change_row public.app_changes;
  snapshot jsonb;
  changes jsonb := '[]'::jsonb;
  final_sequence bigint := p_after_sequence;
  safe_limit integer := greatest(1, least(p_limit, 200));
begin
  if auth.uid() is null or not public.is_active_book_member(p_book_id) then
    raise exception 'Active book membership required';
  end if;
  for change_row in
    select * from public.app_changes
    where book_id = p_book_id and sequence > p_after_sequence
    order by sequence asc limit safe_limit
  loop
    snapshot := public.sync_entity_snapshot(
      change_row.entity_table, change_row.entity_id
    );
    changes := changes || jsonb_build_array(jsonb_build_object(
      'sequence', change_row.sequence,
      'entity_type', change_row.entity_table,
      'entity_id', change_row.entity_id,
      'server_version', coalesce((snapshot->>'version')::bigint, 0),
      'operation', case when snapshot->>'deleted_at' is not null
        then 'delete' else 'upsert' end,
      'snapshot', snapshot
    ));
    final_sequence := change_row.sequence;
  end loop;
  return jsonb_build_object(
    'changes', changes,
    'final_sequence', final_sequence
  );
end;
$$;

alter table public.household_members enable row level security;
alter table public.processed_sync_operations enable row level security;

create policy household_members_member_select on public.household_members
  for select to authenticated using (public.is_active_book_member(book_id));
create policy household_members_member_insert on public.household_members
  for insert to authenticated with check (public.is_active_book_member(book_id));
create policy household_members_member_update on public.household_members
  for update to authenticated using (public.is_active_book_member(book_id))
  with check (public.is_active_book_member(book_id));
create policy processed_operations_member_select
  on public.processed_sync_operations for select to authenticated
  using (public.is_active_book_member(book_id));

revoke all on public.household_members, public.processed_sync_operations from anon;
grant select, insert, update on public.household_members to authenticated;
grant select on public.processed_sync_operations to authenticated;

revoke execute on function public.sync_entity_snapshot(text,uuid)
  from public, anon;
revoke execute on function public.apply_sync_operation(text,text,jsonb,bigint,text)
  from public, anon;
revoke execute on function public.push_book_changes(uuid,jsonb)
  from public, anon;
revoke execute on function public.pull_book_changes(uuid,bigint,integer)
  from public, anon;
grant execute on function public.push_book_changes(uuid,jsonb)
  to authenticated;
grant execute on function public.pull_book_changes(uuid,bigint,integer)
  to authenticated;
