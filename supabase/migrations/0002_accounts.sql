-- Monee, stage 2: account groups, accounts and exchange rates.
--
-- A group has a kind, and the kind decides how its accounts behave:
--   cash, bank, prepaid, other        ordinary money
--   card                              a credit card: a billing account, a settlement day and a payment day
--   debit_card                        spends straight from its linked bank account
--   savings, investment, loan,        may be set as Transfer-Expense: money moved into them
--   insurance                         counts as an expense
--   overdraft                         money owed, like a loan, but never Transfer-Expense
-- Assets are accounts with a balance above zero, liabilities below it.

create table public.account_groups (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  emoji       text check (char_length(emoji) <= 16),
  kind        text not null default 'other' check (kind in ('cash', 'bank', 'card', 'debit_card', 'savings',
                'investment', 'loan', 'insurance', 'prepaid', 'overdraft', 'other')),
  sort        int  not null default 0,
  hidden      boolean not null default false,
  collapsed   boolean not null default false,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index account_groups_book on public.account_groups (book_id, sort);

create table public.accounts (
  id                  uuid primary key default gen_random_uuid(),
  book_id             uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  group_id            uuid not null references public.account_groups (id) on delete cascade,
  name                text not null check (char_length(btrim(name)) between 1 and 60),
  currency            text check (currency ~ '^[A-Z]{3}$'),
  opening_balance     numeric(20, 4) not null default 0,
  note                text check (char_length(note) <= 300),
  in_totals           boolean not null default true,     -- counted in Assets, Liabilities and Total
  hidden              boolean not null default false,
  transfer_expense    boolean not null default false,    -- money moved in counts as an expense
  sort                int not null default 0,
  deleted_at          timestamptz,
  -- Credit cards
  billing_account_id  uuid references public.accounts (id) on delete set null,
  settlement_day      int check (settlement_day between 1 and 31),
  payment_day         int check (payment_day between 1 and 31),
  auto_pay            boolean not null default false,
  autopaid_until      date,                               -- the last payment day already paid automatically
  -- Debit cards
  linked_account_id   uuid references public.accounts (id) on delete set null,
  created_at          timestamptz not null default now()
);
create index accounts_book on public.accounts (book_id, group_id, sort);

-- How much of the main currency one unit of another currency is worth.
create table public.currency_rates (
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  currency    text not null check (currency ~ '^[A-Z]{3}$'),
  rate        numeric(24, 10) not null check (rate > 0),
  updated_at  timestamptz not null default now(),
  primary key (book_id, currency)
);

create or replace function public.group_kind(g uuid) returns text
language sql stable security definer set search_path = '' as $$
  select x.kind from public.account_groups x where x.id = g;
$$;

create or replace function public.account_kind(a uuid) returns text
language sql stable security definer set search_path = '' as $$
  select g.kind from public.accounts x join public.account_groups g on g.id = x.group_id where x.id = a;
$$;

-- The rate for a currency in a book: 1 for the main currency, null when unknown.
create or replace function public.rate_of(b uuid, c text) returns numeric
language sql stable security definer set search_path = '' as $$
  select case when c = (select x.currency from public.books x where x.id = b) then 1::numeric
              else (select r.rate from public.currency_rates r where r.book_id = b and r.currency = c) end;
$$;

-- ---------------------------------------------------------------- rules

create or replace function public.account_groups_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.name := btrim(new.name);
  new.emoji := nullif(btrim(coalesce(new.emoji, '')), '');
  if tg_op = 'UPDATE' then
    if new.book_id is distinct from old.book_id then
      raise exception 'A group cannot move between books.' using errcode = '42501';
    end if;
    if new.kind is distinct from old.kind and exists (select 1 from public.accounts a where a.group_id = new.id) then
      raise exception 'Move the accounts out before changing what kind of group this is.' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger account_groups_check before insert or update on public.account_groups
  for each row execute function public.account_groups_check();

create or replace function public.accounts_check() returns trigger
language plpgsql set search_path = '' as $$
declare k text; gb uuid; other record;
begin
  new.name := btrim(new.name);
  new.note := nullif(btrim(coalesce(new.note, '')), '');
  select g.kind, g.book_id into k, gb from public.account_groups g where g.id = new.group_id;
  if gb is distinct from new.book_id then
    raise exception 'That group is in another book.' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and new.book_id is distinct from old.book_id then
    raise exception 'An account cannot move between books.' using errcode = '42501';
  end if;
  new.currency := upper(coalesce(nullif(btrim(new.currency), ''), (select b.currency from public.books b where b.id = new.book_id)));

  -- Credit cards: a billing account in the same book, a settlement and a payment day.
  if k = 'card' then
    new.settlement_day := coalesce(new.settlement_day, 1);
    new.payment_day := coalesce(new.payment_day, 10);
    if new.billing_account_id is not null then
      select a.book_id, a.id, public.account_kind(a.id) as kind into other from public.accounts a where a.id = new.billing_account_id;
      if other.book_id is distinct from new.book_id or other.id = new.id or other.kind in ('card', 'debit_card') then
        raise exception 'Pay the card from a cash or bank account in this book.' using errcode = '22023';
      end if;
    end if;
    if new.auto_pay and new.billing_account_id is null then
      raise exception 'Automatic payment needs the account the card is paid from.' using errcode = '22023';
    end if;
  else
    new.billing_account_id := null;
    new.settlement_day := null;
    new.payment_day := null;
    new.auto_pay := false;
    new.autopaid_until := null;
  end if;

  -- Debit cards spend from their linked account, in its currency.
  if k = 'debit_card' then
    if new.linked_account_id is null then
      raise exception 'Link the debit card to the account it spends from.' using errcode = '22023';
    end if;
    select a.book_id, a.id, a.currency, public.account_kind(a.id) as kind into other from public.accounts a where a.id = new.linked_account_id;
    if other.book_id is distinct from new.book_id or other.id = new.id or other.kind in ('card', 'debit_card') then
      raise exception 'Link the debit card to a bank or cash account in this book.' using errcode = '22023';
    end if;
    new.currency := other.currency;
    new.opening_balance := 0;
  else
    new.linked_account_id := null;
  end if;

  if k not in ('savings', 'investment', 'loan', 'insurance') then
    new.transfer_expense := false;
  end if;
  return new;
end $$;
create trigger accounts_check before insert or update on public.accounts
  for each row execute function public.accounts_check();

create or replace function public.currency_rates_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.currency := upper(btrim(new.currency));
  if new.currency = (select b.currency from public.books b where b.id = new.book_id) then
    raise exception 'The main currency is always 1.' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger currency_rates_check before insert or update on public.currency_rates
  for each row execute function public.currency_rates_check();

-- ---------------------------------------------------------------- row level security

do $$
declare t text;
begin
  foreach t in array array['account_groups', 'accounts', 'currency_rates'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (book_id = (select public.current_book_id()))', t || '_read', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit())) with check (book_id = (select public.current_book_id()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_delete', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
