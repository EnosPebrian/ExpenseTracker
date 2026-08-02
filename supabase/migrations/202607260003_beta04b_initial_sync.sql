create table public.book_sync_initializations (
  book_id uuid primary key references public.books(id),
  status text not null check (status in ('uploading', 'complete')),
  upload_session_id uuid,
  manifest jsonb not null default '{}'::jsonb,
  snapshot_sequence bigint not null default 0,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.initial_sync_sessions (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id),
  user_id uuid not null references auth.users(id),
  direction text not null check (direction in ('upload', 'download')),
  status text not null default 'active'
    check (status in ('active', 'complete', 'cancelled', 'failed')),
  manifest jsonb not null default '{}'::jsonb,
  snapshot_sequence bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index initial_sync_one_active_upload
  on public.initial_sync_sessions(book_id)
  where direction = 'upload' and status = 'active';
create unique index initial_sync_one_active_download_per_user
  on public.initial_sync_sessions(book_id, user_id)
  where direction = 'download' and status = 'active';

create table public.initial_sync_items (
  session_id uuid not null references public.initial_sync_sessions(id)
    on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  primary key(session_id, entity_type, entity_id)
);

create index initial_sync_items_page
  on public.initial_sync_items(session_id, entity_type, entity_id);

create or replace function public.initial_sync_allowed_fields(p_entity_type text)
returns text[] language sql immutable set search_path = public, pg_temp as $$
  select case p_entity_type
    when 'books' then array[
      'id','name','base_currency_code','created_at','updated_at','deleted_at',
      'version','device_id'
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
$$;

create or replace function public.remote_financial_row_count(p_book_id uuid)
returns bigint language sql stable security definer
set search_path = public, pg_temp as $$
  select
    (select count(*) from public.household_members where book_id = p_book_id) +
    (select count(*) from public.accounts where book_id = p_book_id) +
    (select count(*) from public.categories where book_id = p_book_id) +
    (select count(*) from public.projects where book_id = p_book_id) +
    (select count(*) from public.asset_definitions where book_id = p_book_id) +
    (select count(*) from public.transactions where book_id = p_book_id);
$$;

create or replace function public.enforce_initialized_financial_write()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare target_book_id uuid;
begin
  if tg_table_name = 'books' then
    target_book_id := coalesce(new.id, old.id);
  else
    target_book_id := coalesce(new.book_id, old.book_id);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_book_id::text, 0));
  if current_setting('app.initial_sync_mode', true) = 'on' then
    return coalesce(new, old);
  end if;
  if tg_table_name = 'books' and tg_op = 'INSERT' then return new; end if;
  if not exists (
    select 1 from public.book_sync_initializations initialization
    where initialization.book_id = target_book_id
      and initialization.status = 'complete'
  ) then
    raise exception 'Initial synchronization is not complete';
  end if;
  return coalesce(new, old);
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'books','household_members','accounts','categories','projects',
    'asset_definitions','transactions'
  ] loop
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.enforce_initialized_financial_write()',
      'enforce_initial_sync_' || table_name, table_name
    );
  end loop;
end $$;

create or replace function public.initial_sync_manifest(
  p_book_id uuid,
  p_snapshot_sequence bigint,
  p_member_role text,
  p_household_member_id uuid
) returns jsonb language sql stable security definer
set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'book_id', book.id,
    'book_name', book.name,
    'base_currency_code', book.base_currency_code,
    'counts', jsonb_build_object(
      'books', 1,
      'household_members', (select count(*) from public.household_members where book_id = book.id),
      'categories', (select count(*) from public.categories where book_id = book.id),
      'projects', (select count(*) from public.projects where book_id = book.id),
      'accounts', (select count(*) from public.accounts where book_id = book.id),
      'asset_definitions', (select count(*) from public.asset_definitions where book_id = book.id),
      'transactions', (select count(*) from public.transactions where book_id = book.id)
    ),
    'snapshot_sequence', p_snapshot_sequence,
    'member_role', p_member_role,
    'household_member_id', p_household_member_id,
    'remote_initialization_complete', exists(
      select 1 from public.book_sync_initializations initialization
      where initialization.book_id = book.id and initialization.status = 'complete'
    )
  ) from public.books book where book.id = p_book_id;
$$;

create or replace function public.get_initial_sync_status(p_book_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare membership public.book_memberships;
declare sequence_value bigint;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into membership from public.book_memberships
  where book_id = p_book_id and user_id = auth.uid() and status = 'active';
  if membership.id is null then raise exception 'Active book membership required'; end if;
  select coalesce(max(sequence), 0) into sequence_value
  from public.app_changes where book_id = p_book_id;
  return public.initial_sync_manifest(
    p_book_id, sequence_value, membership.role, membership.household_member_id
  ) || jsonb_build_object(
    'remote_record_count', public.remote_financial_row_count(p_book_id)
  );
end;
$$;

create or replace function public.begin_initial_upload(
  p_book_id uuid,
  p_manifest jsonb
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare membership public.book_memberships;
declare session public.initial_sync_sessions;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_book_id::text, 0));
  select * into membership from public.book_memberships
  where book_id = p_book_id and user_id = auth.uid()
    and status = 'active' and role = 'owner';
  if membership.id is null then raise exception 'Active owner membership required'; end if;
  if (p_manifest->>'book_id')::uuid <> p_book_id or
     coalesce((p_manifest->'counts'->>'books')::integer, 0) <> 1 then
    raise exception 'Invalid initial upload manifest';
  end if;
  if exists (
    select 1 from public.book_sync_initializations
    where book_id = p_book_id and status = 'complete'
  ) then raise exception 'Remote household initialization is already complete'; end if;
  if public.remote_financial_row_count(p_book_id) <> 0 then
    raise exception 'Remote household already contains financial records';
  end if;
  select * into session from public.initial_sync_sessions
  where book_id = p_book_id and direction = 'upload' and status = 'active';
  if session.id is null then
    insert into public.initial_sync_sessions(
      book_id, user_id, direction, manifest
    ) values (p_book_id, auth.uid(), 'upload', p_manifest)
    returning * into session;
    insert into public.book_sync_initializations(
      book_id, status, upload_session_id, manifest
    ) values (p_book_id, 'uploading', session.id, p_manifest)
    on conflict(book_id) do update set
      status = 'uploading', upload_session_id = excluded.upload_session_id,
      manifest = excluded.manifest, started_at = now(), completed_at = null;
  elsif session.user_id <> auth.uid() then
    raise exception 'Another owner is initializing this household';
  elsif session.manifest <> p_manifest then
    raise exception 'Initial upload manifest does not match active session';
  end if;
  return jsonb_build_object(
    'session_id', session.id,
    'direction', 'upload',
    'manifest', session.manifest
  );
end;
$$;

create or replace function public.upload_initial_snapshot_batch(
  p_session_id uuid,
  p_entity_type text,
  p_rows jsonb
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare session public.initial_sync_sessions;
declare row_value jsonb;
declare row_entity_id uuid;
declare existing_payload jsonb;
declare allowed_fields text[];
declare received_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into session from public.initial_sync_sessions
  where id = p_session_id and direction = 'upload' and status = 'active';
  if session.id is null or session.user_id <> auth.uid() or
     not public.is_active_book_owner(session.book_id) then
    raise exception 'Active upload session and owner membership required';
  end if;
  if p_entity_type not in (
    'books','household_members','categories','projects','accounts',
    'asset_definitions','transactions'
  ) or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 100 then
    raise exception 'Invalid initial upload batch';
  end if;
  allowed_fields := public.initial_sync_allowed_fields(p_entity_type);
  for row_value in select value from jsonb_array_elements(p_rows) loop
    row_entity_id := (row_value->>'id')::uuid;
    if row_entity_id is null or
       (p_entity_type = 'books' and row_entity_id <> session.book_id) or
       (p_entity_type <> 'books' and
        (row_value->>'book_id')::uuid <> session.book_id) or
       coalesce((row_value->>'version')::bigint, 0) < 1 or
       exists (
         select 1 from jsonb_object_keys(row_value) key
         where not (key = any(allowed_fields))
       ) then raise exception 'Invalid initial snapshot row'; end if;
    if p_entity_type = 'transactions' and row_value->'amount' is null then
      raise exception 'Transaction amount is required';
    end if;
    select payload into existing_payload from public.initial_sync_items
    where session_id = p_session_id and entity_type = p_entity_type
      and initial_sync_items.entity_id = row_entity_id;
    if existing_payload is not null and existing_payload <> row_value then
      raise exception 'Initial snapshot retry payload mismatch';
    end if;
    insert into public.initial_sync_items(
      session_id, entity_type, entity_id, payload
    ) values (p_session_id, p_entity_type, row_entity_id, row_value)
    on conflict(session_id, entity_type, entity_id) do nothing;
  end loop;
  select count(*) into received_count from public.initial_sync_items
  where session_id = p_session_id and entity_type = p_entity_type;
  if received_count > coalesce(
    (session.manifest->'counts'->>p_entity_type)::integer, 0
  ) then
    raise exception 'Initial snapshot exceeds manifest count';
  end if;
  update public.initial_sync_sessions set updated_at = now()
  where id = p_session_id;
  return jsonb_build_object(
    'entity_type', p_entity_type, 'received_count', received_count
  );
end;
$$;

create or replace function public.apply_initial_snapshot_row(
  p_entity_type text,
  p_payload jsonb
) returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare columns text;
declare entity_id uuid := (p_payload->>'id')::uuid;
begin
  if p_entity_type = 'books' then
    update public.books set
      name = p_payload->>'name',
      base_currency_code = p_payload->>'base_currency_code',
      created_at = (p_payload->>'created_at')::timestamptz,
      updated_at = (p_payload->>'updated_at')::timestamptz,
      deleted_at = (p_payload->>'deleted_at')::timestamptz,
      version = (p_payload->>'version')::bigint,
      device_id = p_payload->>'device_id'
    where id = entity_id;
    return;
  end if;
  case p_entity_type
    when 'household_members' then columns := 'id,book_id,display_name,role,created_at,updated_at,deleted_at,version,device_id';
    when 'categories' then columns := 'id,book_id,name,category_type,created_at,updated_at,deleted_at,version,device_id';
    when 'projects' then columns := 'id,book_id,name,status,created_at,updated_at,deleted_at,version,device_id';
    when 'accounts' then columns := 'id,book_id,owner_member_id,name,account_type,currency_code,opening_balance,opening_balance_date,created_at,updated_at,deleted_at,version,device_id';
    when 'asset_definitions' then columns := 'id,book_id,display_name,asset_kind,symbol,provider_code,provider_symbol,exchange_code,currency_code,unit,lot_size,online_pricing_enabled,created_at,updated_at,deleted_at,version,device_id';
    when 'transactions' then columns := 'id,book_id,entered_by_member_id,project_id,title,category,account,transaction_date,amount,transaction_type,quantity,unit,unit_price,asset_definition_id,asset_name,asset_symbol,asset_action,fee_amount,fee_treatment,related_transaction_id,relation_type,market_reference_unit_price,market_reference_currency_code,market_reference_unit,market_reference_source,market_reference_quoted_at,created_at,updated_at,deleted_at,version,device_id';
    else raise exception 'Unsupported initial snapshot entity: %', p_entity_type;
  end case;
  execute format(
    'insert into public.%I (%s) select %s '
    'from jsonb_populate_record(null::public.%I, $1)',
    p_entity_type, columns, columns, p_entity_type
  ) using p_payload;
end;
$$;

create or replace function public.complete_initial_upload(p_session_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare session public.initial_sync_sessions;
declare current_entity_type text;
declare expected_count integer;
declare actual_count integer;
declare item public.initial_sync_items;
declare final_sequence bigint;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into session from public.initial_sync_sessions
  where id = p_session_id and direction = 'upload';
  if session.id is null or session.user_id <> auth.uid() or
     not public.is_active_book_owner(session.book_id) then
    raise exception 'Active owner upload session required';
  end if;
  if session.status = 'complete' then
    return jsonb_build_object(
      'final_sequence', session.snapshot_sequence, 'status', 'complete'
    );
  end if;
  if session.status <> 'active' then raise exception 'Upload session is not active'; end if;
  perform pg_advisory_xact_lock(hashtextextended(session.book_id::text, 0));
  if public.remote_financial_row_count(session.book_id) <> 0 then
    raise exception 'Remote household became occupied';
  end if;
  foreach current_entity_type in array array[
    'books','household_members','categories','projects','accounts',
    'asset_definitions','transactions'
  ] loop
    expected_count := coalesce(
      (session.manifest->'counts'->>current_entity_type)::integer, 0
    );
    select count(*) into actual_count from public.initial_sync_items
    where session_id = p_session_id
      and initial_sync_items.entity_type = current_entity_type;
    if expected_count <> actual_count then
      raise exception 'Initial upload manifest count mismatch for %', current_entity_type;
    end if;
  end loop;
  if exists (
    select 1 from public.initial_sync_items account
    where account.session_id = p_session_id and account.entity_type = 'accounts'
      and account.payload->>'owner_member_id' is not null
      and not exists (
        select 1 from public.initial_sync_items member
        where member.session_id = p_session_id
          and member.entity_type = 'household_members'
          and member.entity_id = (account.payload->>'owner_member_id')::uuid
      )
  ) or exists (
    select 1 from public.initial_sync_items transaction_item
    where transaction_item.session_id = p_session_id
      and transaction_item.entity_type = 'transactions'
      and (
        (transaction_item.payload->>'entered_by_member_id' is not null and
          not exists (select 1 from public.initial_sync_items member
            where member.session_id = p_session_id
              and member.entity_type = 'household_members'
              and member.entity_id =
                (transaction_item.payload->>'entered_by_member_id')::uuid))
        or (transaction_item.payload->>'related_transaction_id' is not null and
          not exists (select 1 from public.initial_sync_items related
            where related.session_id = p_session_id
              and related.entity_type = 'transactions'
              and related.entity_id =
                (transaction_item.payload->>'related_transaction_id')::uuid))
        or (transaction_item.payload->>'project_id' is not null and
          not exists (select 1 from public.initial_sync_items project
            where project.session_id = p_session_id
              and project.entity_type = 'projects'
              and project.entity_id =
                (transaction_item.payload->>'project_id')::uuid))
        or (transaction_item.payload->>'asset_definition_id' is not null and
          transaction_item.payload->>'asset_name' is null and
          not exists (select 1 from public.initial_sync_items definition
            where definition.session_id = p_session_id
              and definition.entity_type = 'asset_definitions'
              and definition.entity_id =
                (transaction_item.payload->>'asset_definition_id')::uuid))
      )
  ) then raise exception 'Initial upload referential integrity failed'; end if;
  perform set_config('app.initial_sync_mode', 'on', true);
  foreach current_entity_type in array array[
    'books','household_members','categories','projects','accounts',
    'asset_definitions','transactions'
  ] loop
    for item in select * from public.initial_sync_items
      where session_id = p_session_id
        and initial_sync_items.entity_type = current_entity_type
      order by entity_id
    loop
      perform public.apply_initial_snapshot_row(current_entity_type, item.payload);
    end loop;
  end loop;
  select coalesce(max(sequence), 0) into final_sequence
  from public.app_changes where book_id = session.book_id;
  update public.initial_sync_sessions set
    status = 'complete', snapshot_sequence = final_sequence,
    completed_at = now(), updated_at = now()
  where id = p_session_id;
  update public.book_sync_initializations set
    status = 'complete', snapshot_sequence = final_sequence,
    completed_at = now()
  where book_id = session.book_id;
  return jsonb_build_object(
    'final_sequence', final_sequence, 'status', 'complete'
  );
end;
$$;

create or replace function public.begin_initial_download(p_book_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare membership public.book_memberships;
declare session public.initial_sync_sessions;
declare sequence_value bigint;
declare manifest_value jsonb;
declare entity_type text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_book_id::text, 0));
  select * into membership from public.book_memberships
  where book_id = p_book_id and user_id = auth.uid() and status = 'active';
  if membership.id is null then raise exception 'Active book membership required'; end if;
  if not exists (
    select 1 from public.book_sync_initializations
    where book_id = p_book_id and status = 'complete'
  ) then raise exception 'Remote household initialization is incomplete'; end if;
  select * into session from public.initial_sync_sessions
  where book_id = p_book_id and user_id = auth.uid()
    and direction = 'download' and status = 'active';
  if session.id is null then
    select coalesce(max(sequence), 0) into sequence_value
    from public.app_changes where book_id = p_book_id;
    manifest_value := public.initial_sync_manifest(
      p_book_id, sequence_value, membership.role,
      membership.household_member_id
    );
    insert into public.initial_sync_sessions(
      book_id, user_id, direction, manifest, snapshot_sequence
    ) values (
      p_book_id, auth.uid(), 'download', manifest_value, sequence_value
    ) returning * into session;
    insert into public.initial_sync_items(session_id, entity_type, entity_id, payload)
      select session.id, 'books', id, to_jsonb(book)
      from public.books book where id = p_book_id;
    foreach entity_type in array array[
      'household_members','categories','projects','accounts',
      'asset_definitions','transactions'
    ] loop
      execute format(
        'insert into public.initial_sync_items('
        'session_id, entity_type, entity_id, payload) '
        'select $1, $2, id, to_jsonb(value) from public.%I value '
        'where book_id = $3', entity_type
      ) using session.id, entity_type, p_book_id;
    end loop;
  end if;
  return jsonb_build_object(
    'session_id', session.id,
    'direction', 'download',
    'manifest', session.manifest
  );
end;
$$;

create or replace function public.pull_initial_snapshot_batch(
  p_session_id uuid,
  p_entity_type text,
  p_after_entity_id uuid default null,
  p_limit integer default 100
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare session public.initial_sync_sessions;
declare rows jsonb;
declare next_cursor uuid;
declare safe_limit integer := greatest(1, least(p_limit, 100));
declare returned_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into session from public.initial_sync_sessions
  where id = p_session_id and direction = 'download' and status = 'active';
  if session.id is null or session.user_id <> auth.uid() or
     not public.is_active_book_member(session.book_id) then
    raise exception 'Active authorized download session required';
  end if;
  if p_entity_type not in (
    'books','household_members','categories','projects','accounts',
    'asset_definitions','transactions'
  ) then raise exception 'Unsupported initial download entity'; end if;
  select coalesce(jsonb_agg(payload order by entity_id), '[]'::jsonb),
    max(entity_id::text)::uuid, count(*)
  into rows, next_cursor, returned_count
  from (
    select entity_id, payload from public.initial_sync_items
    where session_id = p_session_id and entity_type = p_entity_type
      and (p_after_entity_id is null or entity_id > p_after_entity_id)
    order by entity_id limit safe_limit
  ) page;
  return jsonb_build_object(
    'entity_type', p_entity_type,
    'rows', rows,
    'next_cursor', next_cursor,
    'complete', returned_count < safe_limit
  );
end;
$$;

create or replace function public.cancel_initial_sync(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare session public.initial_sync_sessions;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into session from public.initial_sync_sessions
  where id = p_session_id and status = 'active';
  if session.id is null or session.user_id <> auth.uid() or
     not public.is_active_book_member(session.book_id) then
    raise exception 'Active initialization session required';
  end if;
  if session.direction = 'upload' and
     not public.is_active_book_owner(session.book_id) then
    raise exception 'Owner membership required';
  end if;
  update public.initial_sync_sessions set status = 'cancelled', updated_at = now()
  where id = p_session_id;
  delete from public.initial_sync_items where session_id = p_session_id;
  if session.direction = 'upload' then
    delete from public.book_sync_initializations
    where book_id = session.book_id and status = 'uploading'
      and upload_session_id = session.id;
  end if;
end;
$$;

alter table public.book_sync_initializations enable row level security;
alter table public.initial_sync_sessions enable row level security;
alter table public.initial_sync_items enable row level security;

revoke all on public.book_sync_initializations, public.initial_sync_sessions,
  public.initial_sync_items from public, anon, authenticated;

revoke execute on function public.initial_sync_allowed_fields(text)
  from public, anon, authenticated;
revoke execute on function public.remote_financial_row_count(uuid)
  from public, anon, authenticated;
revoke execute on function public.initial_sync_manifest(uuid,bigint,text,uuid)
  from public, anon, authenticated;
revoke execute on function public.apply_initial_snapshot_row(text,jsonb)
  from public, anon, authenticated;
revoke execute on function public.get_initial_sync_status(uuid)
  from public, anon;
revoke execute on function public.begin_initial_upload(uuid,jsonb)
  from public, anon;
revoke execute on function public.upload_initial_snapshot_batch(uuid,text,jsonb)
  from public, anon;
revoke execute on function public.complete_initial_upload(uuid)
  from public, anon;
revoke execute on function public.begin_initial_download(uuid)
  from public, anon;
revoke execute on function public.pull_initial_snapshot_batch(uuid,text,uuid,integer)
  from public, anon;
revoke execute on function public.cancel_initial_sync(uuid)
  from public, anon;

grant execute on function public.get_initial_sync_status(uuid) to authenticated;
grant execute on function public.begin_initial_upload(uuid,jsonb) to authenticated;
grant execute on function public.upload_initial_snapshot_batch(uuid,text,jsonb)
  to authenticated;
grant execute on function public.complete_initial_upload(uuid) to authenticated;
grant execute on function public.begin_initial_download(uuid) to authenticated;
grant execute on function public.pull_initial_snapshot_batch(uuid,text,uuid,integer)
  to authenticated;
grant execute on function public.cancel_initial_sync(uuid) to authenticated;
