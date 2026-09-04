create table public.monthly_category_budgets (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  category_id uuid not null references public.categories(id),
  month_start date not null check (month_start = date_trunc('month', month_start)::date),
  limit_minor bigint not null check (limit_minor > 0),
  currency_code text not null,
  note text check (note is null or length(note) <= 120),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null
);

create index monthly_category_budgets_book_month
  on public.monthly_category_budgets(book_id, month_start);
create index monthly_category_budgets_book_category
  on public.monthly_category_budgets(book_id, category_id);
create index monthly_category_budgets_updated_at
  on public.monthly_category_budgets(updated_at);
create unique index monthly_category_budgets_one_active
  on public.monthly_category_budgets(book_id, category_id, month_start)
  where deleted_at is null;

alter table public.monthly_category_budgets enable row level security;
create policy monthly_category_budgets_member_select
  on public.monthly_category_budgets for select to authenticated
  using (public.is_active_book_member(book_id));
create policy monthly_category_budgets_member_insert
  on public.monthly_category_budgets for insert to authenticated
  with check (public.is_active_book_member(book_id));
create policy monthly_category_budgets_member_update
  on public.monthly_category_budgets for update to authenticated
  using (public.is_active_book_member(book_id))
  with check (public.is_active_book_member(book_id));
create policy monthly_category_budgets_member_delete
  on public.monthly_category_budgets for delete to authenticated
  using (public.is_active_book_member(book_id));

create trigger capture_monthly_category_budgets_change
after insert or update or delete on public.monthly_category_budgets
for each row execute function public.capture_financial_change();
create trigger enforce_initial_sync_monthly_category_budgets
before insert or update on public.monthly_category_budgets
for each row execute function public.enforce_initialized_financial_write();

grant select, insert, update, delete on public.monthly_category_budgets
  to authenticated;

create or replace function public.validate_monthly_category_budget()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' and new.book_id <> old.book_id then
    raise exception 'A monthly budget cannot move to another household.';
  end if;
  if not exists (
    select 1 from public.categories category
    where category.id = new.category_id
      and category.book_id = new.book_id
      and category.category_type = 'expense'
  ) then
    raise exception 'Budget category must be an expense category in the same household.';
  end if;
  if not exists (
    select 1 from public.books book
    where book.id = new.book_id
      and book.base_currency_code = new.currency_code
  ) then
    raise exception 'Budget currency must match the household base currency.';
  end if;
  return new;
end;
$$;
create trigger validate_monthly_category_budget_reference
before insert or update on public.monthly_category_budgets
for each row execute function public.validate_monthly_category_budget();

create or replace function public.beta07a_patch_function(
  p_function regprocedure,
  p_from text,
  p_to text
) returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare definition text;
begin
  select pg_get_functiondef(p_function) into definition;
  if position(p_from in definition) = 0 then
    raise exception 'BETA-07A patch target not found in %', p_function;
  end if;
  execute replace(definition, p_from, p_to);
end;
$$;

select public.beta07a_patch_function(
  'public.sync_entity_snapshot(text,uuid)'::regprocedure,
  '''transactions'', ''asset_definitions''',
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'''
);
select public.beta07a_patch_function(
  'public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure,
  '''transactions'',''asset_definitions'')',
  '''transactions'',''asset_definitions'',''monthly_category_budgets'')'
);
select public.beta07a_patch_function(
  'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,
  'when ''transactions'' then',
  'when ''monthly_category_budgets'' then
    columns := ''id,book_id,category_id,month_start,limit_minor,currency_code,note,created_at,updated_at,deleted_at,version,device_id'';

  when ''transactions'' then'
);
select public.beta07a_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  '''transactions'', ''asset_definitions''',
  '''transactions'', ''asset_definitions'', ''monthly_category_budgets'''
);
select public.beta07a_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''monthly_category_budgets'' then array[
          ''id'',''book_id'',''category_id'',''month_start'',''limit_minor'',''currency_code'',''note'',
          ''created_at'',''updated_at'',''deleted_at'',''version'',''device_id''
        ]
        when ''transactions'' then array['
);
select public.beta07a_patch_function(
  'public.initial_sync_allowed_fields(text)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''monthly_category_budgets'' then array[
      ''id'',''book_id'',''category_id'',''month_start'',''limit_minor'',''currency_code'',''note'',
      ''created_at'',''updated_at'',''deleted_at'',''version'',''device_id''
    ]
    when ''transactions'' then array['
);
select public.beta07a_patch_function(
  'public.remote_financial_row_count(uuid)'::regprocedure,
  '(select count(*) from public.transactions where book_id = p_book_id)',
  '(select count(*) from public.monthly_category_budgets where book_id = p_book_id) +
    (select count(*) from public.transactions where book_id = p_book_id)'
);
select public.beta07a_patch_function(
  'public.initial_sync_manifest(uuid,bigint,text,uuid)'::regprocedure,
  '''transactions'', (select count(*) from public.transactions where book_id = book.id)',
  '''monthly_category_budgets'', (select count(*) from public.monthly_category_budgets where book_id = book.id),
      ''transactions'', (select count(*) from public.transactions where book_id = book.id)'
);
select public.beta07a_patch_function(
  'public.upload_initial_snapshot_batch(uuid,text,jsonb)'::regprocedure,
  '''asset_definitions'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transactions'''
);
select public.beta07a_patch_function(
  'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure,
  'when ''transactions'' then columns :=',
  'when ''monthly_category_budgets'' then columns := ''id,book_id,category_id,month_start,limit_minor,currency_code,note,created_at,updated_at,deleted_at,version,device_id'';
    when ''transactions'' then columns :='
);
select public.beta07a_patch_function(
  'public.complete_initial_upload(uuid)'::regprocedure,
  '''asset_definitions'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transactions'''
);
select public.beta07a_patch_function(
  'public.begin_initial_download(uuid)'::regprocedure,
  '''asset_definitions'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transactions'''
);
select public.beta07a_patch_function(
  'public.pull_initial_snapshot_batch(uuid,text,uuid,integer)'::regprocedure,
  '''asset_definitions'',''transactions''',
  '''asset_definitions'',''monthly_category_budgets'',''transactions'''
);

drop function public.beta07a_patch_function(regprocedure,text,text);
