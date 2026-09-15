-- Non-financial reconciliation evidence; no transaction/account mutation.
create table public.brokerage_settlements (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  brokerage_account_id uuid not null references public.accounts(id),
  statement_date timestamptz not null,
  settlement_type text not null check (settlement_type in ('BUY_SETTLEMENT','SELL_SETTLEMENT')),
  amount bigint not null check (amount > 0),
  currency_code text not null,
  source_fingerprint text not null,
  source_row_identity text not null,
  source_row_fingerprint text not null,
  reference text not null default '',
  note text not null default '',
  trade_ids_json text not null default '[]' check (jsonb_typeof(trade_ids_json::jsonb) = 'array'),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null,
  unique(book_id,brokerage_account_id,source_fingerprint,source_row_identity,source_row_fingerprint)
);
create index brokerage_settlements_book on public.brokerage_settlements(book_id);
create index brokerage_settlements_account on public.brokerage_settlements(brokerage_account_id);
create index brokerage_settlements_updated on public.brokerage_settlements(updated_at);
alter table public.brokerage_settlements enable row level security;
revoke all on public.brokerage_settlements from anon;
grant select, insert, update on public.brokerage_settlements to authenticated;
create policy settlement_select on public.brokerage_settlements for select to authenticated using (public.is_active_book_member(book_id));
create policy settlement_insert on public.brokerage_settlements for insert to authenticated with check (public.is_active_book_member(book_id));
create policy settlement_update on public.brokerage_settlements for update to authenticated using (public.is_active_book_member(book_id)) with check (public.is_active_book_member(book_id));

create function public.validate_brokerage_settlement() returns trigger language plpgsql security invoker set search_path = public, pg_temp as $$
declare trade_id text;
begin
  if tg_op = 'UPDATE' and (new.id <> old.id or new.book_id <> old.book_id or new.brokerage_account_id <> old.brokerage_account_id or new.statement_date <> old.statement_date or new.amount <> old.amount or new.currency_code <> old.currency_code or new.settlement_type <> old.settlement_type or new.source_fingerprint <> old.source_fingerprint or new.source_row_identity <> old.source_row_identity or new.source_row_fingerprint <> old.source_row_fingerprint or new.reference <> old.reference or new.note <> old.note) then
    raise exception 'Settlement source identity and evidence are immutable';
  end if;
  if not exists(select 1 from public.accounts a where a.id = new.brokerage_account_id and a.book_id = new.book_id and a.account_type = 'brokerage' and a.currency_code = new.currency_code) then raise exception 'Incompatible settlement account'; end if;
  if (select count(*) <> count(distinct value) from jsonb_array_elements_text(new.trade_ids_json::jsonb)) then raise exception 'Duplicate trade references'; end if;
  for trade_id in select jsonb_array_elements_text(new.trade_ids_json::jsonb) loop
    if not exists(select 1 from public.transactions t where t.id = trade_id::uuid and t.book_id = new.book_id and t.brokerage_account_id = new.brokerage_account_id and t.brokerage_activity_type = case new.settlement_type when 'BUY_SETTLEMENT' then 'buy' else 'sell' end) then raise exception 'Incompatible settlement trade reference'; end if;
  end loop;
  return new;
end; $$;
revoke all on function public.validate_brokerage_settlement() from public, anon, authenticated;
create trigger validate_brokerage_settlement before insert or update on public.brokerage_settlements for each row execute function public.validate_brokerage_settlement();
create trigger capture_brokerage_settlements_change after insert or update or delete on public.brokerage_settlements for each row execute function public.capture_financial_change();
create trigger enforce_initial_sync_brokerage_settlements before insert or update on public.brokerage_settlements for each row execute function public.enforce_initialized_financial_write();

-- Extend existing protocol registries without replacing their authorization,
-- presence-sensitive payload handling or version-conflict rules.
do $$
declare
  target regprocedure;
  definition text;
  original text;
  columns text := 'id,book_id,brokerage_account_id,statement_date,settlement_type,amount,currency_code,source_fingerprint,source_row_identity,source_row_fingerprint,reference,note,trade_ids_json,created_at,updated_at,deleted_at,version,device_id';
begin
  foreach target in array array[
    'public.sync_entity_snapshot(text,uuid)'::regprocedure,
    'public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure,
    'public.push_book_changes_pre_beta08n0(uuid,jsonb)'::regprocedure,
    'public.upload_initial_snapshot_batch(uuid,text,jsonb)'::regprocedure,
    'public.complete_initial_upload(uuid)'::regprocedure,
    'public.begin_initial_download(uuid)'::regprocedure,
    'public.pull_initial_snapshot_batch(uuid,text,uuid,integer)'::regprocedure
  ] loop
    original := pg_get_functiondef(target);
    original := replace(original, E'\r\n', E'\n');
    definition := replace(original, '''transactions'',''transfer_links''', '''transactions'',''brokerage_settlements'',''transfer_links''');
    definition := replace(definition, '''transactions'', ''transfer_links''', '''transactions'', ''brokerage_settlements'', ''transfer_links''');
    definition := replace(definition, '''import_review_drafts'',''transfer_links''', '''import_review_drafts'',''brokerage_settlements'',''transfer_links''');
    definition := replace(definition, '''import_review_drafts'', ''transfer_links''', '''import_review_drafts'', ''brokerage_settlements'', ''transfer_links''');
    definition := regexp_replace(definition, '''import_review_drafts''\s*,\s*''transfer_links''', '''import_review_drafts'', ''brokerage_settlements'', ''transfer_links''', 'g');
    definition := regexp_replace(definition, '''transactions''\s*,\s*''transfer_links''', '''transactions'', ''brokerage_settlements'', ''transfer_links''', 'g');
    if definition = original then raise exception 'Settlement registry target missing: %', target; end if;
    execute definition;
  end loop;
  foreach target in array array['public.apply_sync_operation_pre_beta08n0(text,text,jsonb,bigint,text)'::regprocedure,'public.apply_initial_snapshot_row_pre_beta08n0(text,jsonb)'::regprocedure] loop
    original := pg_get_functiondef(target);
    definition := replace(original, 'when ''transactions'' then', 'when ''brokerage_settlements'' then columns := ' || quote_literal(columns) || '; when ''transactions'' then');
    if definition = original then raise exception 'Settlement columns target missing: %', target; end if;
    execute definition;
  end loop;
  foreach target in array array['public.push_book_changes_pre_beta08n0(uuid,jsonb)'::regprocedure,'public.initial_sync_allowed_fields_pre_beta08n0(text)'::regprocedure] loop
    original := pg_get_functiondef(target);
    definition := replace(original, 'when ''transactions'' then array[', 'when ''brokerage_settlements'' then string_to_array(' || quote_literal(columns) || ', '','') when ''transactions'' then array[');
    if definition = original then raise exception 'Settlement field target missing: %', target; end if;
    execute definition;
  end loop;
  target := 'public.remote_financial_row_count(uuid)'::regprocedure;
  original := pg_get_functiondef(target);
  definition := replace(original, '(select count(*) from public.transfer_links where book_id = p_book_id)', '(select count(*) from public.brokerage_settlements where book_id = p_book_id) + (select count(*) from public.transfer_links where book_id = p_book_id)');
  if definition = original then raise exception 'Settlement row count target missing'; end if;
  execute definition;
  target := 'public.initial_sync_manifest(uuid,bigint,text,uuid)'::regprocedure;
  original := pg_get_functiondef(target);
  definition := replace(original, '''transfer_links'', (select count(*) from public.transfer_links where book_id = book.id),', '''brokerage_settlements'', (select count(*) from public.brokerage_settlements where book_id = book.id), ''transfer_links'', (select count(*) from public.transfer_links where book_id = book.id),');
  if definition = original then raise exception 'Settlement manifest target missing'; end if;
  execute definition;
end; $$;

-- N0's transaction wrapper must not strip the evidence account reference.
do $$
declare target regprocedure; original text; definition text;
begin
  foreach target in array array['public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure] loop
    original := pg_get_functiondef(target);
    definition := replace(original, 'p_payload - array[', '(case when p_entity_type = ''transactions'' then p_payload else p_payload end) - case when p_entity_type = ''transactions'' then array[');
    definition := replace(definition, E'''split_numerator'', ''split_denominator''\n    ]', E'''split_numerator'', ''split_denominator''\n    ] else array[]::text[] end');
    if definition = original then raise exception 'Settlement wrapper target missing'; end if;
    execute definition;
  end loop;
end; $$;
