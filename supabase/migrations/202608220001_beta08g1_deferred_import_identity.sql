alter table public.import_review_drafts
  add column source_row_key text,
  add column deterministic_transaction_account_id uuid
    references public.accounts(id);

update public.import_review_drafts draft
set source_row_key = case session.source_type
  when 'csv' then draft.source_index::text
  when 'receipt' then 'receipt'
  when 'invoice' then 'receipt'
  else null
end,
deterministic_transaction_account_id = session.destination_account_id
from public.import_review_sessions session
where session.id = draft.session_id;

do $$
begin
  if exists (
    select 1 from public.import_review_drafts
    where deterministic_transaction_id is not null
      and deterministic_transaction_account_id is null
  ) then
    raise exception 'BETA-08G draft identity account cannot be proven';
  end if;
end; $$;

alter table public.import_review_drafts
  alter column deterministic_transaction_id drop not null,
  add constraint import_review_drafts_identity_pair check (
    (deterministic_transaction_id is null) =
    (deterministic_transaction_account_id is null)
  );

create or replace function public.validate_import_review_draft()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare parent_session public.import_review_sessions%rowtype;
begin
  select * into parent_session from public.import_review_sessions s
  where s.id = new.session_id and s.book_id = new.book_id;
  if not found then
    raise exception 'Import draft must belong to its session household.';
  end if;
  if tg_op = 'UPDATE' and (
    new.book_id <> old.book_id or new.session_id <> old.session_id or
    new.source_row_identity <> old.source_row_identity or
    new.source_row_key is distinct from old.source_row_key
  ) then raise exception 'Import draft source identity is immutable.'; end if;
  if tg_op = 'UPDATE' and parent_session.state in ('completed','discarded') and (
    new.deterministic_transaction_id is distinct from old.deterministic_transaction_id or
    new.deterministic_transaction_account_id is distinct from old.deterministic_transaction_account_id
  ) then raise exception 'Completed import transaction identity is immutable.'; end if;
  if new.deterministic_transaction_account_id is not null then
    if new.deterministic_transaction_account_id is distinct from parent_session.destination_account_id then
      raise exception 'Import identity account must match the session destination.';
    end if;
    if not exists (
      select 1 from public.accounts a
      where a.id = new.deterministic_transaction_account_id
        and a.book_id = new.book_id and a.deleted_at is null
    ) then
      raise exception 'Import identity account must belong to the household.';
    end if;
  end if;
  if new.deleted_at is null and new.category_id is not null and not exists (
    select 1 from public.categories c where c.id = new.category_id
      and c.book_id = new.book_id
      and c.category_type = new.transaction_type and c.deleted_at is null
  ) then
    raise exception 'Import draft category must match its household and type.';
  end if;
  return new;
end; $$;

create or replace function public.beta08g1_patch_function(
  p_function regprocedure, p_from text, p_to text
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare definition text;
begin
  select pg_get_functiondef(p_function) into definition;
  if position(p_from in definition) = 0 then
    raise exception 'BETA-08G1 patch target not found in %', p_function;
  end if;
  execute replace(definition,p_from,p_to);
end; $$;

select public.beta08g1_patch_function(
  'public.apply_sync_operation(text,text,jsonb,bigint,text)'::regprocedure,
  'id,session_id,book_id,source_row_identity,deterministic_transaction_id,source_index',
  'id,session_id,book_id,source_row_identity,source_row_key,deterministic_transaction_id,deterministic_transaction_account_id,source_index'
);
select public.beta08g1_patch_function(
  'public.push_book_changes(uuid,jsonb)'::regprocedure,
  '''source_row_identity'',''deterministic_transaction_id'',''source_index''',
  '''source_row_identity'',''source_row_key'',''deterministic_transaction_id'',''deterministic_transaction_account_id'',''source_index'''
);
select public.beta08g1_patch_function(
  'public.initial_sync_allowed_fields(text)'::regprocedure,
  '''source_row_identity'',''deterministic_transaction_id'',''source_index''',
  '''source_row_identity'',''source_row_key'',''deterministic_transaction_id'',''deterministic_transaction_account_id'',''source_index'''
);
select public.beta08g1_patch_function(
  'public.apply_initial_snapshot_row(text,jsonb)'::regprocedure,
  'id,session_id,book_id,source_row_identity,deterministic_transaction_id,source_index',
  'id,session_id,book_id,source_row_identity,source_row_key,deterministic_transaction_id,deterministic_transaction_account_id,source_index'
);

drop function public.beta08g1_patch_function(regprocedure,text,text);
