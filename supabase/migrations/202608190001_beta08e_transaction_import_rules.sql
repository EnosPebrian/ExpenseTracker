create table public.transaction_import_rules (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  name text not null check (length(name) between 1 and 80),
  enabled boolean not null default true,
  priority integer not null default 0,
  transaction_type text not null check (transaction_type in ('expense', 'income')),
  match_field text not null check (match_field in ('description', 'reference', 'merchantHint', 'descriptionOrReference')),
  match_operator text not null check (match_operator in ('contains', 'equals', 'startsWith')),
  pattern text not null check (length(pattern) between 1 and 160),
  pattern_key text not null,
  account_id uuid references public.accounts(id),
  category_id uuid not null references public.categories(id),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null
);

create index transaction_import_rules_book_priority
  on public.transaction_import_rules(book_id, enabled, priority desc);
create index transaction_import_rules_updated_at
  on public.transaction_import_rules(updated_at);
create index transaction_import_rules_book_type
  on public.transaction_import_rules(book_id, transaction_type);
create index transaction_import_rules_book_category
  on public.transaction_import_rules(book_id, category_id);
create index transaction_import_rules_book_account
  on public.transaction_import_rules(book_id, account_id);
create unique index transaction_import_rules_one_active_semantic
  on public.transaction_import_rules(
    book_id, transaction_type, match_field, match_operator, pattern_key,
    coalesce(account_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) where deleted_at is null;

alter table public.transaction_import_rules enable row level security;
create policy transaction_import_rules_member_select
  on public.transaction_import_rules for select to authenticated
  using (public.is_active_book_member(book_id));
create policy transaction_import_rules_member_insert
  on public.transaction_import_rules for insert to authenticated
  with check (public.is_active_book_member(book_id));
create policy transaction_import_rules_member_update
  on public.transaction_import_rules for update to authenticated
  using (public.is_active_book_member(book_id))
  with check (public.is_active_book_member(book_id));
create policy transaction_import_rules_member_delete
  on public.transaction_import_rules for delete to authenticated
  using (public.is_active_book_member(book_id));

create trigger capture_transaction_import_rules_change
after insert or update or delete on public.transaction_import_rules
for each row execute function public.capture_financial_change();
create trigger enforce_initial_sync_transaction_import_rules
before insert or update on public.transaction_import_rules
for each row execute function public.enforce_initialized_financial_write();

grant select, insert, update, delete on public.transaction_import_rules to authenticated;

create or replace function public.validate_transaction_import_rule()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' and new.book_id <> old.book_id then
    raise exception 'An import rule cannot move to another household.';
  end if;
  if not exists (
    select 1 from public.categories category
    where category.id = new.category_id
      and category.book_id = new.book_id
      and category.category_type = new.transaction_type
  ) then
    raise exception 'Import rule category must match household and transaction type.';
  end if;
  if new.account_id is not null and not exists (
    select 1 from public.accounts account
    where account.id = new.account_id and account.book_id = new.book_id
  ) then
    raise exception 'Import rule account must belong to the same household.';
  end if;
  return new;
end;
$$;
create trigger validate_transaction_import_rule_reference
before insert or update on public.transaction_import_rules
for each row execute function public.validate_transaction_import_rule();

create or replace function public.beta08e_patch_function(
  p_function regprocedure, p_from text, p_to text
) returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare definition text;
begin
  select pg_get_functiondef(p_function) into definition;
  if position(p_from in definition) = 0 then
    raise exception 'BETA-08E patch target not found in %', p_function;
  end if;
  execute replace(definition, p_from, p_to);
end;
$$;

select public.beta08e_patch_function(
  'public.sync_entity_snapshot(text,uuid)'::regprocedure,
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets''',
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'', ''transaction_import_rules'''
);
select public.beta08e_patch_function(
  'public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure,
  '''transactions'',''asset_definitions'',''monthly_category_budgets'')',
  '''transactions'',''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'')'
);
select public.beta08e_patch_function(
  'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,
  'when ''transactions'' then',
  'when ''transaction_import_rules'' then
    columns := ''id,book_id,name,enabled,priority,transaction_type,match_field,match_operator,pattern,pattern_key,account_id,category_id,created_at,updated_at,deleted_at,version,device_id'';
  when ''transactions'' then'
);
select public.beta08e_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets''',
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'', ''transaction_import_rules'''
);
select public.beta08e_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''transaction_import_rules'' then array[
    ''id'',''book_id'',''name'',''enabled'',''priority'',''transaction_type'',''match_field'',''match_operator'',
    ''pattern'',''pattern_key'',''account_id'',''category_id'',''created_at'',''updated_at'',''deleted_at'',''version'',''device_id''
  ]
  when ''transactions'' then array['
);
select public.beta08e_patch_function(
  'public.initial_sync_allowed_fields(text)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''transaction_import_rules'' then array[
    ''id'',''book_id'',''name'',''enabled'',''priority'',''transaction_type'',''match_field'',''match_operator'',
    ''pattern'',''pattern_key'',''account_id'',''category_id'',''created_at'',''updated_at'',''deleted_at'',''version'',''device_id''
  ]
  when ''transactions'' then array['
);
select public.beta08e_patch_function(
  'public.remote_financial_row_count(uuid)'::regprocedure,
  '(select count(*) from public.monthly_category_budgets where book_id = p_book_id) +',
  '(select count(*) from public.transaction_import_rules where book_id = p_book_id) +
   (select count(*) from public.monthly_category_budgets where book_id = p_book_id) +'
);
select public.beta08e_patch_function(
  'public.initial_sync_manifest(uuid,bigint,text,uuid)'::regprocedure,
  '''monthly_category_budgets'', (select count(*) from public.monthly_category_budgets where book_id = book.id),',
  '''monthly_category_budgets'', (select count(*) from public.monthly_category_budgets where book_id = book.id),
   ''transaction_import_rules'', (select count(*) from public.transaction_import_rules where book_id = book.id),'
);
select public.beta08e_patch_function(
  'public.upload_initial_snapshot_batch(uuid,text,jsonb)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'''
);
select public.beta08e_patch_function(
  'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure,
  'when ''transactions'' then columns :=',
  'when ''transaction_import_rules'' then columns := ''id,book_id,name,enabled,priority,transaction_type,match_field,match_operator,pattern,pattern_key,account_id,category_id,created_at,updated_at,deleted_at,version,device_id'';
   when ''transactions'' then columns :='
);
select public.beta08e_patch_function(
  'public.complete_initial_upload(uuid)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'''
);
select public.beta08e_patch_function(
  'public.begin_initial_download(uuid)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'''
);
select public.beta08e_patch_function(
  'public.pull_initial_snapshot_batch(uuid,text,uuid,integer)'::regprocedure,
  '''asset_definitions'',''monthly_category_budgets'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transaction_import_rules'',''transactions'''
);

drop function public.beta08e_patch_function(regprocedure,text,text);
