-- Serialize version-check + write + idempotency acknowledgement for a household.
-- Same transaction-scoped key as initial sync. No data/schema/RLS/ACL change.
-- Existing full validators remain authoritative; no historical migration edits.
do $migration$
declare
  target regprocedure;
  definition text;
  anchor text;
begin
  foreach target in array array[
    'public.push_book_changes_pre_beta08n0(uuid,jsonb)'::regprocedure,
    'public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure
  ] loop
    definition := pg_get_functiondef(target);
    anchor := case when target =
      'public.push_book_changes_pre_beta08n0(uuid,jsonb)'::regprocedure
      then '  for operation in select value from jsonb_array_elements(p_operations) loop'
      else '  select * into processed from public.processed_sync_operations' end;
    if position(anchor in definition) = 0 then
      raise exception 'Unexpected sync function definition: %', target;
    end if;
    definition := replace(definition, anchor,
      E'  perform pg_advisory_xact_lock(hashtextextended(p_book_id::text, 0));\n'
      || anchor);
    execute definition;
  end loop;
end
$migration$;
