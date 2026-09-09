-- BETA-08M0: durable, optional user-owned transaction metadata.
alter table public.transactions
  add column note text,
  add column reference text;

alter table public.transactions
  add constraint transactions_note_length check (
    note is null or (char_length(note) <= 4000 and btrim(note) <> '')
  ),
  add constraint transactions_reference_length check (
    reference is null or (
      char_length(reference) <= 256 and
      reference = btrim(reference) and
      reference <> ''
    )
  );

-- Replace the four current sync functions deterministically. Their signatures,
-- execution modes, search paths, and existing ACLs remain unchanged. An omitted
-- legacy metadata property keeps the stored value on update; an explicitly
-- present JSON null clears it.
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

  if p_entity_type = 'transactions' and not (p_payload ? 'category_id') then
    normalized := normalized || jsonb_build_object(
      'category_id',
      case when existing is not null
        and p_payload->>'category' is not distinct from existing->>'category'
        and p_payload->>'transaction_type'
          is not distinct from existing->>'transaction_type'
      then existing->'category_id' else 'null'::jsonb end
    );
  end if;
  if p_entity_type = 'transactions' and existing is not null then
    normalized := normalized || jsonb_build_object(
      'note', case when p_payload ? 'note'
        then p_payload->'note' else existing->'note' end,
      'reference', case when p_payload ? 'reference'
        then p_payload->'reference' else existing->'reference' end
    );
  end if;
  if p_entity_type = 'books' then
    if existing is null then
      normalized := normalized || jsonb_build_object(
        'created_by_user_id', auth.uid(),
        'created_at', coalesce(normalized->'created_at', to_jsonb(now()))
      );
      insert into public.books
      select value.*
      from jsonb_populate_record(null::public.books, normalized) value;
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
    when 'monthly_category_budgets' then
      columns := 'id,book_id,category_id,month_start,limit_minor,currency_code,note,created_at,updated_at,deleted_at,version,device_id';
    when 'transaction_import_rules' then
      columns := 'id,book_id,name,enabled,priority,transaction_type,match_field,match_operator,pattern,pattern_key,account_id,category_id,created_at,updated_at,deleted_at,version,device_id';
    when 'transfer_links' then
      columns := 'id,book_id,outgoing_transaction_id,incoming_transaction_id,source_account_id,destination_account_id,currency_code,amount,created_at,updated_at,deleted_at,version,device_id';
    when 'import_review_sessions' then
      columns := 'id,book_id,source_type,title,source_fingerprint,destination_account_id,state,created_by_member_id,summary_json,created_at,updated_at,completed_at,deleted_at,version,device_id';
    when 'import_review_drafts' then
      columns := 'id,session_id,book_id,source_row_identity,source_row_key,deterministic_transaction_id,deterministic_transaction_account_id,source_index,transaction_date,description,amount_minor,currency_code,transaction_type,category_name,category_id,category_provenance,reference_text,note_text,merchant_hint,included,user_edited_fields_json,warnings_json,created_at,updated_at,deleted_at,version,device_id';
    when 'transactions' then
      columns := 'id,book_id,entered_by_member_id,project_id,title,category,category_id,account,note,reference,transaction_date,amount,transaction_type,quantity,unit,unit_price,asset_definition_id,asset_name,asset_symbol,asset_action,fee_amount,fee_treatment,related_transaction_id,relation_type,market_reference_unit_price,market_reference_currency_code,market_reference_unit,market_reference_source,market_reference_quoted_at,created_at,updated_at,deleted_at,version,device_id';
    else
      raise exception 'Unsupported sync entity: %', p_entity_type;
  end case;

  if existing is null then
    execute format(
      'insert into public.%I (%s) select %s '
      'from jsonb_populate_record(null::public.%I, $1)',
      p_entity_type, columns, columns, p_entity_type
    ) using normalized;
  else
    execute format(
      'update public.%I set (%s) = (select %s '
      'from jsonb_populate_record(null::public.%I, $1)) where id = $2',
      p_entity_type, columns, columns, p_entity_type
    ) using normalized, entity_id;
  end if;
  return public.sync_entity_snapshot(p_entity_type, entity_id);
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
    when 'household_members' then
      columns := 'id,book_id,display_name,role,created_at,updated_at,deleted_at,version,device_id';
    when 'categories' then
      columns := 'id,book_id,name,category_type,created_at,updated_at,deleted_at,version,device_id';
    when 'projects' then
      columns := 'id,book_id,name,status,created_at,updated_at,deleted_at,version,device_id';
    when 'accounts' then
      columns := 'id,book_id,owner_member_id,name,account_type,currency_code,opening_balance,opening_balance_date,created_at,updated_at,deleted_at,version,device_id';
    when 'asset_definitions' then
      columns := 'id,book_id,display_name,asset_kind,symbol,provider_code,provider_symbol,exchange_code,currency_code,unit,lot_size,online_pricing_enabled,created_at,updated_at,deleted_at,version,device_id';
    when 'monthly_category_budgets' then
      columns := 'id,book_id,category_id,month_start,limit_minor,currency_code,note,created_at,updated_at,deleted_at,version,device_id';
    when 'transaction_import_rules' then
      columns := 'id,book_id,name,enabled,priority,transaction_type,match_field,match_operator,pattern,pattern_key,account_id,category_id,created_at,updated_at,deleted_at,version,device_id';
    when 'transfer_links' then
      columns := 'id,book_id,outgoing_transaction_id,incoming_transaction_id,source_account_id,destination_account_id,currency_code,amount,created_at,updated_at,deleted_at,version,device_id';
    when 'import_review_sessions' then
      columns := 'id,book_id,source_type,title,source_fingerprint,destination_account_id,state,created_by_member_id,summary_json,created_at,updated_at,completed_at,deleted_at,version,device_id';
    when 'import_review_drafts' then
      columns := 'id,session_id,book_id,source_row_identity,source_row_key,deterministic_transaction_id,deterministic_transaction_account_id,source_index,transaction_date,description,amount_minor,currency_code,transaction_type,category_name,category_id,category_provenance,reference_text,note_text,merchant_hint,included,user_edited_fields_json,warnings_json,created_at,updated_at,deleted_at,version,device_id';
    when 'transactions' then
      columns := 'id,book_id,entered_by_member_id,project_id,title,category,category_id,account,note,reference,transaction_date,amount,transaction_type,quantity,unit,unit_price,asset_definition_id,asset_name,asset_symbol,asset_action,fee_amount,fee_treatment,related_transaction_id,relation_type,market_reference_unit_price,market_reference_currency_code,market_reference_unit,market_reference_source,market_reference_quoted_at,created_at,updated_at,deleted_at,version,device_id';
    else
      raise exception 'Unsupported initial snapshot entity: %', p_entity_type;
  end case;
  execute format(
    'insert into public.%I (%s) select %s '
    'from jsonb_populate_record(null::public.%I, $1)',
    p_entity_type, columns, columns, p_entity_type
  ) using p_payload;
end;
$$;

create or replace function public.initial_sync_allowed_fields(
  p_entity_type text
) returns text[] language sql immutable
set search_path = public, pg_temp as $$
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
    when 'monthly_category_budgets' then array[
      'id','book_id','category_id','month_start','limit_minor','currency_code',
      'note','created_at','updated_at','deleted_at','version','device_id'
    ]
    when 'transaction_import_rules' then array[
      'id','book_id','name','enabled','priority','transaction_type',
      'match_field','match_operator','pattern','pattern_key','account_id',
      'category_id','created_at','updated_at','deleted_at','version','device_id'
    ]
    when 'transfer_links' then array[
      'id','book_id','outgoing_transaction_id','incoming_transaction_id',
      'source_account_id','destination_account_id','currency_code','amount',
      'created_at','updated_at','deleted_at','version','device_id'
    ]
    when 'import_review_sessions' then array[
      'id','book_id','source_type','title','source_fingerprint',
      'destination_account_id','state','created_by_member_id','summary_json',
      'created_at','updated_at','completed_at','deleted_at','version','device_id'
    ]
    when 'import_review_drafts' then array[
      'id','session_id','book_id','source_row_identity','source_row_key',
      'deterministic_transaction_id','deterministic_transaction_account_id',
      'source_index','transaction_date','description','amount_minor',
      'currency_code','transaction_type','category_name','category_id',
      'category_provenance','reference_text','note_text','merchant_hint',
      'included','user_edited_fields_json','warnings_json','created_at',
      'updated_at','deleted_at','version','device_id'
    ]
    when 'transactions' then array[
      'id','book_id','entered_by_member_id','project_id','title','category',
      'category_id','account','note','reference','transaction_date','amount',
      'transaction_type','quantity','unit','unit_price','asset_definition_id',
      'asset_name','asset_symbol','asset_action','fee_amount','fee_treatment',
      'related_transaction_id','relation_type','market_reference_unit_price',
      'market_reference_currency_code','market_reference_unit',
      'market_reference_source','market_reference_quoted_at','created_at',
      'updated_at','deleted_at','version','device_id'
    ]
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
  if jsonb_typeof(p_operations) <> 'array'
     or jsonb_array_length(p_operations) > 50 then
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
        'transactions', 'asset_definitions', 'monthly_category_budgets',
        'transaction_import_rules', 'import_review_sessions',
        'import_review_drafts', 'transfer_links'
      ) or operation_type not in ('upsert', 'delete') or base_version < 0 then
        raise exception 'Invalid sync operation';
      end if;

      select * into processed from public.processed_sync_operations
      where processed_sync_operations.operation_id = current_operation_id;
      if processed.operation_id is not null then
        if processed.book_id <> p_book_id
           or processed.entity_type <> entity_type
           or processed.entity_id <> op_entity_id then
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
      if (entity_type = 'books' and op_entity_id <> p_book_id)
         or (entity_type <> 'books'
           and (payload->>'book_id')::uuid <> p_book_id) then
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
        when 'monthly_category_budgets' then array[
          'id','book_id','category_id','month_start','limit_minor',
          'currency_code','note','created_at','updated_at','deleted_at',
          'version','device_id'
        ]
        when 'transaction_import_rules' then array[
          'id','book_id','name','enabled','priority','transaction_type',
          'match_field','match_operator','pattern','pattern_key','account_id',
          'category_id','created_at','updated_at','deleted_at','version',
          'device_id'
        ]
        when 'transfer_links' then array[
          'id','book_id','outgoing_transaction_id','incoming_transaction_id',
          'source_account_id','destination_account_id','currency_code','amount',
          'created_at','updated_at','deleted_at','version','device_id'
        ]
        when 'import_review_sessions' then array[
          'id','book_id','source_type','title','source_fingerprint',
          'destination_account_id','state','created_by_member_id','summary_json',
          'created_at','updated_at','completed_at','deleted_at','version',
          'device_id'
        ]
        when 'import_review_drafts' then array[
          'id','session_id','book_id','source_row_identity','source_row_key',
          'deterministic_transaction_id','deterministic_transaction_account_id',
          'source_index','transaction_date','description','amount_minor',
          'currency_code','transaction_type','category_name','category_id',
          'category_provenance','reference_text','note_text','merchant_hint',
          'included','user_edited_fields_json','warnings_json','created_at',
          'updated_at','deleted_at','version','device_id'
        ]
        when 'transactions' then array[
          'id','book_id','entered_by_member_id','project_id','title','category',
          'category_id','account','note','reference','transaction_date','amount',
          'transaction_type','quantity','unit','unit_price','asset_definition_id',
          'asset_name','asset_symbol','asset_action','fee_amount','fee_treatment',
          'related_transaction_id','relation_type','market_reference_unit_price',
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
          current_operation_id, p_book_id, entity_type, op_entity_id,
          'version_conflict',
          coalesce((current_snapshot->>'version')::bigint, 0)
        );
        results := results || jsonb_build_array(jsonb_build_object(
          'operation_id', current_operation_id,
          'entity_type', entity_type,
          'status', 'version_conflict',
          'server_version', coalesce(
            (current_snapshot->>'version')::bigint, 0
          ),
          'server_payload', current_snapshot
        ));
        continue;
      end if;

      applied_snapshot := public.apply_sync_operation(
        entity_type, operation_type, payload, base_version,
        coalesce(operation->>'deviceId', 'unknown-device')
      );
      select max(sequence) into sequence_value
      from public.app_changes
      where book_id = p_book_id
        and entity_table = entity_type
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
