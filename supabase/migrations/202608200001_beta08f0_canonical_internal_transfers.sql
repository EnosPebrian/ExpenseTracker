create table public.transfer_links (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  outgoing_transaction_id uuid not null references public.transactions(id),
  incoming_transaction_id uuid not null references public.transactions(id),
  source_account_id uuid not null references public.accounts(id),
  destination_account_id uuid not null references public.accounts(id),
  currency_code text not null check (length(currency_code) = 3),
  amount bigint not null check (amount > 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null,
  check (outgoing_transaction_id <> incoming_transaction_id),
  check (source_account_id <> destination_account_id)
);

create index transfer_links_book on public.transfer_links(book_id);
create index transfer_links_updated_at on public.transfer_links(updated_at);
create unique index transfer_links_one_active_outgoing
  on public.transfer_links(outgoing_transaction_id) where deleted_at is null;
create unique index transfer_links_one_active_incoming
  on public.transfer_links(incoming_transaction_id) where deleted_at is null;

alter table public.transfer_links enable row level security;
create policy transfer_links_member_select on public.transfer_links
  for select to authenticated using (public.is_active_book_member(book_id));
create policy transfer_links_member_insert on public.transfer_links
  for insert to authenticated with check (public.is_active_book_member(book_id));
create policy transfer_links_member_update on public.transfer_links
  for update to authenticated using (public.is_active_book_member(book_id))
  with check (public.is_active_book_member(book_id));
create policy transfer_links_member_delete on public.transfer_links
  for delete to authenticated using (public.is_active_book_member(book_id));

create or replace function public.validate_transfer_link()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  outgoing public.transactions%rowtype;
  incoming public.transactions%rowtype;
  source_account public.accounts%rowtype;
  destination_account public.accounts%rowtype;
begin
  if tg_op = 'UPDATE' and (
    new.book_id <> old.book_id or
    new.outgoing_transaction_id <> old.outgoing_transaction_id or
    new.incoming_transaction_id <> old.incoming_transaction_id
  ) then
    raise exception 'Transfer relation identity and direction are immutable.';
  end if;
  if new.deleted_at is not null then return new; end if;

  select * into outgoing from public.transactions
    where id = new.outgoing_transaction_id;
  select * into incoming from public.transactions
    where id = new.incoming_transaction_id;
  select * into source_account from public.accounts
    where id = new.source_account_id;
  select * into destination_account from public.accounts
    where id = new.destination_account_id;

  if outgoing.id is null or incoming.id is null or
     source_account.id is null or destination_account.id is null or
     outgoing.book_id <> new.book_id or incoming.book_id <> new.book_id or
     source_account.book_id <> new.book_id or
     destination_account.book_id <> new.book_id or
     outgoing.deleted_at is not null or incoming.deleted_at is not null or
     source_account.deleted_at is not null or
     destination_account.deleted_at is not null or
     outgoing.transaction_type <> 'expense' or
     incoming.transaction_type <> 'income' or
     outgoing.amount <> new.amount or incoming.amount <> new.amount or
     lower(trim(outgoing.account)) <> lower(trim(source_account.name)) or
     lower(trim(incoming.account)) <> lower(trim(destination_account.name)) or
     source_account.currency_code <> destination_account.currency_code or
     source_account.currency_code <> new.currency_code then
    raise exception 'Canonical internal transfer relation is invalid.';
  end if;
  return new;
end;
$$;

create trigger validate_transfer_link_reference
before insert or update on public.transfer_links
for each row execute function public.validate_transfer_link();
create trigger capture_transfer_links_change
after insert or update or delete on public.transfer_links
for each row execute function public.capture_financial_change();
create trigger enforce_initial_sync_transfer_links
before insert or update on public.transfer_links
for each row execute function public.enforce_initialized_financial_write();
grant select, insert, update, delete on public.transfer_links to authenticated;

create or replace function public.beta08f0_patch_function(
  p_function regprocedure, p_from text, p_to text
) returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare definition text;
begin
  select pg_get_functiondef(p_function) into definition;
  if position(p_from in definition) = 0 then
    raise exception 'BETA-08F0 patch target not found in %', p_function;
  end if;
  execute replace(definition, p_from, p_to);
end;
$$;

select public.beta08f0_patch_function(
  'public.sync_entity_snapshot(text,uuid)'::regprocedure,
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'', ''transaction_import_rules''',
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'', ''transaction_import_rules'', ''transfer_links'''
);
select public.beta08f0_patch_function(
  'public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure,
  '''transactions'',''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'')',
  '''transactions'',''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transfer_links'')'
);
select public.beta08f0_patch_function(
  'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,
  'when ''transactions'' then',
  'when ''transfer_links'' then
    columns := ''id,book_id,outgoing_transaction_id,incoming_transaction_id,source_account_id,destination_account_id,currency_code,amount,created_at,updated_at,deleted_at,version,device_id'';
  when ''transactions'' then'
);
select public.beta08f0_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'', ''transaction_import_rules''',
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'', ''transaction_import_rules'', ''transfer_links'''
);
select public.beta08f0_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''transfer_links'' then array[
    ''id'',''book_id'',''outgoing_transaction_id'',''incoming_transaction_id'',''source_account_id'',
    ''destination_account_id'',''currency_code'',''amount'',''created_at'',''updated_at'',
    ''deleted_at'',''version'',''device_id''
  ]
  when ''transactions'' then array['
);
select public.beta08f0_patch_function(
  'public.initial_sync_allowed_fields(text)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''transfer_links'' then array[
    ''id'',''book_id'',''outgoing_transaction_id'',''incoming_transaction_id'',''source_account_id'',
    ''destination_account_id'',''currency_code'',''amount'',''created_at'',''updated_at'',
    ''deleted_at'',''version'',''device_id''
  ]
  when ''transactions'' then array['
);
select public.beta08f0_patch_function(
  'public.remote_financial_row_count(uuid)'::regprocedure,
  '(select count(*) from public.transaction_import_rules where book_id = p_book_id) +',
  '(select count(*) from public.transfer_links where book_id = p_book_id) +
   (select count(*) from public.transaction_import_rules where book_id = p_book_id) +'
);
select public.beta08f0_patch_function(
  'public.initial_sync_manifest(uuid,bigint,text,uuid)'::regprocedure,
  '''transaction_import_rules'', (select count(*) from public.transaction_import_rules where book_id = book.id),',
  '''transaction_import_rules'', (select count(*) from public.transaction_import_rules where book_id = book.id),
   ''transfer_links'', (select count(*) from public.transfer_links where book_id = book.id),'
);
select public.beta08f0_patch_function(
  'public.upload_initial_snapshot_batch(uuid,text,jsonb)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'',''transfer_links'''
);
select public.beta08f0_patch_function(
  'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure,
  'when ''transactions'' then columns :=',
  'when ''transfer_links'' then columns := ''id,book_id,outgoing_transaction_id,incoming_transaction_id,source_account_id,destination_account_id,currency_code,amount,created_at,updated_at,deleted_at,version,device_id'';
   when ''transactions'' then columns :='
);
select public.beta08f0_patch_function(
  'public.complete_initial_upload(uuid)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'',''transfer_links'''
);
select public.beta08f0_patch_function(
  'public.begin_initial_download(uuid)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'',''transfer_links'''
);
select public.beta08f0_patch_function(
  'public.pull_initial_snapshot_batch(uuid,text,uuid,integer)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'',''transfer_links'''
);

drop function public.beta08f0_patch_function(regprocedure,text,text);
