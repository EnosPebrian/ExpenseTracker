create table public.import_review_sessions (
  id uuid primary key,
  book_id uuid not null references public.books(id),
  source_type text not null check (source_type in ('csv','receipt','invoice','bankStatement')),
  title text not null check (length(title) between 1 and 160),
  source_fingerprint text not null,
  destination_account_id uuid references public.accounts(id),
  state text not null check (state in ('pendingReview','readyToCommit','completed','discarded')),
  created_by_member_id uuid references public.household_members(id),
  summary_json text not null default '{}',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  completed_at timestamptz,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null
);

create table public.import_review_drafts (
  id uuid primary key,
  session_id uuid not null references public.import_review_sessions(id),
  book_id uuid not null references public.books(id),
  source_row_identity text not null,
  deterministic_transaction_id uuid not null,
  source_index integer not null,
  transaction_date timestamptz not null,
  description text not null,
  amount_minor bigint not null,
  currency_code text not null check (length(currency_code) = 3),
  transaction_type text not null check (transaction_type in ('expense','income')),
  category_name text not null default '',
  category_id uuid references public.categories(id),
  category_provenance text not null check (category_provenance in ('unresolved','source','rule','manual')),
  reference_text text not null default '',
  note_text text not null default '',
  merchant_hint text not null default '',
  included boolean not null default true,
  user_edited_fields_json text not null default '[]',
  warnings_json text not null default '[]',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  version bigint not null check (version > 0),
  device_id text not null,
  unique(session_id, source_row_identity),
  unique(session_id, deterministic_transaction_id)
);

create index import_review_sessions_book_state on public.import_review_sessions(book_id,state);
create index import_review_sessions_updated on public.import_review_sessions(updated_at);
create index import_review_drafts_session on public.import_review_drafts(session_id);
create index import_review_drafts_book on public.import_review_drafts(book_id);
create index import_review_drafts_transaction on public.import_review_drafts(deterministic_transaction_id);
create index import_review_drafts_updated on public.import_review_drafts(updated_at);

alter table public.import_review_sessions enable row level security;
alter table public.import_review_drafts enable row level security;

create policy import_review_sessions_member_select on public.import_review_sessions
  for select to authenticated using (public.is_active_book_member(book_id));
create policy import_review_sessions_member_insert on public.import_review_sessions
  for insert to authenticated with check (public.is_active_book_member(book_id));
create policy import_review_sessions_member_update on public.import_review_sessions
  for update to authenticated using (public.is_active_book_member(book_id))
  with check (public.is_active_book_member(book_id));
create policy import_review_sessions_member_delete on public.import_review_sessions
  for delete to authenticated using (public.is_active_book_member(book_id));
create policy import_review_drafts_member_select on public.import_review_drafts
  for select to authenticated using (public.is_active_book_member(book_id));
create policy import_review_drafts_member_insert on public.import_review_drafts
  for insert to authenticated with check (public.is_active_book_member(book_id));
create policy import_review_drafts_member_update on public.import_review_drafts
  for update to authenticated using (public.is_active_book_member(book_id))
  with check (public.is_active_book_member(book_id));
create policy import_review_drafts_member_delete on public.import_review_drafts
  for delete to authenticated using (public.is_active_book_member(book_id));

create or replace function public.validate_import_review_session()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' then
    if new.book_id <> old.book_id or new.source_fingerprint <> old.source_fingerprint then
      raise exception 'Import review identity cannot move between households.';
    end if;
    if old.state <> new.state and not (
      (old.state = 'pendingReview' and new.state in ('readyToCommit','discarded')) or
      (old.state = 'readyToCommit' and new.state = 'completed')
    ) then
      raise exception 'Invalid import review lifecycle transition.';
    end if;
  end if;
  if new.state <> 'discarded' and new.destination_account_id is not null and not exists (
    select 1 from public.accounts a where a.id = new.destination_account_id
      and a.book_id = new.book_id and a.deleted_at is null
  ) then raise exception 'Import destination account must belong to the household.'; end if;
  if new.state <> 'discarded' and new.created_by_member_id is not null and not exists (
    select 1 from public.household_members m where m.id = new.created_by_member_id
      and m.book_id = new.book_id and m.deleted_at is null
  ) then raise exception 'Import creator must belong to the household.'; end if;
  return new;
end; $$;

create or replace function public.validate_import_review_draft()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' and (
    new.book_id <> old.book_id or new.session_id <> old.session_id or
    new.source_row_identity <> old.source_row_identity or
    new.deterministic_transaction_id <> old.deterministic_transaction_id
  ) then raise exception 'Import draft identity is immutable.'; end if;
  if not exists (select 1 from public.import_review_sessions s
    where s.id = new.session_id and s.book_id = new.book_id) then
    raise exception 'Import draft must belong to its session household.';
  end if;
  if new.deleted_at is null and new.category_id is not null and not exists (select 1 from public.categories c
    where c.id = new.category_id and c.book_id = new.book_id
      and c.category_type = new.transaction_type and c.deleted_at is null) then
    raise exception 'Import draft category must match its household and type.';
  end if;
  return new;
end; $$;

create trigger validate_import_review_session_reference before insert or update
on public.import_review_sessions for each row execute function public.validate_import_review_session();
create trigger validate_import_review_draft_reference before insert or update
on public.import_review_drafts for each row execute function public.validate_import_review_draft();
create trigger capture_import_review_sessions_change after insert or update or delete
on public.import_review_sessions for each row execute function public.capture_financial_change();
create trigger capture_import_review_drafts_change after insert or update or delete
on public.import_review_drafts for each row execute function public.capture_financial_change();
create trigger enforce_initial_sync_import_review_sessions before insert or update
on public.import_review_sessions for each row execute function public.enforce_initialized_financial_write();
create trigger enforce_initial_sync_import_review_drafts before insert or update
on public.import_review_drafts for each row execute function public.enforce_initialized_financial_write();
grant select,insert,update,delete on public.import_review_sessions to authenticated;
grant select,insert,update,delete on public.import_review_drafts to authenticated;

create or replace function public.beta08g_patch_function(
  p_function regprocedure, p_from text, p_to text
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare definition text;
begin
  select pg_get_functiondef(p_function) into definition;
  if position(p_from in definition) = 0 then
    raise exception 'BETA-08G patch target not found in %', p_function;
  end if;
  execute replace(definition,p_from,p_to);
end; $$;

select public.beta08g_patch_function(
  'public.sync_entity_snapshot(text,uuid)'::regprocedure,
  '''transaction_import_rules'', ''transfer_links''',
  '''transaction_import_rules'', ''import_review_sessions'', ''import_review_drafts'', ''transfer_links'''
);
select public.beta08g_patch_function(
  'public.resolve_sync_conflict(uuid,text,uuid,bigint,uuid,text,jsonb)'::regprocedure,
  '''transaction_import_rules'',''transfer_links'')',
  '''transaction_import_rules'',''import_review_sessions'',''import_review_drafts'',''transfer_links'')'
);
select public.beta08g_patch_function(
  'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,
  'when ''transactions'' then',
  'when ''import_review_sessions'' then columns := ''id,book_id,source_type,title,source_fingerprint,destination_account_id,state,created_by_member_id,summary_json,created_at,updated_at,completed_at,deleted_at,version,device_id'';
   when ''import_review_drafts'' then columns := ''id,session_id,book_id,source_row_identity,deterministic_transaction_id,source_index,transaction_date,description,amount_minor,currency_code,transaction_type,category_name,category_id,category_provenance,reference_text,note_text,merchant_hint,included,user_edited_fields_json,warnings_json,created_at,updated_at,deleted_at,version,device_id'';
   when ''transactions'' then'
);
select public.beta08g_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  '''transaction_import_rules'', ''transfer_links''',
  '''transaction_import_rules'', ''import_review_sessions'', ''import_review_drafts'', ''transfer_links'''
);
select public.beta08g_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''import_review_sessions'' then array[''id'',''book_id'',''source_type'',''title'',''source_fingerprint'',''destination_account_id'',''state'',''created_by_member_id'',''summary_json'',''created_at'',''updated_at'',''completed_at'',''deleted_at'',''version'',''device_id'']
   when ''import_review_drafts'' then array[''id'',''session_id'',''book_id'',''source_row_identity'',''deterministic_transaction_id'',''source_index'',''transaction_date'',''description'',''amount_minor'',''currency_code'',''transaction_type'',''category_name'',''category_id'',''category_provenance'',''reference_text'',''note_text'',''merchant_hint'',''included'',''user_edited_fields_json'',''warnings_json'',''created_at'',''updated_at'',''deleted_at'',''version'',''device_id'']
   when ''transactions'' then array['
);
select public.beta08g_patch_function(
  'public.initial_sync_allowed_fields(text)'::regprocedure,
  'when ''transactions'' then array[',
  'when ''import_review_sessions'' then array[''id'',''book_id'',''source_type'',''title'',''source_fingerprint'',''destination_account_id'',''state'',''created_by_member_id'',''summary_json'',''created_at'',''updated_at'',''completed_at'',''deleted_at'',''version'',''device_id'']
   when ''import_review_drafts'' then array[''id'',''session_id'',''book_id'',''source_row_identity'',''deterministic_transaction_id'',''source_index'',''transaction_date'',''description'',''amount_minor'',''currency_code'',''transaction_type'',''category_name'',''category_id'',''category_provenance'',''reference_text'',''note_text'',''merchant_hint'',''included'',''user_edited_fields_json'',''warnings_json'',''created_at'',''updated_at'',''deleted_at'',''version'',''device_id'']
   when ''transactions'' then array['
);
select public.beta08g_patch_function(
  'public.remote_financial_row_count(uuid)'::regprocedure,
  '(select count(*) from public.transfer_links where book_id = p_book_id) +',
  '(select count(*) from public.import_review_sessions where book_id = p_book_id) +
   (select count(*) from public.import_review_drafts where book_id = p_book_id) +
   (select count(*) from public.transfer_links where book_id = p_book_id) +'
);
select public.beta08g_patch_function(
  'public.initial_sync_manifest(uuid,bigint,text,uuid)'::regprocedure,
  '''transfer_links'', (select count(*) from public.transfer_links where book_id = book.id),',
  '''import_review_sessions'', (select count(*) from public.import_review_sessions where book_id = book.id),
   ''import_review_drafts'', (select count(*) from public.import_review_drafts where book_id = book.id),
   ''transfer_links'', (select count(*) from public.transfer_links where book_id = book.id),'
);
select public.beta08g_patch_function(
  'public.upload_initial_snapshot_batch(uuid,text,jsonb)'::regprocedure,
  '''transactions'',''transfer_links''',
  '''import_review_sessions'',''import_review_drafts'',''transactions'',''transfer_links'''
);
select public.beta08g_patch_function(
  'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure,
  'when ''transactions'' then columns :=',
  'when ''import_review_sessions'' then columns := ''id,book_id,source_type,title,source_fingerprint,destination_account_id,state,created_by_member_id,summary_json,created_at,updated_at,completed_at,deleted_at,version,device_id'';
   when ''import_review_drafts'' then columns := ''id,session_id,book_id,source_row_identity,deterministic_transaction_id,source_index,transaction_date,description,amount_minor,currency_code,transaction_type,category_name,category_id,category_provenance,reference_text,note_text,merchant_hint,included,user_edited_fields_json,warnings_json,created_at,updated_at,deleted_at,version,device_id'';
   when ''transactions'' then columns :='
);
select public.beta08g_patch_function('public.complete_initial_upload(uuid)'::regprocedure,
  '''transactions'',''transfer_links''','''import_review_sessions'',''import_review_drafts'',''transactions'',''transfer_links''');
select public.beta08g_patch_function('public.begin_initial_download(uuid)'::regprocedure,
  '''transactions'',''transfer_links''','''import_review_sessions'',''import_review_drafts'',''transactions'',''transfer_links''');
select public.beta08g_patch_function('public.pull_initial_snapshot_batch(uuid,text,uuid,integer)'::regprocedure,
  '''transactions'',''transfer_links''','''import_review_sessions'',''import_review_drafts'',''transactions'',''transfer_links''');

drop function public.beta08g_patch_function(regprocedure,text,text);
