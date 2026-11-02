-- Monee, stage 4: transactions.
--
-- Every income and expense moves one account; a transfer moves money from one
-- account to another (and may carry a fee). Amounts are in the account's own
-- currency. `rate` is how much of the main currency one unit was worth when
-- the entry was made: totals and stats use it, so old months never change
-- when today's rate does.
--
-- Two views hold the arithmetic, and everything else reads them:
--   account_moves  what each transaction does to each account's balance
--   entries        what counts as income and expense, after the book's rules:
--                  card spending as a lump on payment day, Transfer-Expense
--                  accounts, transfer fees.

create table public.txns (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  kind            text not null check (kind in ('income', 'expense', 'transfer')),
  at              timestamp not null,                 -- the book's own wall clock
  account_id      uuid not null references public.accounts (id) on delete cascade,
  to_account_id   uuid references public.accounts (id) on delete cascade,
  category_id     uuid references public.categories (id) on delete set null,
  amount          numeric(20, 4) not null check (amount > 0),
  to_amount       numeric(20, 4) check (to_amount > 0),       -- transfers: what arrived, in the other account's currency
  fee             numeric(20, 4) not null default 0 check (fee >= 0),
  currency        text,
  rate            numeric(24, 10) check (rate > 0),
  note            text check (char_length(note) <= 120),
  description     text check (char_length(description) <= 2000),
  repeat_id       uuid,
  plan_id         uuid,
  plan_no         int,
  pays_cycle      date,                                 -- automatic card payments: the payment day they cover
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index txns_book_at on public.txns (book_id, at);
create index txns_account on public.txns (account_id, at);
create index txns_to_account on public.txns (to_account_id, at) where to_account_id is not null;
create index txns_category on public.txns (category_id) where category_id is not null;
create index txns_note on public.txns using gin (note extensions.gin_trgm_ops);

-- One shop, several categories.
create table public.txn_splits (
  id           uuid primary key default gen_random_uuid(),
  book_id      uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  txn_id       uuid not null references public.txns (id) on delete cascade,
  category_id  uuid references public.categories (id) on delete set null,
  amount       numeric(20, 4) not null check (amount > 0),
  note         text check (char_length(note) <= 120)
);
create index txn_splits_txn on public.txn_splits (txn_id);

create table public.txn_tags (
  book_id  uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  txn_id   uuid not null references public.txns (id) on delete cascade,
  tag_id   uuid not null references public.tags (id) on delete cascade,
  primary key (txn_id, tag_id)
);
create index txn_tags_tag on public.txn_tags (tag_id);

create table public.txn_photos (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  txn_id      uuid not null references public.txns (id) on delete cascade,
  path        text not null,                          -- the file in storage (bucket monee-photos)
  created_at  timestamptz not null default now()
);
create index txn_photos_txn on public.txn_photos (txn_id);

-- ---------------------------------------------------------------- rules

create or replace function public.txns_check() returns trigger
language plpgsql set search_path = '' as $$
declare a record; t record; c record; main text;
begin
  select x.book_id, x.currency, x.deleted_at, public.account_kind(x.id) as kind into a from public.accounts x where x.id = new.account_id;
  if a.book_id is distinct from new.book_id then
    raise exception 'That account is in another book.' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and new.book_id is distinct from old.book_id then
    raise exception 'A transaction cannot move between books.' using errcode = '42501';
  end if;
  if a.deleted_at is not null and not public.trusted_writer()
     and (tg_op = 'INSERT' or new.account_id is distinct from old.account_id) then
    raise exception 'That account is deleted. Restore it first.' using errcode = '22023';
  end if;
  main := (select b.currency from public.books b where b.id = new.book_id);
  new.note := nullif(btrim(coalesce(new.note, '')), '');
  new.description := nullif(btrim(coalesce(new.description, '')), '');
  new.currency := a.currency;

  if new.kind = 'transfer' then
    if new.to_account_id is null then
      raise exception 'Pick the account the money goes to.' using errcode = '22023';
    end if;
    select x.book_id, x.currency, x.deleted_at into t from public.accounts x where x.id = new.to_account_id;
    if t.book_id is distinct from new.book_id then
      raise exception 'That account is in another book.' using errcode = '22023';
    end if;
    if new.to_account_id = new.account_id then
      raise exception 'A transfer goes to a different account.' using errcode = '22023';
    end if;
    if t.deleted_at is not null and not public.trusted_writer()
       and (tg_op = 'INSERT' or new.to_account_id is distinct from old.to_account_id) then
      raise exception 'That account is deleted. Restore it first.' using errcode = '22023';
    end if;
    new.category_id := null;
    if t.currency = a.currency then
      new.to_amount := new.amount;
    elsif new.to_amount is null then
      -- Worked out from the rates when the app did not say.
      new.to_amount := round(new.amount * public.rate_of(new.book_id, a.currency) / nullif(public.rate_of(new.book_id, t.currency), 0), 4);
      if new.to_amount is null then
        raise exception 'Say how much arrived in %, or add its exchange rate.', t.currency using errcode = '22023';
      end if;
    end if;
  else
    new.to_account_id := null;
    new.to_amount := null;
    new.fee := 0;
    if new.category_id is not null then
      select x.book_id, x.kind into c from public.categories x where x.id = new.category_id;
      if c.book_id is distinct from new.book_id or c.kind <> new.kind then
        raise exception 'Pick an % category.', new.kind using errcode = '22023';
      end if;
    end if;
  end if;

  if new.currency = main then
    new.rate := 1;
  elsif new.rate is null or (tg_op = 'UPDATE' and new.currency is distinct from old.currency and new.rate = old.rate) then
    new.rate := public.rate_of(new.book_id, new.currency);
    if new.rate is null then
      raise exception 'Add the exchange rate for % first.', new.currency using errcode = '22023';
    end if;
  end if;
  new.updated_at := now();
  if tg_op = 'UPDATE' and not public.trusted_writer() then
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
create trigger txns_check before insert or update on public.txns
  for each row execute function public.txns_check();

create or replace function public.txn_parts_check() returns trigger
language plpgsql set search_path = '' as $$
declare t record;
begin
  select x.book_id, x.kind into t from public.txns x where x.id = new.txn_id;
  if t.book_id is distinct from new.book_id then
    raise exception 'That transaction is in another book.' using errcode = '22023';
  end if;
  if tg_table_name = 'txn_splits' then
    if t.kind = 'transfer' then
      raise exception 'Only income and expenses can be split.' using errcode = '22023';
    end if;
    if new.category_id is not null and not exists (
        select 1 from public.categories c where c.id = new.category_id and c.book_id = new.book_id and c.kind = t.kind) then
      raise exception 'Pick an % category for each part.', t.kind using errcode = '22023';
    end if;
  elsif tg_table_name = 'txn_tags' then
    if not exists (select 1 from public.tags g where g.id = new.tag_id and g.book_id = new.book_id) then
      raise exception 'That tag is in another book.' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger txn_splits_check before insert or update on public.txn_splits
  for each row execute function public.txn_parts_check();
create trigger txn_tags_check before insert or update on public.txn_tags
  for each row execute function public.txn_parts_check();
create trigger txn_photos_check before insert or update on public.txn_photos
  for each row execute function public.txn_parts_check();

-- The parts of a split always add up to the whole.
create or replace function public.txn_splits_total() returns trigger
language plpgsql set search_path = '' as $$
declare v_txn uuid; total numeric; parts numeric;
begin
  v_txn := case when tg_table_name = 'txns' then new.id else coalesce(new.txn_id, old.txn_id) end;
  select x.amount into total from public.txns x where x.id = v_txn;
  if total is null then return null; end if;   -- the transaction itself is going
  select sum(s.amount) into parts from public.txn_splits s where s.txn_id = v_txn;
  if parts is not null and parts <> total then
    raise exception 'The parts add up to %, not %.', parts, total using errcode = '22023';
  end if;
  return null;
end $$;
create constraint trigger txn_splits_total after insert or update or delete on public.txn_splits
  deferrable initially deferred for each row execute function public.txn_splits_total();
create constraint trigger txn_amount_vs_splits after update of amount on public.txns
  deferrable initially deferred for each row execute function public.txn_splits_total();

-- ---------------------------------------------------------------- row level security

do $$
declare t text;
begin
  foreach t in array array['txns', 'txn_splits', 'txn_tags', 'txn_photos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (book_id = (select public.current_book_id()))', t || '_read', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit())) with check (book_id = (select public.current_book_id()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_delete', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- the arithmetic

-- What each transaction does to each account's balance, in that account's
-- currency. A debit card's spending lands on the account it is linked to.
create or replace view public.account_moves with (security_invoker = true) as
  select t.book_id, t.id as txn_id, t.at, coalesce(a.linked_account_id, a.id) as account_id, t.account_id as via_account_id,
         case t.kind when 'income' then t.amount else -(t.amount + t.fee) end as delta
    from public.txns t join public.accounts a on a.id = t.account_id
  union all
  select t.book_id, t.id, t.at, coalesce(a.linked_account_id, a.id), t.to_account_id, t.to_amount
    from public.txns t join public.accounts a on a.id = t.to_account_id
   where t.kind = 'transfer';

-- The lines of an income or expense: its split parts, or itself.
create or replace view public.txn_lines with (security_invoker = true) as
  select t.id as txn_id, s.category_id, s.amount, coalesce(s.note, t.note) as note
    from public.txns t join public.txn_splits s on s.txn_id = t.id
   where t.kind <> 'transfer'
  union all
  select t.id, t.category_id, t.amount, t.note
    from public.txns t
   where t.kind <> 'transfer' and not exists (select 1 from public.txn_splits s where s.txn_id = t.id);

-- What counts as income and expense, in the main currency.
--   special: null (a category's line), 'transfer' (into or out of a
--   Transfer-Expense account), 'card' (a card paid off, when card spending
--   counts as a lump), 'fee' (a transfer's fee).
create or replace view public.entries with (security_invoker = true) as
  -- Income and expenses. Card spending waits for payment day when the book says so.
  select t.book_id, t.id as txn_id, t.at, t.at::date as day, t.kind, l.category_id, null::text as special,
         t.account_id, l.amount, round(l.amount * t.rate, 4) as amount_main, l.note
    from public.txns t
    join public.txn_lines l on l.txn_id = t.id
    join public.books b on b.id = t.book_id
   where not (t.kind = 'expense' and b.card_display = 'lump_sum' and public.account_kind(t.account_id) = 'card')
  union all
  -- Into a Transfer-Expense account (savings, insurance, investment, loan): an expense.
  -- Paying a card off, when card spending counts as a lump: an expense.
  select t.book_id, t.id, t.at, t.at::date, 'expense', null, case when d.transfer_expense then 'transfer' else 'card' end,
         t.account_id, t.amount, round(t.amount * t.rate, 4), t.note
    from public.txns t
    join public.accounts d on d.id = t.to_account_id
    join public.accounts s on s.id = t.account_id
    join public.books b on b.id = t.book_id
   where t.kind = 'transfer'
     and ((d.transfer_expense and not s.transfer_expense)
       or (b.card_display = 'lump_sum' and public.account_kind(d.id) = 'card' and public.account_kind(s.id) <> 'card'))
  union all
  -- Out of a Transfer-Expense account back into ordinary money: income.
  select t.book_id, t.id, t.at, t.at::date, 'income', null, 'transfer',
         t.account_id, t.amount, round(t.amount * t.rate, 4), t.note
    from public.txns t
    join public.accounts s on s.id = t.account_id
    join public.accounts d on d.id = t.to_account_id
   where t.kind = 'transfer' and s.transfer_expense and not d.transfer_expense
  union all
  -- Transfer fees.
  select t.book_id, t.id, t.at, t.at::date, 'expense', null, 'fee',
         t.account_id, t.fee, round(t.fee * t.rate, 4), t.note
    from public.txns t
   where t.kind = 'transfer' and t.fee > 0;

-- ---------------------------------------------------------------- writing a transaction

-- One call for the whole entry: the transaction, its split parts and its tags
-- (by name; new names become tags). With id it changes that transaction.
-- Runs as the caller, so row level security decides as for any write.
create or replace function public.save_txn(p jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; r public.txns%rowtype; tag text; tid uuid; part jsonb;
begin
  if not public.can_edit() then raise exception 'You can only look at this book.' using errcode = '42501'; end if;
  if v_id is null then
    insert into public.txns (kind, at, account_id, to_account_id, category_id, amount, to_amount, fee, rate, note, description, repeat_id, plan_id, plan_no)
    values (p ->> 'kind', coalesce((p ->> 'at')::timestamp, public.book_now(public.current_book_id())),
            (p ->> 'account_id')::uuid, nullif(p ->> 'to_account_id', '')::uuid, nullif(p ->> 'category_id', '')::uuid,
            (p ->> 'amount')::numeric, nullif(p ->> 'to_amount', '')::numeric, coalesce(nullif(p ->> 'fee', '')::numeric, 0),
            nullif(p ->> 'rate', '')::numeric, p ->> 'note', p ->> 'description',
            nullif(p ->> 'repeat_id', '')::uuid, nullif(p ->> 'plan_id', '')::uuid, nullif(p ->> 'plan_no', '')::int)
    returning * into r;
  else
    update public.txns x set
      kind = coalesce(p ->> 'kind', x.kind),
      at = coalesce((p ->> 'at')::timestamp, x.at),
      account_id = coalesce((p ->> 'account_id')::uuid, x.account_id),
      to_account_id = case when p ? 'to_account_id' then nullif(p ->> 'to_account_id', '')::uuid else x.to_account_id end,
      category_id = case when p ? 'category_id' then nullif(p ->> 'category_id', '')::uuid else x.category_id end,
      amount = coalesce((p ->> 'amount')::numeric, x.amount),
      to_amount = case when p ? 'to_amount' then nullif(p ->> 'to_amount', '')::numeric else x.to_amount end,
      fee = case when p ? 'fee' then coalesce(nullif(p ->> 'fee', '')::numeric, 0) else x.fee end,
      rate = case when p ? 'rate' then nullif(p ->> 'rate', '')::numeric else x.rate end,
      note = case when p ? 'note' then p ->> 'note' else x.note end,
      description = case when p ? 'description' then p ->> 'description' else x.description end
    where x.id = v_id
    returning * into r;
    if r.id is null then raise exception 'That transaction is not in this book.' using errcode = '42501'; end if;
  end if;

  if p ? 'splits' then
    delete from public.txn_splits s where s.txn_id = r.id;
    for part in select * from jsonb_array_elements(coalesce(p -> 'splits', '[]'::jsonb)) loop
      insert into public.txn_splits (txn_id, category_id, amount, note)
      values (r.id, nullif(part ->> 'category_id', '')::uuid, (part ->> 'amount')::numeric, part ->> 'note');
    end loop;
  end if;

  if p ? 'tags' then
    delete from public.txn_tags g where g.txn_id = r.id;
    for tag in select distinct regexp_replace(btrim(x), '^#', '') from jsonb_array_elements_text(coalesce(p -> 'tags', '[]'::jsonb)) x where btrim(x) <> '' loop
      select g.id into tid from public.tags g where g.book_id = r.book_id and lower(g.name) = lower(tag);
      if tid is null then
        insert into public.tags (name) values (tag) returning tags.id into tid;
      end if;
      insert into public.txn_tags (txn_id, tag_id) values (r.id, tid) on conflict do nothing;
    end loop;
  end if;
  return jsonb_build_object('id', r.id, 'at', r.at, 'rate', r.rate, 'to_amount', r.to_amount);
end $$;

-- ---------------------------------------------------------------- the main currency

-- Changing the main currency moves every stored rate with it, so old totals
-- keep their value. `per_old` is how many of the new currency one of the old
-- main currency is worth (1 SAR = 22.5 INR: per_old 22.5).
create or replace function public.set_main_currency(new_currency text, per_old numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b uuid := public.current_book_id(); old text; nc text := upper(btrim(coalesce(new_currency, '')));
begin
  if not public.is_owner() then raise exception 'Only the owner can change the main currency.' using errcode = '42501'; end if;
  if nc !~ '^[A-Z]{3}$' then raise exception 'Use a three-letter currency code.' using errcode = '22023'; end if;
  select x.currency into old from public.books x where x.id = b;
  if nc = old then return jsonb_build_object('currency', old); end if;
  if per_old is null or per_old <= 0 then raise exception 'Say how much one % is in %.', old, nc using errcode = '22023'; end if;
  update public.books x set currency = nc where x.id = b;
  update public.txns t set rate = case when t.currency = nc then 1 else t.rate * per_old end where t.book_id = b;
  delete from public.currency_rates r where r.book_id = b and r.currency = nc;
  update public.currency_rates r set rate = r.rate * per_old where r.book_id = b;
  insert into public.currency_rates (book_id, currency, rate) values (b, old, per_old);
  return jsonb_build_object('currency', nc);
end $$;
