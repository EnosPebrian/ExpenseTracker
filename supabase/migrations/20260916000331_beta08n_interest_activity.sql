-- Extend the existing authoritative brokerage transaction contract with one
-- positive, non-instrument investment cash activity. No new table or authority.
alter table public.transactions
  drop constraint transactions_brokerage_activity_type,
  add constraint transactions_brokerage_activity_type check (
    brokerage_activity_type is null or brokerage_activity_type in (
      'buy', 'sell', 'dividend', 'interest', 'fee', 'tax',
      'deposit', 'withdrawal', 'split'
    )
  );

create or replace function public.validate_transaction_brokerage_reference()
returns trigger language plpgsql
security invoker
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
    or (new.brokerage_activity_type in ('dividend', 'interest', 'fee', 'tax')
      and (new.transaction_type <> 'investment' or new.amount <= 0
        or new.asset_action is not null))
    or (new.brokerage_activity_type = 'interest'
      and new.asset_definition_id is not null)
    or (new.brokerage_activity_type = 'deposit'
      and new.transaction_type <> 'income')
    or (new.brokerage_activity_type = 'withdrawal'
      and new.transaction_type <> 'expense') then
    raise exception 'Brokerage activity does not match its authoritative transaction';
  end if;
  return new;
end;
$$;

revoke execute on function public.validate_transaction_brokerage_reference()
  from public, anon, authenticated;
