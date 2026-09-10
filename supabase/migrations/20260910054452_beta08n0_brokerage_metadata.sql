-- BETA-08N0: additive brokerage attribution on authoritative transactions.
alter table public.transactions
  add column brokerage_account_id uuid references public.accounts(id),
  add column brokerage_activity_type text,
  add column split_numerator bigint,
  add column split_denominator bigint;

alter table public.transactions
  add constraint transactions_brokerage_identity_pair check (
    (brokerage_account_id is null) = (brokerage_activity_type is null)
  ),
  add constraint transactions_brokerage_activity_type check (
    brokerage_activity_type is null or brokerage_activity_type in (
      'buy', 'sell', 'dividend', 'fee', 'tax', 'deposit', 'withdrawal', 'split'
    )
  ),
  add constraint transactions_brokerage_split_shape check (
    (brokerage_activity_type = 'split'
      and split_numerator is not null and split_numerator > 0
      and split_denominator is not null and split_denominator > 0)
    or
    (brokerage_activity_type is distinct from 'split'
      and split_numerator is null and split_denominator is null)
  );

create index transactions_brokerage_account_id
  on public.transactions(brokerage_account_id);

create or replace function public.validate_transaction_brokerage_reference()
returns trigger language plpgsql
set search_path = public, pg_temp as $$
begin
  if new.brokerage_account_id is null then
    return new;
  end if;
  if not exists (
    select 1 from public.accounts account
    where account.id = new.brokerage_account_id
      and account.book_id = new.book_id
      and account.account_type = 'brokerage'
  ) then
    raise exception 'Brokerage account must belong to the transaction household';
  end if;
  if new.brokerage_activity_type in ('buy', 'sell', 'split') and not exists (
    select 1 from public.asset_definitions definition
    where definition.id = new.asset_definition_id
      and definition.book_id = new.book_id
  ) then
    raise exception 'Brokerage trade instrument must belong to the transaction household';
  end if;
  if (new.brokerage_activity_type = 'buy'
      and (new.transaction_type <> 'assetConversion' or new.asset_action <> 'buy'))
    or (new.brokerage_activity_type = 'sell'
      and (new.transaction_type <> 'assetConversion' or new.asset_action <> 'sell'))
    or (new.brokerage_activity_type = 'split'
      and (new.transaction_type <> 'assetConversion'
        or new.asset_action <> 'split' or new.amount <> 0))
    or (new.brokerage_activity_type in ('dividend', 'fee', 'tax')
      and new.transaction_type <> 'investment')
    or (new.brokerage_activity_type = 'deposit'
      and new.transaction_type <> 'income')
    or (new.brokerage_activity_type = 'withdrawal'
      and new.transaction_type <> 'expense') then
    raise exception 'Brokerage activity does not match its authoritative transaction';
  end if;
  return new;
end;
$$;

-- Presence-sensitive metadata is injected by the sync wrappers below before
-- the existing authoritative sync functions write the row. Omitted keys keep
-- their stored value while explicit JSON null clears the pending attribution.
create or replace function public.apply_transaction_brokerage_sync_context()
returns trigger language plpgsql
set search_path = public, pg_temp as $$
declare
  context jsonb := coalesce(
    nullif(current_setting('pilgrim.brokerage_sync_payloads', true), '')::jsonb,
    '{}'::jsonb
  );
  metadata jsonb;
begin
  metadata := context -> new.id::text;
  if metadata is null then return new; end if;
  if metadata ? 'brokerage_account_id' then
    new.brokerage_account_id := (metadata->>'brokerage_account_id')::uuid;
  end if;
  if metadata ? 'brokerage_activity_type' then
    new.brokerage_activity_type := metadata->>'brokerage_activity_type';
  end if;
  if metadata ? 'split_numerator' then
    new.split_numerator := (metadata->>'split_numerator')::bigint;
  end if;
  if metadata ? 'split_denominator' then
    new.split_denominator := (metadata->>'split_denominator')::bigint;
  end if;
  return new;
end;
$$;

create trigger a_apply_transaction_brokerage_sync_context
before insert or update on public.transactions
for each row execute function public.apply_transaction_brokerage_sync_context();

create trigger z_validate_transaction_brokerage_reference
before insert or update on public.transactions
for each row execute function public.validate_transaction_brokerage_reference();

alter function public.apply_sync_operation(text,text,jsonb,bigint,text)
  rename to apply_sync_operation_pre_beta08n0;

create function public.apply_sync_operation(
  p_entity_type text,
  p_operation_type text,
  p_payload jsonb,
  p_base_version bigint,
  p_device_id text
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  metadata jsonb := '{}'::jsonb;
begin
  if p_entity_type = 'transactions' and p_payload ?| array[
    'brokerage_account_id', 'brokerage_activity_type',
    'split_numerator', 'split_denominator'
  ] then
    if p_payload ? 'brokerage_account_id' then metadata := metadata ||
      jsonb_build_object('brokerage_account_id', p_payload->'brokerage_account_id'); end if;
    if p_payload ? 'brokerage_activity_type' then metadata := metadata ||
      jsonb_build_object('brokerage_activity_type', p_payload->'brokerage_activity_type'); end if;
    if p_payload ? 'split_numerator' then metadata := metadata ||
      jsonb_build_object('split_numerator', p_payload->'split_numerator'); end if;
    if p_payload ? 'split_denominator' then metadata := metadata ||
      jsonb_build_object('split_denominator', p_payload->'split_denominator'); end if;
    perform set_config(
      'pilgrim.brokerage_sync_payloads',
      jsonb_build_object(p_payload->>'id', metadata)::text,
      true
    );
  end if;
  return public.apply_sync_operation_pre_beta08n0(
    p_entity_type,
    p_operation_type,
    p_payload - array[
      'brokerage_account_id', 'brokerage_activity_type',
      'split_numerator', 'split_denominator'
    ],
    p_base_version,
    p_device_id
  );
end;
$$;

alter function public.initial_sync_allowed_fields(text)
  rename to initial_sync_allowed_fields_pre_beta08n0;

create function public.initial_sync_allowed_fields(p_entity_type text)
returns text[] language sql immutable
set search_path = public, pg_temp as $$
  select public.initial_sync_allowed_fields_pre_beta08n0(p_entity_type) ||
    case when p_entity_type = 'transactions' then array[
      'brokerage_account_id', 'brokerage_activity_type',
      'split_numerator', 'split_denominator'
    ] else array[]::text[] end;
$$;

alter function public.apply_initial_snapshot_row(text,jsonb)
  rename to apply_initial_snapshot_row_pre_beta08n0;

create function public.apply_initial_snapshot_row(
  p_entity_type text,
  p_payload jsonb
) returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  metadata jsonb := '{}'::jsonb;
begin
  if p_entity_type = 'transactions' and p_payload ?| array[
    'brokerage_account_id', 'brokerage_activity_type',
    'split_numerator', 'split_denominator'
  ] then
    if p_payload ? 'brokerage_account_id' then metadata := metadata ||
      jsonb_build_object('brokerage_account_id', p_payload->'brokerage_account_id'); end if;
    if p_payload ? 'brokerage_activity_type' then metadata := metadata ||
      jsonb_build_object('brokerage_activity_type', p_payload->'brokerage_activity_type'); end if;
    if p_payload ? 'split_numerator' then metadata := metadata ||
      jsonb_build_object('split_numerator', p_payload->'split_numerator'); end if;
    if p_payload ? 'split_denominator' then metadata := metadata ||
      jsonb_build_object('split_denominator', p_payload->'split_denominator'); end if;
    perform set_config(
      'pilgrim.brokerage_sync_payloads',
      jsonb_build_object(p_payload->>'id', metadata)::text,
      true
    );
  end if;
  perform public.apply_initial_snapshot_row_pre_beta08n0(
    p_entity_type,
    p_payload - array[
      'brokerage_account_id', 'brokerage_activity_type',
      'split_numerator', 'split_denominator'
    ]
  );
end;
$$;

alter function public.push_book_changes(uuid,jsonb)
  rename to push_book_changes_pre_beta08n0;

create function public.push_book_changes(
  p_book_id uuid,
  p_operations jsonb
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  operation jsonb;
  metadata_by_id jsonb := '{}'::jsonb;
  metadata jsonb;
  sanitized jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_operations) = 'array' then
    for operation in select value from jsonb_array_elements(p_operations) loop
      if operation->>'entityType' = 'transactions'
         and operation->'payload' ?| array[
           'brokerage_account_id', 'brokerage_activity_type',
           'split_numerator', 'split_denominator'
         ] then
        metadata := '{}'::jsonb;
        if operation->'payload' ? 'brokerage_account_id' then metadata := metadata ||
          jsonb_build_object('brokerage_account_id', operation->'payload'->'brokerage_account_id'); end if;
        if operation->'payload' ? 'brokerage_activity_type' then metadata := metadata ||
          jsonb_build_object('brokerage_activity_type', operation->'payload'->'brokerage_activity_type'); end if;
        if operation->'payload' ? 'split_numerator' then metadata := metadata ||
          jsonb_build_object('split_numerator', operation->'payload'->'split_numerator'); end if;
        if operation->'payload' ? 'split_denominator' then metadata := metadata ||
          jsonb_build_object('split_denominator', operation->'payload'->'split_denominator'); end if;
        metadata_by_id := metadata_by_id ||
          jsonb_build_object(operation->>'entityId', metadata);
        operation := jsonb_set(
          operation,
          '{payload}',
          (operation->'payload') - array[
            'brokerage_account_id', 'brokerage_activity_type',
            'split_numerator', 'split_denominator'
          ]
        );
      end if;
      sanitized := sanitized || jsonb_build_array(operation);
    end loop;
  else
    sanitized := p_operations;
  end if;
  perform set_config(
    'pilgrim.brokerage_sync_payloads',
    metadata_by_id::text,
    true
  );
  return public.push_book_changes_pre_beta08n0(p_book_id, sanitized);
end;
$$;

revoke execute on function public.apply_sync_operation_pre_beta08n0(text,text,jsonb,bigint,text)
  from public, anon, authenticated;
revoke execute on function public.initial_sync_allowed_fields_pre_beta08n0(text)
  from public, anon, authenticated;
revoke execute on function public.apply_initial_snapshot_row_pre_beta08n0(text,jsonb)
  from public, anon, authenticated;
revoke execute on function public.push_book_changes_pre_beta08n0(uuid,jsonb)
  from public, anon, authenticated;
revoke execute on function public.apply_transaction_brokerage_sync_context()
  from public, anon, authenticated;
revoke execute on function public.validate_transaction_brokerage_reference()
  from public, anon, authenticated;
revoke execute on function public.apply_sync_operation(text,text,jsonb,bigint,text)
  from public, anon, authenticated;
revoke execute on function public.initial_sync_allowed_fields(text)
  from public, anon, authenticated;
revoke execute on function public.apply_initial_snapshot_row(text,jsonb)
  from public, anon, authenticated;
revoke execute on function public.push_book_changes(uuid,jsonb)
  from public, anon;
grant execute on function public.push_book_changes(uuid,jsonb) to authenticated;
