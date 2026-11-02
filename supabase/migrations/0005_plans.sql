-- Monee, stage 5: what happens by itself, and what is planned.
--
--   repeat_rules       salary, rent, subscriptions: recorded on their dates by catch_up()
--   instalment_plans   one purchase spread over months, every month recorded up front
--   cards              payable and outstanding balances, and automatic payment on payment day
--   budgets            per category, or in total, by week, month or year
--   bookmarks          saved entries for one-tap adding
--   day_memos          a line of text on a calendar day

-- ---------------------------------------------------------------- repeats

create table public.repeat_rules (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  kind            text not null check (kind in ('income', 'expense', 'transfer')),
  account_id      uuid not null references public.accounts (id) on delete cascade,
  to_account_id   uuid references public.accounts (id) on delete cascade,
  category_id     uuid references public.categories (id) on delete set null,
  amount          numeric(20, 4) not null check (amount > 0),
  to_amount       numeric(20, 4) check (to_amount > 0),
  fee             numeric(20, 4) not null default 0 check (fee >= 0),
  note            text check (char_length(note) <= 120),
  description     text check (char_length(description) <= 2000),
  freq            text not null check (freq in ('day', 'week', 'month', 'year')),
  every           int  not null default 1 check (every between 1 and 366),
  starts_on       date not null,
  ends_on         date,
  at_time         time not null default '09:00',
  done            int  not null default 0,      -- occurrences already recorded
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on)
);
create index repeat_rules_book on public.repeat_rules (book_id) where active;
alter table public.txns add constraint txns_repeat_fk foreign key (repeat_id) references public.repeat_rules (id) on delete set null;

-- The n-th date of a rule (0 is the first). Months keep their day, or the
-- month's last day when it is shorter (31 Jan, 28 Feb, 31 Mar).
create or replace function public.repeat_date(r public.repeat_rules, n int) returns date
language sql immutable set search_path = '' as $$
  select (r.starts_on + (n * r.every) * case r.freq when 'day' then interval '1 day' when 'week' then interval '1 week'
                                              when 'month' then interval '1 month' else interval '1 year' end)::date;
$$;

-- The dates of a rule between two days.
create or replace function public.repeat_dates(r public.repeat_rules, date_from date, date_to date) returns setof date
language plpgsql stable set search_path = '' as $$
declare n int := 0; d date;
begin
  -- Skip ahead roughly to date_from, then walk.
  if date_from > r.starts_on then
    n := greatest(0, case r.freq
      when 'day' then (date_from - r.starts_on) / r.every
      when 'week' then (date_from - r.starts_on) / (7 * r.every)
      when 'month' then ((extract(year from date_from) - extract(year from r.starts_on)) * 12
                        + extract(month from date_from) - extract(month from r.starts_on))::int / r.every - 1
      else (extract(year from date_from) - extract(year from r.starts_on))::int / r.every - 1 end);
  end if;
  loop
    d := public.repeat_date(r, n);
    exit when d > date_to or (r.ends_on is not null and d > r.ends_on);
    if d >= date_from then return next d; end if;
    n := n + 1;
    exit when n > 100000;
  end loop;
end $$;

create or replace function public.repeat_rules_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.accounts a where a.id = new.account_id and a.book_id = new.book_id)
     or (new.to_account_id is not null and not exists (select 1 from public.accounts a where a.id = new.to_account_id and a.book_id = new.book_id)) then
    raise exception 'That account is in another book.' using errcode = '22023';
  end if;
  if new.kind = 'transfer' and (new.to_account_id is null or new.to_account_id = new.account_id) then
    raise exception 'Pick the account the money goes to.' using errcode = '22023';
  end if;
  if new.kind <> 'transfer' then
    new.to_account_id := null; new.to_amount := null; new.fee := 0;
    if new.category_id is not null and not exists (
        select 1 from public.categories c where c.id = new.category_id and c.book_id = new.book_id and c.kind = new.kind) then
      raise exception 'Pick an % category.', new.kind using errcode = '22023';
    end if;
  else
    new.category_id := null;
  end if;
  if tg_op = 'UPDATE' then
    if new.book_id is distinct from old.book_id then
      raise exception 'A repeat cannot move between books.' using errcode = '42501';
    end if;
    -- A new start date starts the count again from there.
    if new.starts_on is distinct from old.starts_on or new.freq is distinct from old.freq or new.every is distinct from old.every then
      new.done := (select count(*) from public.repeat_dates(new, new.starts_on, public.book_today(new.book_id) - 1));
    end if;
  end if;
  return new;
end $$;
create trigger repeat_rules_check before insert or update on public.repeat_rules
  for each row execute function public.repeat_rules_check();

-- ---------------------------------------------------------------- instalments

create table public.instalment_plans (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  months      int not null check (months between 2 and 120),
  total       numeric(20, 4) not null check (total > 0),
  first_at    timestamp not null,
  created_at  timestamptz not null default now()
);
alter table public.txns add constraint txns_plan_fk foreign key (plan_id) references public.instalment_plans (id) on delete cascade;

-- A purchase spread over months: $300 in 3 from 12 Feb is $100 on 12 Feb,
-- 12 Mar and 12 Apr. The cents left over go on the first month.
create or replace function public.add_instalments(p jsonb, months int) returns jsonb
language plpgsql set search_path = '' as $$
declare plan uuid; total numeric := (p ->> 'amount')::numeric; part numeric; first_at timestamp; i int; q jsonb; ids jsonb := '[]';
begin
  if not public.can_edit() then raise exception 'You can only look at this book.' using errcode = '42501'; end if;
  if months is null or months < 2 or months > 120 then raise exception 'Pick 2 to 120 months.' using errcode = '22023'; end if;
  if total is null or total <= 0 then raise exception 'Enter the amount.' using errcode = '22023'; end if;
  if coalesce(p ->> 'kind', 'expense') = 'income' then raise exception 'Instalments are for spending.' using errcode = '22023'; end if;
  first_at := coalesce((p ->> 'at')::timestamp, public.book_now(public.current_book_id()));
  insert into public.instalment_plans (months, total, first_at) values (months, total, first_at) returning id into plan;
  part := trunc(total / months, 2);
  for i in 1 .. months loop
    q := p - 'id' - 'splits' || jsonb_build_object(
      'at', first_at + (i - 1) * interval '1 month',
      'amount', case when i = 1 then total - part * (months - 1) else part end,
      'plan_id', plan, 'plan_no', i);
    ids := ids || (public.save_txn(q) -> 'id');
  end loop;
  return jsonb_build_object('plan_id', plan, 'ids', ids);
end $$;

-- ---------------------------------------------------------------- cards

-- A day of a month, or the month's last day when the month is shorter.
create or replace function public.month_day(m date, d int) returns date
language sql immutable set search_path = '' as $$
  select (date_trunc('month', m)::date + (least(d, extract(day from (date_trunc('month', m) + interval '1 month - 1 day'))::int) - 1));
$$;

-- The settlement day on or before a day: the start of the card's open cycle.
create or replace function public.last_settlement(settlement_day int, d date) returns date
language sql immutable set search_path = '' as $$
  select case when public.month_day(d, settlement_day) <= d then public.month_day(d, settlement_day)
              else public.month_day((d - interval '1 month')::date, settlement_day) end;
$$;

-- The payment day for a cycle that closed on `closed`: the first payment day on or after it.
create or replace function public.due_after(payment_day int, closed date) returns date
language sql immutable set search_path = '' as $$
  select case when public.month_day(closed, payment_day) >= closed then public.month_day(closed, payment_day)
              else public.month_day((closed + interval '1 month')::date, payment_day) end;
$$;

-- What is owed on a card before a moment (positive means owed).
create or replace function public.card_debt(card uuid, before timestamp) returns numeric
language sql stable security definer set search_path = '' as $$
  select -(a.opening_balance + coalesce((select sum(m.delta) from public.account_moves m
                                          where m.account_id = a.id and m.at < before), 0))
    from public.accounts a where a.id = card;
$$;

-- What was spent on a card between two moments.
create or replace function public.card_spent(card uuid, since timestamp, before timestamp) returns numeric
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(-m.delta), 0) from public.account_moves m
   where m.account_id = card and m.delta < 0 and m.at >= since and m.at < before;
$$;

-- A card's position today: Balance Payable (closed cycles, due on the next
-- payment day) and Outstanding (the open cycle). Payments clear the oldest first.
create or replace function public.card_status(card uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a public.accounts%rowtype; today date; closed date; debt numeric; open_spend numeric; payable numeric; due date;
begin
  select * into a from public.accounts x where x.id = card and x.book_id = public.current_book_id();
  if a.id is null or public.account_kind(a.id) <> 'card' then return null; end if;
  today := public.book_today(a.book_id);
  closed := public.last_settlement(a.settlement_day, today);
  -- Up to the end of today: instalments still to come are not owed yet.
  debt := public.card_debt(a.id, (today + 1)::timestamp);
  open_spend := public.card_spent(a.id, closed::timestamp, (today + 1)::timestamp);
  payable := greatest(debt - open_spend, 0);
  due := public.due_after(a.payment_day, closed);
  return jsonb_build_object(
    'debt', debt, 'payable', payable, 'outstanding', debt - payable,
    'cycle_from', closed, 'next_settlement', public.month_day((closed + interval '1 month')::date, a.settlement_day),
    'due', due, 'overdue', payable > 0 and due < today,
    'billing_account_id', a.billing_account_id, 'auto_pay', a.auto_pay);
end $$;

-- Pay a card off: a transfer from its billing account (or another one).
create or replace function public.pay_card(card uuid, amount numeric default null, from_account uuid default null, at timestamp default null) returns jsonb
language plpgsql set search_path = '' as $$
declare a public.accounts%rowtype; s jsonb := public.card_status(card);
begin
  select * into a from public.accounts x where x.id = card;
  if s is null then raise exception 'That is not a card in this book.' using errcode = '22023'; end if;
  if coalesce(from_account, a.billing_account_id) is null then
    raise exception 'Pick the account to pay the card from.' using errcode = '22023';
  end if;
  amount := coalesce(amount, (s ->> 'payable')::numeric);
  if amount is null or amount <= 0 then raise exception 'Nothing to pay on this card.' using errcode = '22023'; end if;
  return public.save_txn(jsonb_build_object('kind', 'transfer', 'account_id', coalesce(from_account, a.billing_account_id),
    'to_account_id', card, 'amount', amount, 'note', 'Card payment',
    'at', coalesce(at, public.book_now(a.book_id))));
end $$;

-- ---------------------------------------------------------------- budgets, bookmarks, memos

create table public.budgets (
  id           uuid primary key default gen_random_uuid(),
  book_id      uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  category_id  uuid references public.categories (id) on delete cascade,   -- null: the total budget
  period       text not null default 'month' check (period in ('week', 'month', 'year')),
  amount       numeric(20, 4) not null check (amount >= 0),
  from_month   date not null default date_trunc('month', now())::date,   -- applies from this month until a later row
  created_at   timestamptz not null default now()
);
create unique index budgets_one on public.budgets (book_id, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid), period, from_month);

create or replace function public.budgets_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.from_month := date_trunc('month', new.from_month)::date;
  if new.category_id is not null and not exists (
      select 1 from public.categories c where c.id = new.category_id and c.book_id = new.book_id and c.kind = 'expense' and c.parent_id is null) then
    raise exception 'Budgets are for expense categories (not subcategories) in this book.' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and new.book_id is distinct from old.book_id then
    raise exception 'A budget cannot move between books.' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger budgets_check before insert or update on public.budgets
  for each row execute function public.budgets_check();

create table public.bookmarks (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  kind            text not null check (kind in ('income', 'expense', 'transfer')),
  account_id      uuid references public.accounts (id) on delete cascade,
  to_account_id   uuid references public.accounts (id) on delete cascade,
  category_id     uuid references public.categories (id) on delete set null,
  amount          numeric(20, 4) check (amount > 0),
  fee             numeric(20, 4) not null default 0 check (fee >= 0),
  note            text check (char_length(note) <= 120),
  description     text check (char_length(description) <= 2000),
  sort            int not null default 0,
  created_at      timestamptz not null default now()
);

create table public.day_memos (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  day         date not null,
  text        text not null check (char_length(btrim(text)) between 1 and 1000),
  color       text check (color ~ '^#[0-9a-fA-F]{6}$'),
  created_at  timestamptz not null default now()
);
create index day_memos_book_day on public.day_memos (book_id, day);

do $$
declare t text;
begin
  foreach t in array array['repeat_rules', 'instalment_plans', 'budgets', 'bookmarks', 'day_memos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (book_id = (select public.current_book_id()))', t || '_read', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit())) with check (book_id = (select public.current_book_id()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_delete', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- catching up

-- Records what is due: repeats up to today (or to the month's end when the
-- book shows them from the first of the month), and automatic card payments
-- on payment day. The app calls it when it opens; running it twice records
-- nothing twice.
create or replace function public.catch_up() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b public.books%rowtype; today date; horizon date; r public.repeat_rules; d date; n_rep int := 0; n_pay int := 0;
  c public.accounts%rowtype; m date; pay_on date; closed date; amt numeric; since date;
begin
  select * into b from public.books x where x.id = public.current_book_id();
  if b.id is null then return jsonb_build_object('repeats', 0, 'card_payments', 0); end if;
  today := public.book_today(b.id);
  horizon := case when b.repeat_show = 'month_start' then (date_trunc('month', today) + interval '1 month - 1 day')::date else today end;

  for r in select * from public.repeat_rules x where x.book_id = b.id and x.active for update loop
    loop
      d := public.repeat_date(r, r.done);
      exit when d > horizon or (r.ends_on is not null and d > r.ends_on);
      -- An entry that cannot be made yet (a rate still missing) waits for the
      -- next catch-up instead of stopping everything else.
      begin
        insert into public.txns (book_id, kind, at, account_id, to_account_id, category_id, amount, to_amount, fee, note, description, repeat_id)
        select b.id, r.kind, d + r.at_time, r.account_id, r.to_account_id, r.category_id, r.amount, r.to_amount, r.fee, r.note, r.description, r.id
         where exists (select 1 from public.accounts a where a.id = r.account_id and a.deleted_at is null);
      exception when others then
        exit;
      end;
      r.done := r.done + 1;
      n_rep := n_rep + 1;
    end loop;
    update public.repeat_rules x set done = r.done where x.id = r.id and x.done is distinct from r.done;
  end loop;

  for c in select x.* from public.accounts x where x.book_id = b.id and x.auto_pay and x.billing_account_id is not null
             and x.deleted_at is null and public.account_kind(x.id) = 'card' for update loop
    since := coalesce(c.autopaid_until, today - 1);
    m := date_trunc('month', since)::date;
    while m <= today loop
      pay_on := public.month_day(m, c.payment_day);
      if pay_on > since and pay_on <= today then
        closed := public.last_settlement(c.settlement_day, pay_on);
        if public.due_after(c.payment_day, closed) <> pay_on then
          closed := public.last_settlement(c.settlement_day, closed - 1);
        end if;
        amt := greatest(public.card_debt(c.id, pay_on::timestamp) - public.card_spent(c.id, closed::timestamp, pay_on::timestamp), 0);
        if amt > 0 and not exists (select 1 from public.txns t where t.to_account_id = c.id and t.pays_cycle = pay_on) then
          insert into public.txns (book_id, kind, at, account_id, to_account_id, amount, note, pays_cycle)
          values (b.id, 'transfer', pay_on + time '09:00', c.billing_account_id, c.id, amt, 'Card payment', pay_on);
          n_pay := n_pay + 1;
        end if;
      end if;
      m := (m + interval '1 month')::date;
    end loop;
    update public.accounts x set autopaid_until = today where x.id = c.id;
  end loop;
  return jsonb_build_object('repeats', n_rep, 'card_payments', n_pay);
end $$;

-- Repeats still to come between two days, for the calendar and the month list
-- (shown dimmed; they are recorded on their day by catch_up).
create or replace function public.upcoming(date_from date, date_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('repeat_id', r.id, 'day', d, 'kind', r.kind, 'account_id', r.account_id,
             'to_account_id', r.to_account_id, 'category_id', r.category_id, 'amount', r.amount, 'note', r.note,
             'amount_main', round(r.amount * coalesce(public.rate_of(b, a.currency), 1), 4))
           order by d)
      from public.repeat_rules r
      join public.accounts a on a.id = r.account_id
      cross join lateral public.repeat_dates(r, greatest(date_from, public.repeat_date(r, r.done)), date_to) d
     where r.book_id = b and r.active), '[]'::jsonb);
end $$;

-- A new repeat from an entry: the entry's date is the first occurrence, and
-- everything due up to today is recorded at once.
create or replace function public.add_repeat(p jsonb, freq text, every int default 1, ends_on date default null) returns jsonb
language plpgsql set search_path = '' as $$
declare b uuid := public.current_book_id(); at timestamp; r public.repeat_rules%rowtype;
begin
  if not public.can_edit() then raise exception 'You can only look at this book.' using errcode = '42501'; end if;
  at := coalesce((p ->> 'at')::timestamp, public.book_now(b));
  insert into public.repeat_rules (kind, account_id, to_account_id, category_id, amount, to_amount, fee, note, description,
                                   freq, every, starts_on, ends_on, at_time)
  values (p ->> 'kind', (p ->> 'account_id')::uuid, nullif(p ->> 'to_account_id', '')::uuid, nullif(p ->> 'category_id', '')::uuid,
          (p ->> 'amount')::numeric, nullif(p ->> 'to_amount', '')::numeric, coalesce(nullif(p ->> 'fee', '')::numeric, 0),
          p ->> 'note', p ->> 'description', freq, coalesce(every, 1), at::date, ends_on, at::time)
  returning * into r;
  perform public.catch_up();
  return jsonb_build_object('repeat_id', r.id,
    'recorded', (select count(*) from public.txns t where t.repeat_id = r.id));
end $$;
