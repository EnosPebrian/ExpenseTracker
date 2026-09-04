create table public.telegram_connections (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id),
  book_id uuid not null references public.books(id),
  member_id uuid not null references public.household_members(id),
  telegram_user_id bigint not null check (telegram_user_id > 0),
  telegram_chat_id bigint not null check (telegram_chat_id > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (telegram_user_id = telegram_chat_id)
);

create unique index telegram_connections_one_active_identity
  on public.telegram_connections(telegram_user_id) where revoked_at is null;
create unique index telegram_connections_one_active_user
  on public.telegram_connections(auth_user_id) where revoked_at is null;
create index telegram_connections_book on public.telegram_connections(book_id);

create table public.telegram_pairing_tokens (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id),
  book_id uuid not null references public.books(id),
  member_id uuid not null references public.household_members(id),
  token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz,
  check (expires_at > created_at),
  check (consumed_at is null or consumed_at >= created_at),
  check (revoked_at is null or revoked_at >= created_at)
);

create unique index telegram_pairing_tokens_one_outstanding_user
  on public.telegram_pairing_tokens(auth_user_id)
  where consumed_at is null and revoked_at is null;
create index telegram_pairing_tokens_expiry on public.telegram_pairing_tokens(expires_at);

create table public.telegram_ingestion_events (
  update_id bigint primary key,
  connection_id uuid references public.telegram_connections(id),
  telegram_user_id bigint,
  telegram_message_id bigint,
  event_type text not null check (event_type in ('command','link','attachment','unsupported')),
  status text not null check (status in ('received','processing','completed','failed','ignored')),
  session_id uuid references public.import_review_sessions(id),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  sanitized_error_code text check (
    sanitized_error_code is null or
    sanitized_error_code ~ '^[a-z][a-z0-9_]{0,63}$'
  )
);

create index telegram_ingestion_events_connection_time
  on public.telegram_ingestion_events(connection_id,received_at desc);
create index telegram_ingestion_events_identity_time
  on public.telegram_ingestion_events(telegram_user_id,received_at desc);

alter table public.telegram_connections enable row level security;
alter table public.telegram_pairing_tokens enable row level security;
alter table public.telegram_ingestion_events enable row level security;

create policy telegram_connections_owner_read on public.telegram_connections
  for select to authenticated using (
    auth_user_id = auth.uid() and public.is_active_book_member(book_id)
  );

revoke all on public.telegram_connections from anon, authenticated;
revoke all on public.telegram_pairing_tokens from anon, authenticated;
revoke all on public.telegram_ingestion_events from anon, authenticated;
grant select on public.telegram_connections to authenticated;

create or replace function public.validate_telegram_connection()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' and (
    new.auth_user_id <> old.auth_user_id or new.book_id <> old.book_id or
    new.member_id <> old.member_id or new.telegram_user_id <> old.telegram_user_id or
    new.telegram_chat_id <> old.telegram_chat_id or new.created_at <> old.created_at
  ) then
    raise exception 'Telegram connection identity is immutable.';
  end if;
  if new.revoked_at is null and not exists (
    select 1 from public.book_memberships membership
    join public.household_members member
      on member.id = new.member_id and member.book_id = membership.book_id
    where membership.book_id = new.book_id
      and membership.user_id = new.auth_user_id
      and membership.household_member_id = new.member_id
      and membership.status = 'active'
      and member.deleted_at is null
  ) then
    raise exception 'Telegram connection requires active mapped membership.';
  end if;
  return new;
end; $$;

create trigger validate_telegram_connection_reference
before insert or update on public.telegram_connections
for each row execute function public.validate_telegram_connection();

create or replace function public.telegram_connection_status(p_book_id uuid)
returns table(connected boolean, connected_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_active_book_member(p_book_id) then
    raise exception 'Active household membership required.';
  end if;
  return query select true, connection.created_at
  from public.telegram_connections connection
  where connection.auth_user_id = auth.uid()
    and connection.book_id = p_book_id and connection.revoked_at is null
  limit 1;
  if not found then return query select false, null::timestamptz; end if;
end; $$;

create or replace function public.issue_telegram_pairing_token(
  p_book_id uuid,
  p_member_id uuid,
  p_token_hash text,
  p_expires_at timestamptz
) returns timestamptz
language plpgsql security definer set search_path = public, pg_temp as $$
declare caller uuid := auth.uid();
begin
  if caller is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid pairing request.';
  end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '11 minutes' then
    raise exception 'Invalid pairing expiry.';
  end if;
  if not exists (
    select 1 from public.book_memberships membership
    join public.household_members member
      on member.id = p_member_id and member.book_id = membership.book_id
    where membership.book_id = p_book_id and membership.user_id = caller
      and membership.household_member_id = p_member_id
      and membership.status = 'active' and member.deleted_at is null
  ) then raise exception 'Active mapped membership required.'; end if;

  update public.telegram_pairing_tokens set revoked_at = now()
  where auth_user_id = caller and consumed_at is null and revoked_at is null;
  insert into public.telegram_pairing_tokens(
    auth_user_id,book_id,member_id,token_hash,expires_at
  ) values (caller,p_book_id,p_member_id,decode(p_token_hash,'hex'),p_expires_at);
  return p_expires_at;
end; $$;

create or replace function public.disconnect_telegram_connection(p_book_id uuid)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare changed integer;
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  update public.telegram_connections set revoked_at = now(), updated_at = now()
  where auth_user_id = auth.uid() and book_id = p_book_id and revoked_at is null;
  get diagnostics changed = row_count;
  update public.telegram_pairing_tokens set revoked_at = now()
  where auth_user_id = auth.uid() and book_id = p_book_id
    and consumed_at is null and revoked_at is null;
  return changed > 0;
end; $$;

create or replace function public.telegram_claim_ingestion_event(
  p_update_id bigint,
  p_telegram_user_id bigint,
  p_telegram_chat_id bigint,
  p_message_id bigint,
  p_event_type text
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare connection public.telegram_connections%rowtype;
declare inserted integer;
declare hourly_count integer;
declare daily_count integer;
begin
  if p_update_id < 0 or p_telegram_user_id <= 0 or
     p_telegram_chat_id <> p_telegram_user_id or
     p_event_type not in ('command','link','attachment','unsupported') then
    raise exception 'Invalid Telegram event.';
  end if;
  insert into public.telegram_ingestion_events(
    update_id,telegram_user_id,telegram_message_id,event_type,status
  ) values (p_update_id,p_telegram_user_id,p_message_id,p_event_type,'received')
  on conflict (update_id) do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then return jsonb_build_object('claimed',false,'reason','duplicate'); end if;

  if p_event_type = 'link' then
    select count(*) into hourly_count from public.telegram_ingestion_events event
    where event.telegram_user_id = p_telegram_user_id and event.event_type = 'link'
      and event.received_at > now() - interval '1 hour';
    if hourly_count > 10 then
      update public.telegram_ingestion_events set status='failed',processed_at=now(),
        sanitized_error_code='rate_limited' where update_id=p_update_id;
      return jsonb_build_object('claimed',false,'reason','rate_limited');
    end if;
    update public.telegram_ingestion_events set status='processing'
      where update_id=p_update_id;
    return jsonb_build_object('claimed',true,'linked',false);
  end if;

  select * into connection from public.telegram_connections candidate
  where candidate.telegram_user_id = p_telegram_user_id
    and candidate.telegram_chat_id = p_telegram_chat_id
    and candidate.revoked_at is null limit 1;

  if connection.id is null then
    update public.telegram_ingestion_events set status='failed',processed_at=now(),
      sanitized_error_code='not_linked' where update_id=p_update_id;
    return jsonb_build_object('claimed',false,'reason','not_linked');
  end if;
  if not exists (
    select 1 from public.book_memberships membership
    join public.household_members member
      on member.id=connection.member_id and member.book_id=membership.book_id
    where membership.book_id=connection.book_id
      and membership.user_id=connection.auth_user_id
      and membership.household_member_id=connection.member_id
      and membership.status='active' and member.deleted_at is null
  ) then
    update public.telegram_connections set revoked_at=now(),updated_at=now()
      where id=connection.id;
    update public.telegram_ingestion_events set status='failed',processed_at=now(),
      sanitized_error_code='membership_revoked' where update_id=p_update_id;
    return jsonb_build_object('claimed',false,'reason','membership_revoked');
  end if;

  update public.telegram_ingestion_events set connection_id=connection.id
    where update_id=p_update_id;
  if p_event_type = 'attachment' then
    select count(*) into hourly_count from public.telegram_ingestion_events event
      where event.connection_id=connection.id and event.event_type='attachment'
        and event.received_at > now() - interval '1 hour';
    select count(*) into daily_count from public.telegram_ingestion_events event
      where event.connection_id=connection.id and event.event_type='attachment'
        and event.received_at > now() - interval '1 day';
    if hourly_count > 10 or daily_count > 50 then
      update public.telegram_ingestion_events set status='failed',processed_at=now(),
        sanitized_error_code='rate_limited' where update_id=p_update_id;
      return jsonb_build_object('claimed',false,'reason','rate_limited');
    end if;
  end if;
  update public.telegram_ingestion_events set status='processing'
    where update_id=p_update_id;
  return jsonb_build_object(
    'claimed',true,'linked',true,'connection_id',connection.id,
    'book_id',connection.book_id,'member_id',connection.member_id,
    'currency_code',(select base_currency_code from public.books where id=connection.book_id)
  );
end; $$;

create or replace function public.telegram_consume_pairing_token(
  p_update_id bigint,
  p_token_hash text,
  p_telegram_user_id bigint,
  p_telegram_chat_id bigint
) returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare token public.telegram_pairing_tokens%rowtype;
declare new_connection_id uuid;
begin
  if p_token_hash !~ '^[0-9a-f]{64}$' or p_telegram_user_id <= 0 or
     p_telegram_chat_id <> p_telegram_user_id then return false; end if;
  select * into token from public.telegram_pairing_tokens candidate
    where candidate.token_hash=decode(p_token_hash,'hex') for update;
  if token.id is null or token.expires_at <= now() or token.consumed_at is not null
     or token.revoked_at is not null then return false; end if;
  if not exists (
    select 1 from public.book_memberships membership
    join public.household_members member
      on member.id=token.member_id and member.book_id=membership.book_id
    where membership.book_id=token.book_id and membership.user_id=token.auth_user_id
      and membership.household_member_id=token.member_id
      and membership.status='active' and member.deleted_at is null
  ) then
    update public.telegram_pairing_tokens set revoked_at=now() where id=token.id;
    return false;
  end if;
  update public.telegram_connections set revoked_at=now(),updated_at=now()
    where revoked_at is null and
      (telegram_user_id=p_telegram_user_id or auth_user_id=token.auth_user_id);
  insert into public.telegram_connections(
    auth_user_id,book_id,member_id,telegram_user_id,telegram_chat_id
  ) values (
    token.auth_user_id,token.book_id,token.member_id,p_telegram_user_id,p_telegram_chat_id
  ) returning id into new_connection_id;
  update public.telegram_pairing_tokens set consumed_at=now() where id=token.id;
  update public.telegram_ingestion_events set connection_id=new_connection_id,
    status='completed',processed_at=now(),sanitized_error_code=null
    where update_id=p_update_id;
  return true;
end; $$;

create or replace function public.telegram_revoke_connection(
  p_update_id bigint,p_telegram_user_id bigint,p_telegram_chat_id bigint
) returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare changed integer;
begin
  update public.telegram_connections set revoked_at=now(),updated_at=now()
  where telegram_user_id=p_telegram_user_id and telegram_chat_id=p_telegram_chat_id
    and revoked_at is null;
  get diagnostics changed=row_count;
  update public.telegram_ingestion_events set status='completed',processed_at=now()
    where update_id=p_update_id;
  return changed > 0;
end; $$;

create or replace function public.telegram_finish_ingestion_event(
  p_update_id bigint,p_status text,p_error_code text default null
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_status not in ('completed','failed','ignored') or
     (p_error_code is not null and p_error_code !~ '^[a-z][a-z0-9_]{0,63}$') then
    raise exception 'Invalid event completion.';
  end if;
  update public.telegram_ingestion_events set status=p_status,processed_at=now(),
    sanitized_error_code=p_error_code where update_id=p_update_id;
end; $$;

create or replace function public.create_telegram_import_review(
  p_update_id bigint,p_connection_id uuid,p_session jsonb,p_drafts jsonb
) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare connection public.telegram_connections%rowtype;
declare event public.telegram_ingestion_events%rowtype;
declare draft jsonb;
declare new_session_id uuid := (p_session->>'id')::uuid;
declare source_type text := p_session->>'source_type';
declare fingerprint text := p_session->>'source_fingerprint';
declare title text := p_session->>'title';
declare draft_count integer;
begin
  select * into event from public.telegram_ingestion_events candidate
    where candidate.update_id=p_update_id and candidate.connection_id=p_connection_id
      and candidate.status='processing' for update;
  select * into connection from public.telegram_connections candidate
    where candidate.id=p_connection_id and candidate.revoked_at is null;
  if event.update_id is null or connection.id is null then
    raise exception 'Telegram ingestion claim is unavailable.';
  end if;
  if not exists (
    select 1 from public.book_memberships membership
    join public.household_members member
      on member.id=connection.member_id and member.book_id=membership.book_id
    where membership.book_id=connection.book_id
      and membership.user_id=connection.auth_user_id
      and membership.household_member_id=connection.member_id
      and membership.status='active' and member.deleted_at is null
  ) then raise exception 'Active mapped membership required.'; end if;
  draft_count := jsonb_array_length(p_drafts);
  if source_type not in ('csv','receipt','invoice','bankStatement') or
     fingerprint !~ '^[0-9a-f]{64}$' or length(title) not between 1 and 160 or
     draft_count < 1 or draft_count > 5000 then
    raise exception 'Invalid normalized Telegram import.';
  end if;

  insert into public.import_review_sessions(
    id,book_id,source_type,title,source_fingerprint,destination_account_id,state,
    created_by_member_id,summary_json,created_at,updated_at,version,device_id
  ) values (
    new_session_id,connection.book_id,source_type,title,fingerprint,null,'pendingReview',
    connection.member_id,coalesce((p_session->'summary')::text,'{}'),now(),now(),1,
    'telegram-gateway'
  );
  for draft in select value from jsonb_array_elements(p_drafts) loop
    if (draft ? 'deterministic_transaction_id') or
       (draft ? 'deterministic_transaction_account_id') then
      raise exception 'Telegram cannot assign final financial identity.';
    end if;
    insert into public.import_review_drafts(
      id,session_id,book_id,source_row_identity,source_row_key,
      deterministic_transaction_id,deterministic_transaction_account_id,
      source_index,transaction_date,description,amount_minor,currency_code,
      transaction_type,category_name,category_id,category_provenance,
      reference_text,note_text,merchant_hint,included,user_edited_fields_json,
      warnings_json,created_at,updated_at,version,device_id
    ) values (
      (draft->>'id')::uuid,new_session_id,connection.book_id,
      draft->>'source_row_identity',draft->>'source_row_key',null,null,
      (draft->>'source_index')::integer,(draft->>'transaction_date')::timestamptz,
      left(coalesce(draft->>'description',''),10000),(draft->>'amount_minor')::bigint,
      upper(draft->>'currency_code'),draft->>'transaction_type',
      left(coalesce(draft->>'category_name',''),10000),null,
      coalesce(draft->>'category_provenance','unresolved'),
      left(coalesce(draft->>'reference_text',''),10000),
      left(coalesce(draft->>'note_text',''),10000),
      left(coalesce(draft->>'merchant_hint',''),10000),true,'[]',
      coalesce((draft->'warnings')::text,'[]'),now(),now(),1,'telegram-gateway'
    );
  end loop;
  update public.telegram_ingestion_events set status='completed',session_id=new_session_id,
    processed_at=now(),sanitized_error_code=null where update_id=p_update_id;
  return new_session_id;
end; $$;

revoke all on function public.telegram_connection_status(uuid) from public;
revoke all on function public.issue_telegram_pairing_token(uuid,uuid,text,timestamptz) from public;
revoke all on function public.disconnect_telegram_connection(uuid) from public;
grant execute on function public.telegram_connection_status(uuid) to authenticated;
grant execute on function public.issue_telegram_pairing_token(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function public.disconnect_telegram_connection(uuid) to authenticated;

revoke all on function public.telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text) from public;
revoke all on function public.telegram_consume_pairing_token(bigint,text,bigint,bigint) from public;
revoke all on function public.telegram_revoke_connection(bigint,bigint,bigint) from public;
revoke all on function public.telegram_finish_ingestion_event(bigint,text,text) from public;
revoke all on function public.create_telegram_import_review(bigint,uuid,jsonb,jsonb) from public;
grant execute on function public.telegram_claim_ingestion_event(bigint,bigint,bigint,bigint,text) to service_role;
grant execute on function public.telegram_consume_pairing_token(bigint,text,bigint,bigint) to service_role;
grant execute on function public.telegram_revoke_connection(bigint,bigint,bigint) to service_role;
grant execute on function public.telegram_finish_ingestion_event(bigint,text,text) to service_role;
grant execute on function public.create_telegram_import_review(bigint,uuid,jsonb,jsonb) to service_role;
