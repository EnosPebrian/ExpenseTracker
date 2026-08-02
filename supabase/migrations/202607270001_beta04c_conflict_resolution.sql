create or replace function public.resolve_sync_conflict(
  p_book_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_expected_server_version bigint,
  p_resolution_operation_id uuid,
  p_resolution_type text,
  p_resolved_payload jsonb default null
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  current_snapshot jsonb;
  resolved_snapshot jsonb;
  processed public.processed_sync_operations;
  sequence_value bigint;
  operation_type text := 'upsert';
begin
  if auth.uid() is null then
    return jsonb_build_object('status', 'unauthorized');
  end if;
  if not public.is_active_book_member(p_book_id) then
    return jsonb_build_object('status', 'unauthorized');
  end if;
  if p_entity_type not in ('books','household_members','accounts','categories','projects','transactions','asset_definitions')
     or p_resolution_type not in ('keepServer','keepDevice','manualMerge','keepDeleted','restoreDevice') then
    return jsonb_build_object('status', 'validationError');
  end if;

  select * into processed from public.processed_sync_operations
    where operation_id = p_resolution_operation_id;
  if processed.operation_id is not null then
    if processed.book_id <> p_book_id or processed.entity_type <> p_entity_type or processed.entity_id <> p_entity_id then
      return jsonb_build_object('status', 'validationError');
    end if;
    return jsonb_build_object(
      'status', 'alreadyResolved',
      'canonical_snapshot', public.sync_entity_snapshot(p_entity_type, p_entity_id),
      'server_version', processed.server_version,
      'server_sequence', processed.server_sequence
    );
  end if;

  current_snapshot := public.sync_entity_snapshot(p_entity_type, p_entity_id);
  if current_snapshot is null or coalesce((current_snapshot->>'version')::bigint, 0) <> p_expected_server_version then
    return jsonb_build_object('status', 'staleResolution', 'canonical_snapshot', current_snapshot);
  end if;
  if (p_entity_type = 'books' and p_entity_id <> p_book_id) or
     (p_entity_type <> 'books' and (current_snapshot->>'book_id')::uuid <> p_book_id) then
    return jsonb_build_object('status', 'unauthorized');
  end if;

  if p_resolution_type = 'keepServer' then
    resolved_snapshot := current_snapshot;
    select max(sequence) into sequence_value from public.app_changes
      where book_id = p_book_id and entity_table = p_entity_type and entity_id = p_entity_id;
  else
    if p_resolved_payload is null or (p_resolved_payload->>'id')::uuid <> p_entity_id then
      return jsonb_build_object('status', 'validationError');
    end if;
    if (p_entity_type = 'books' and p_entity_id <> p_book_id) or
       (p_entity_type <> 'books' and (p_resolved_payload->>'book_id')::uuid <> p_book_id) then
      return jsonb_build_object('status', 'validationError');
    end if;
    if p_resolution_type = 'keepDeleted' then operation_type := 'delete'; end if;
    resolved_snapshot := public.apply_sync_operation(
      p_entity_type, operation_type, p_resolved_payload,
      p_expected_server_version, coalesce(p_resolved_payload->>'device_id', 'conflict-resolution')
    );
    select max(sequence) into sequence_value from public.app_changes
      where book_id = p_book_id and entity_table = p_entity_type and entity_id = p_entity_id;
  end if;

  insert into public.processed_sync_operations(
    operation_id, book_id, entity_type, entity_id, result_status,
    server_version, server_sequence
  ) values (
    p_resolution_operation_id, p_book_id, p_entity_type, p_entity_id,
    'resolved', (resolved_snapshot->>'version')::bigint, sequence_value
  );
  return jsonb_build_object(
    'status', 'resolved', 'canonical_snapshot', resolved_snapshot,
    'server_version', (resolved_snapshot->>'version')::bigint,
    'server_sequence', coalesce(sequence_value, 0)
  );
exception when others then
  return jsonb_build_object('status', 'validationError');
end;
$$;

revoke execute on function public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb) from public, anon;
grant execute on function public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb) to authenticated;
