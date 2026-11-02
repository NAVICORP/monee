-- Monee, stage 6: what the screens read.
--
-- Each function answers one screen in one call, for the book being worked in.
-- They run as their owner and filter by current_book_id() themselves.
--
-- A filter (f) is a json object, every key optional:
--   accounts    [uuid]   transactions on, from or to these accounts
--   categories  [uuid]   these categories (a category includes its subcategories)
--   kinds       [text]   income, expense, transfer
--   tags        [text]   any of these tags
--   q           text     words in the note, description, category, account or tags
--   min, max    number   the amount (in the account's currency)

create or replace function public.uuids(j jsonb) returns uuid[]
language sql immutable set search_path = '' as $$
  select case when j is null or jsonb_typeof(j) <> 'array' or jsonb_array_length(j) = 0 then null
              else array(select x::uuid from jsonb_array_elements_text(j) x) end;
$$;

create or replace function public.texts(j jsonb) returns text[]
language sql immutable set search_path = '' as $$
  select case when j is null or jsonb_typeof(j) <> 'array' or jsonb_array_length(j) = 0 then null
              else array(select lower(btrim(x)) from jsonb_array_elements_text(j) x) end;
$$;

-- Does a transaction pass a filter?
create or replace function public.txn_passes(t public.txns, f jsonb) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare acc uuid[] := public.uuids(f -> 'accounts'); cats uuid[] := public.uuids(f -> 'categories');
  kinds text[] := public.texts(f -> 'kinds'); tags text[] := public.texts(f -> 'tags');
  q text := nullif(btrim(coalesce(f ->> 'q', '')), '');
begin
  if f is null or f = '{}'::jsonb then return true; end if;
  if kinds is not null and not (t.kind = any (kinds)) then return false; end if;
  if acc is not null and not (t.account_id = any (acc) or t.to_account_id = any (acc)
       or exists (select 1 from public.accounts a where a.id = t.account_id and a.linked_account_id = any (acc))) then
    return false;
  end if;
  if cats is not null and not exists (
      select 1 from public.categories c
       where c.id in (select t.category_id union select s.category_id from public.txn_splits s where s.txn_id = t.id)
         and (c.id = any (cats) or c.parent_id = any (cats))) then
    return false;
  end if;
  if tags is not null and not exists (
      select 1 from public.txn_tags x join public.tags g on g.id = x.tag_id
       where x.txn_id = t.id and lower(g.name) = any (tags)) then
    return false;
  end if;
  if f ? 'min' and t.amount < (f ->> 'min')::numeric then return false; end if;
  if f ? 'max' and t.amount > (f ->> 'max')::numeric then return false; end if;
  if q is not null then
    q := '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%';
    if not (coalesce(t.note, '') ilike q or coalesce(t.description, '') ilike q
        or exists (select 1 from public.categories c where c.id = t.category_id and c.name ilike q)
        or exists (select 1 from public.categories c join public.categories p on p.id = c.parent_id where c.id = t.category_id and p.name ilike q)
        or exists (select 1 from public.accounts a where a.id in (t.account_id, t.to_account_id) and a.name ilike q)
        or exists (select 1 from public.txn_tags x join public.tags g on g.id = x.tag_id where x.txn_id = t.id and g.name ilike q)
        or exists (select 1 from public.txn_splits s left join public.categories c on c.id = s.category_id
                    where s.txn_id = t.id and (coalesce(s.note, '') ilike q or coalesce(c.name, '') ilike q))
        or t.amount::text like replace(q, ',', '')) then
      return false;
    end if;
  end if;
  return true;
end $$;

-- ---------------------------------------------------------------- periods

-- The month labelled y-m: from its start day to the day before the next one.
-- With the month starting on the 25th, "October" runs 25 Oct to 24 Nov.
create or replace function public.month_range(b uuid, y int, m int) returns daterange
language sql stable security definer set search_path = '' as $$
  select daterange(public.month_day(make_date(y, m, 1), x.month_start_day),
                   public.month_day((make_date(y, m, 1) + interval '1 month')::date, x.month_start_day), '[)')
    from public.books x where x.id = b;
$$;

-- ---------------------------------------------------------------- Trans tab

-- Income, expenses and total for a period, with the carried-over balance
-- when the book carries over.
create or replace function public.period_totals(date_from date, date_to date, f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b public.books%rowtype; inc numeric; exp numeric; carry numeric := 0;
begin
  select * into b from public.books x where x.id = public.current_book_id();
  if b.id is null then raise exception 'Open a book first.' using errcode = '42501'; end if;
  select coalesce(sum(e.amount_main) filter (where e.kind = 'income'), 0),
         coalesce(sum(e.amount_main) filter (where e.kind = 'expense'), 0)
    into inc, exp
    from public.entries e join public.txns t on t.id = e.txn_id
   where e.book_id = b.id and e.day between date_from and date_to and public.txn_passes(t, f);
  if b.carry_over then
    select coalesce(sum(case e.kind when 'income' then e.amount_main else -e.amount_main end), 0) into carry
      from public.entries e join public.txns t on t.id = e.txn_id
     where e.book_id = b.id and e.day < date_from and public.txn_passes(t, f);
  end if;
  return jsonb_build_object('from', date_from, 'to', date_to, 'income', inc, 'expense', exp,
    'carry', carry, 'carry_over', b.carry_over, 'total', carry + inc - exp);
end $$;

-- Income and expense per day: the calendar, and the Daily list's day headers.
create or replace function public.day_totals(date_from date, date_to date, f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('day', x.day, 'income', x.inc, 'expense', x.exp) order by x.day)
      from (select e.day,
                   coalesce(sum(e.amount_main) filter (where e.kind = 'income'), 0) as inc,
                   coalesce(sum(e.amount_main) filter (where e.kind = 'expense'), 0) as exp
              from public.entries e join public.txns t on t.id = e.txn_id
             where e.book_id = b and e.day between date_from and date_to and public.txn_passes(t, f)
             group by e.day) x), '[]'::jsonb);
end $$;

-- Totals by week or month across a span: the Monthly sub-tab (months of a
-- year, the weeks of a month). Weeks start on the book's week start day.
create or replace function public.span_totals(date_from date, date_to date, unit text default 'month', f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b public.books%rowtype; spans daterange[] := '{}'; d date; y int; m int; r daterange;
begin
  select * into b from public.books x where x.id = public.current_book_id();
  if unit = 'week' then
    d := date_from - ((extract(dow from date_from)::int - b.week_start + 7) % 7);
    while d <= date_to loop
      spans := spans || daterange(greatest(d, date_from), least(d + 7, date_to + 1), '[)');
      d := d + 7;
    end loop;
  else
    y := extract(year from date_from); m := extract(month from date_from);
    loop
      r := public.month_range(b.id, y, m);
      exit when lower(r) > date_to;
      if upper(r) > date_from then spans := spans || r; end if;
      m := m + 1; if m > 12 then m := 1; y := y + 1; end if;
      exit when y > extract(year from date_to) + 1;
    end loop;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('from', lower(s), 'to', upper(s) - 1,
             'income', coalesce(x.inc, 0), 'expense', coalesce(x.exp, 0)) order by lower(s) desc)
      from unnest(spans) s
      left join lateral (
        select sum(e.amount_main) filter (where e.kind = 'income') as inc,
               sum(e.amount_main) filter (where e.kind = 'expense') as exp
          from public.entries e join public.txns t on t.id = e.txn_id
         where e.book_id = b.id and e.day >= lower(s) and e.day < upper(s) and public.txn_passes(t, f)) x on true), '[]'::jsonb);
end $$;

-- The transactions of a period, newest first, with everything a row shows.
-- Also the search (a wide period and f.q) and an account's own list.
create or replace function public.txn_list(date_from date, date_to date, f jsonb default '{}', max_rows int default 3000) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b public.books%rowtype;
begin
  select * into b from public.books x where x.id = public.current_book_id();
  if b.id is null then raise exception 'Open a book first.' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(x)::jsonb order by x.at desc, x.created_at desc)
      from (
        select t.id, t.kind, t.at, t.created_at, t.account_id, a.name as account, a.currency, t.to_account_id, ta.name as to_account,
               ta.currency as to_currency, t.category_id, c.name as category, c.emoji, p.id as parent_id, p.name as parent,
               p.emoji as parent_emoji, t.amount, t.to_amount, t.fee, t.rate, round(t.amount * t.rate, 4) as amount_main,
               t.note, t.description, t.repeat_id, t.plan_id, t.plan_no, ip.months as plan_months, t.created_by,
               case
                 when t.kind = 'transfer' and ta.transfer_expense and not a.transfer_expense then 'expense'
                 when t.kind = 'transfer' and a.transfer_expense and not ta.transfer_expense then 'income'
                 when t.kind = 'expense' and b.card_display = 'lump_sum' and public.account_kind(a.id) = 'card' then 'card'
                 else t.kind end as counts_as,
               (select coalesce(jsonb_agg(g.name order by g.name), '[]') from public.txn_tags tt join public.tags g on g.id = tt.tag_id where tt.txn_id = t.id) as tags,
               (select count(*) from public.txn_photos ph where ph.txn_id = t.id) as photos,
               (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'category_id', s.category_id, 'category', sc.name,
                         'emoji', coalesce(sc.emoji, sp.emoji), 'amount', s.amount, 'note', s.note) order by s.amount desc), '[]')
                  from public.txn_splits s left join public.categories sc on sc.id = s.category_id
                  left join public.categories sp on sp.id = sc.parent_id where s.txn_id = t.id) as splits
          from public.txns t
          join public.accounts a on a.id = t.account_id
          left join public.accounts ta on ta.id = t.to_account_id
          left join public.categories c on c.id = t.category_id
          left join public.categories p on p.id = c.parent_id
          left join public.instalment_plans ip on ip.id = t.plan_id
         where t.book_id = b.id and t.at >= date_from and t.at < date_to + 1 and public.txn_passes(t, f)
         order by t.at desc, t.created_at desc
         limit greatest(1, least(coalesce(max_rows, 3000), 10000))) x), '[]'::jsonb);
end $$;

-- Transactions grouped by their note: the Note sub-tab.
create or replace function public.note_totals(date_from date, date_to date, kind text default 'expense', f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('note', x.note, 'count', x.n, 'total', x.total) order by x.total desc)
      from (select coalesce(e.note, '') as note, count(distinct e.txn_id) as n, sum(e.amount_main) as total
              from public.entries e join public.txns t on t.id = e.txn_id
             where e.book_id = b and e.kind = note_totals.kind and e.day between date_from and date_to and public.txn_passes(t, f)
             group by 1) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------- Stats tab

-- Income or expense by category (subcategories added into their parent).
-- Money that is not in a category shows as Transfers, Card payments, Fees or
-- Uncategorised.
create or replace function public.category_totals(date_from date, date_to date, kind text default 'expense',
  parent uuid default null, f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id(); out jsonb;
begin
  with lines as (
    select case when parent is null then coalesce(p.id, c.id) else c.id end as category_id,
           case when parent is null then coalesce(p.name, c.name) else c.name end as name,
           case when parent is null then coalesce(p.emoji, c.emoji) else coalesce(c.emoji, p.emoji) end as emoji,
           coalesce(e.special, 'none') as special, e.amount_main
      from public.entries e
      join public.txns t on t.id = e.txn_id
      left join public.categories c on c.id = e.category_id
      left join public.categories p on p.id = c.parent_id
     where e.book_id = b and e.kind = category_totals.kind and e.day between date_from and date_to
       and (parent is null or c.id = parent or c.parent_id = parent)
       and public.txn_passes(t, f)
  ), grouped as (
    select coalesce(l.category_id::text, l.special) as key, l.category_id, max(l.name) as name, max(l.emoji) as emoji,
           sum(l.amount_main) as amount
      from lines l group by 1, 2
  ), total as (select coalesce(sum(g.amount), 0) as amount from grouped g)
  select jsonb_build_object('total', (select amount from total), 'rows', coalesce(jsonb_agg(jsonb_build_object(
           'category_id', g.category_id, 'key', g.key,
           'name', coalesce(g.name, case g.key when 'transfer' then 'Transfers' when 'card' then 'Card payments'
                                               when 'fee' then 'Fees' else 'Uncategorised' end),
           'emoji', g.emoji, 'amount', g.amount,
           'percent', round(100 * g.amount / nullif((select amount from total), 0), 1),
           'has_subs', exists (select 1 from public.categories s where s.parent_id = g.category_id and s.deleted_at is null))
           order by g.amount desc), '[]'))
    into out
    from grouped g;
  return out;
end $$;

-- One category (or all income or all expense) month by month, for the trend line.
create or replace function public.category_trend(kind text, category uuid default null, months int default 12,
  until date default null, f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b public.books%rowtype; y int; m int; r daterange; i int; out jsonb := '[]';
begin
  select * into b from public.books x where x.id = public.current_book_id();
  until := coalesce(until, public.book_today(b.id));
  y := extract(year from until); m := extract(month from until);
  if public.month_day(make_date(y, m, 1), b.month_start_day) > until then
    m := m - 1; if m < 1 then m := 12; y := y - 1; end if;
  end if;
  for i in 1 .. least(greatest(coalesce(months, 12), 1), 60) loop
    r := public.month_range(b.id, y, m);
    out := jsonb_build_object('year', y, 'month', m, 'from', lower(r), 'to', upper(r) - 1,
      'amount', coalesce((select sum(e.amount_main) from public.entries e
                            join public.txns t on t.id = e.txn_id
                            left join public.categories c on c.id = e.category_id
                           where e.book_id = b.id and e.kind = category_trend.kind
                             and e.day >= lower(r) and e.day < upper(r)
                             and (category is null or c.id = category or c.parent_id = category)
                             and public.txn_passes(t, f)), 0)) || out;
    m := m - 1; if m < 1 then m := 12; y := y - 1; end if;
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------- budgets

-- Budget against spending for a period. The budget in force is the latest
-- one set on or before the period's first month. A category without a
-- budget for this kind of period borrows its monthly one (a week is 12/52 of
-- a month, a year twelve months). The total is the total budget when one is
-- set, otherwise the categories added up.
create or replace function public.budget_status(date_from date, date_to date, period text default 'month') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id(); today date := public.book_today(public.current_book_id());
  rows jsonb; total_budget numeric; total_spent numeric; mo date := date_trunc('month', date_from)::date;
begin
  with cats as (
    select c.id, c.name, c.emoji, c.sort from public.categories c
     where c.book_id = b and c.kind = 'expense' and c.parent_id is null and c.deleted_at is null
  ), budget as (
    -- A budget saved as 0 means it was cleared from that month on.
    select c.id, nullif(coalesce(
      (select x.amount from public.budgets x where x.book_id = b and x.category_id = c.id and x.period = budget_status.period
         and x.from_month <= mo order by x.from_month desc limit 1),
      (select x.amount * case budget_status.period when 'week' then 12.0 / 52 when 'year' then 12 else 1 end
         from public.budgets x where x.book_id = b and x.category_id = c.id and x.period = 'month'
          and x.from_month <= mo order by x.from_month desc limit 1)), 0) as amount
      from cats c
  ), spent as (
    select coalesce(p.id, c.id) as id, sum(e.amount_main) as amount
      from public.entries e join public.categories c on c.id = e.category_id
      left join public.categories p on p.id = c.parent_id
     where e.book_id = b and e.kind = 'expense' and e.day between date_from and date_to
     group by 1
  )
  select jsonb_agg(jsonb_build_object('category_id', c.id, 'name', c.name, 'emoji', c.emoji,
           'budget', bu.amount, 'spent', coalesce(s.amount, 0), 'left', bu.amount - coalesce(s.amount, 0),
           'percent', round(100 * coalesce(s.amount, 0) / nullif(bu.amount, 0), 0))
           order by c.sort, c.name)
    into rows
    from cats c join budget bu on bu.id = c.id left join spent s on s.id = c.id
   where bu.amount is not null;

  total_budget := coalesce(nullif(coalesce(
    (select x.amount from public.budgets x where x.book_id = b and x.category_id is null and x.period = budget_status.period
        and x.from_month <= mo order by x.from_month desc limit 1),
    (select x.amount * case budget_status.period when 'week' then 12.0 / 52 when 'year' then 12 else 1 end
       from public.budgets x where x.book_id = b and x.category_id is null and x.period = 'month'
        and x.from_month <= mo order by x.from_month desc limit 1)), 0),
    (select sum((r ->> 'budget')::numeric) from jsonb_array_elements(coalesce(rows, '[]')) r));
  select coalesce(sum(e.amount_main), 0) into total_spent from public.entries e
   where e.book_id = b and e.kind = 'expense' and e.day between date_from and date_to;
  return jsonb_build_object(
    'from', date_from, 'to', date_to,
    'today_percent', case when today < date_from then 0 when today > date_to then 100
                          else round(100.0 * (today - date_from + 1) / (date_to - date_from + 1), 0) end,
    'total', case when total_budget is null then null else jsonb_build_object('budget', total_budget, 'spent', total_spent,
               'left', total_budget - total_spent, 'percent', round(100 * total_spent / nullif(total_budget, 0), 0)) end,
    'rows', coalesce(rows, '[]'));
end $$;

-- ---------------------------------------------------------------- Accounts tab

-- An account's balance at the end of a day, in its own currency.
create or replace function public.balance_at(account uuid, until date) returns numeric
language sql stable security definer set search_path = '' as $$
  select a.opening_balance + coalesce((select sum(m.delta) from public.account_moves m
                                        where m.account_id = a.id and m.at < until + 1), 0)
    from public.accounts a where a.id = account;
$$;

-- Every group and account with today's balances, Assets, Liabilities and Total.
-- Debit cards show what was spent on them this month; their spending is in
-- the linked account's balance. Hidden accounts come with hidden: true.
create or replace function public.accounts_overview(include_deleted boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b public.books%rowtype; today date; mr daterange; out jsonb;
begin
  select * into b from public.books x where x.id = public.current_book_id();
  if b.id is null then raise exception 'Open a book first.' using errcode = '42501'; end if;
  today := public.book_today(b.id);
  mr := public.month_range(b.id, extract(year from today)::int, extract(month from today)::int);
  if lower(mr) > today then
    mr := public.month_range(b.id, extract(year from (today - interval '1 month'))::int, extract(month from (today - interval '1 month'))::int);
  end if;

  with ao0 as materialized (
    select a.id, a.group_id, a.name, a.currency,
           case when g.kind = 'debit_card' then null else public.balance_at(a.id, today) end as balance,
           a.in_totals, a.hidden, a.deleted_at is not null as deleted, g.kind, a.sort,
           case g.kind
             when 'card' then public.card_status(a.id)
             when 'debit_card' then jsonb_build_object('linked_account_id', a.linked_account_id,
               'spent_this_month', coalesce((select sum(t.amount) from public.txns t
                  where t.account_id = a.id and t.kind = 'expense' and t.at >= lower(mr) and t.at < least(upper(mr), today + 1)), 0))
             else null end as extra
      from public.accounts a join public.account_groups g on g.id = a.group_id
     where a.book_id = b.id and (include_deleted or (a.deleted_at is null and g.deleted_at is null))
  ), ao as materialized (
    select x.*, round(x.balance * public.rate_of(b.id, x.currency), 4) as balance_main,
           public.rate_of(b.id, x.currency) as rate
      from ao0 x
  ), sums as (
    select coalesce(sum(x.balance_main) filter (where x.balance_main > 0), 0) as assets,
           coalesce(-sum(x.balance_main) filter (where x.balance_main < 0), 0) as liabilities
      from ao x where x.in_totals and not x.deleted and x.kind <> 'debit_card'
  ), groups as (
    select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'emoji', g.emoji, 'kind', g.kind,
             'hidden', g.hidden, 'collapsed', g.collapsed, 'deleted', g.deleted_at is not null,
             'total_main', (select coalesce(sum(x.balance_main), 0) from ao x where x.group_id = g.id and x.in_totals and not x.deleted),
             'payable_main', case when g.kind = 'card' then (select coalesce(sum(round((x.extra ->> 'payable')::numeric * x.rate, 4)), 0) from ao x where x.group_id = g.id and not x.deleted) end,
             'outstanding_main', case when g.kind = 'card' then (select coalesce(sum(round((x.extra ->> 'outstanding')::numeric * x.rate, 4)), 0) from ao x where x.group_id = g.id and not x.deleted) end,
             'accounts', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'currency', x.currency,
                            'balance', x.balance, 'balance_main', x.balance_main, 'in_totals', x.in_totals, 'hidden', x.hidden,
                            'deleted', x.deleted, 'card', case when x.kind = 'card' then x.extra end,
                            'debit', case when x.kind = 'debit_card' then x.extra end) order by x.sort, x.name), '[]')
                            from ao x where x.group_id = g.id))
             order by g.sort, g.name), '[]') as list
      from public.account_groups g
     where g.book_id = b.id and (include_deleted or g.deleted_at is null)
  )
  select jsonb_build_object('currency', b.currency, 'today', today, 'assets', s.assets, 'liabilities', s.liabilities,
    'total', s.assets - s.liabilities, 'groups', gr.list,
    'missing_rates', (select coalesce(jsonb_agg(distinct x.currency), '[]') from ao x where x.balance is not null and x.balance_main is null))
    into out
    from sums s, groups gr;
  return out;
end $$;

-- An account month by month: what came in, what went out, and the balance at
-- each month's end.
create or replace function public.account_trend(account uuid, months int default 12) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a public.accounts%rowtype; today date; y int; m int; r daterange; i int; out jsonb := '[]'; bal_to uuid;
begin
  select * into a from public.accounts x where x.id = account and x.book_id = public.current_book_id();
  if a.id is null then raise exception 'That account is not in this book.' using errcode = '42501'; end if;
  bal_to := coalesce(a.linked_account_id, a.id);
  today := public.book_today(a.book_id);
  y := extract(year from today); m := extract(month from today);
  for i in 1 .. least(greatest(coalesce(months, 12), 1), 60) loop
    r := public.month_range(a.book_id, y, m);
    if lower(r) <= today then
      out := jsonb_build_object('year', y, 'month', m, 'from', lower(r), 'to', upper(r) - 1,
        'in', coalesce((select sum(x.delta) from public.account_moves x where x.via_account_id = a.id and x.delta > 0 and x.at >= lower(r) and x.at < upper(r)), 0),
        'out', coalesce((select -sum(x.delta) from public.account_moves x where x.via_account_id = a.id and x.delta < 0 and x.at >= lower(r) and x.at < upper(r)), 0),
        'balance', public.balance_at(bal_to, least(upper(r) - 1, today))) || out;
    end if;
    m := m - 1; if m < 1 then m := 12; y := y - 1; end if;
  end loop;
  return out;
end $$;

-- Assets, liabilities and total at each month's end, at today's rates.
create or replace function public.asset_trend(months int default 12) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id(); today date := public.book_today(public.current_book_id());
  y int; m int; r daterange; i int; out jsonb := '[]'; d date; pos numeric; neg numeric;
begin
  y := extract(year from today); m := extract(month from today);
  for i in 1 .. least(greatest(coalesce(months, 12), 1), 60) loop
    r := public.month_range(b, y, m);
    if lower(r) <= today then
      d := least(upper(r) - 1, today);
      select coalesce(sum(v) filter (where v > 0), 0), coalesce(-sum(v) filter (where v < 0), 0) into pos, neg
        from (select round(public.balance_at(a.id, d) * coalesce(public.rate_of(b, a.currency), 0), 4) as v
                from public.accounts a join public.account_groups g on g.id = a.group_id
               where a.book_id = b and a.in_totals and a.deleted_at is null and g.kind <> 'debit_card') x;
      out := jsonb_build_object('year', y, 'month', m, 'to', d, 'assets', pos, 'liabilities', neg, 'total', pos - neg) || out;
    end if;
    m := m - 1; if m < 1 then m := 12; y := y - 1; end if;
  end loop;
  return out;
end $$;

-- The Total sub-tab's Accounts block: expenses paid from cash and bank,
-- expenses on cards, money moved out of cash and bank, and expenses against
-- the period before.
create or replace function public.period_accounts(date_from date, date_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b uuid := public.current_book_id(); days int := date_to - date_from + 1; cash_exp numeric; card_exp numeric;
  moved numeric; before numeric;
begin
  select coalesce(sum(round(t.amount * t.rate, 4)) filter (where public.account_kind(t.account_id) <> 'card'), 0),
         coalesce(sum(round(t.amount * t.rate, 4)) filter (where public.account_kind(t.account_id) = 'card'), 0)
    into cash_exp, card_exp
    from public.txns t where t.book_id = b and t.kind = 'expense' and t.at >= date_from and t.at < date_to + 1;
  select coalesce(sum(round(t.amount * t.rate, 4)), 0) into moved
    from public.txns t where t.book_id = b and t.kind = 'transfer' and t.at >= date_from and t.at < date_to + 1
     and public.account_kind(t.account_id) in ('cash', 'bank', 'prepaid', 'debit_card', 'other');
  select coalesce(sum(e.amount_main), 0) into before from public.entries e
   where e.book_id = b and e.kind = 'expense'
     and e.day >= (date_from - interval '1 month')::date and e.day < date_from;
  return jsonb_build_object('expense_cash', cash_exp, 'expense_card', card_exp, 'transfer_out', moved,
    'expense_before', before,
    'compared_percent', round(100 * (select coalesce(sum(e.amount_main), 0) from public.entries e
                                       where e.book_id = b and e.kind = 'expense' and e.day between date_from and date_to)
                               / nullif(before, 0), 0),
    'days', days);
end $$;

-- ---------------------------------------------------------------- import

-- Many transactions at once, by name (an Excel sheet, or another app's
-- backup). Accounts and categories that do not exist yet are made: accounts
-- in Others (in the main currency unless the row says), categories at the
-- end of the list. Each row: date, kind (income, expense, transfer), account,
-- to_account, category, subcategory, amount, currency, note, description.
create or replace function public.import_rows(rows jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare b uuid := public.current_book_id(); r jsonb; acc uuid; acc_to uuid; cat uuid; sub uuid; k text; n int := 0;
  others uuid; made_acc int := 0; made_cat int := 0;
begin
  if not public.can_edit() then raise exception 'You can only look at this book.' using errcode = '42501'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) > 20000 then
    raise exception 'Import up to 20000 rows at a time.' using errcode = '22023';
  end if;
  select g.id into others from public.account_groups g where g.book_id = b and g.kind = 'other' and g.deleted_at is null order by g.sort limit 1;
  if others is null then
    insert into public.account_groups (name, emoji, kind, sort) values ('Others', '🗂️', 'other', 1000) returning id into others;
  end if;
  for r in select * from jsonb_array_elements(rows) loop
    k := lower(coalesce(r ->> 'kind', 'expense'));
    if k in ('exp', 'expenses', 'expense', 'out') then k := 'expense';
    elsif k in ('inc', 'income', 'in') then k := 'income';
    elsif k like 'transfer%' then k := 'transfer';
    else k := 'expense'; end if;
    -- The account, by name.
    select a.id into acc from public.accounts a where a.book_id = b and lower(a.name) = lower(btrim(r ->> 'account')) and a.deleted_at is null limit 1;
    if acc is null then
      insert into public.accounts (group_id, name, currency) values (others, coalesce(nullif(btrim(r ->> 'account'), ''), 'Imported'), nullif(r ->> 'currency', ''))
      returning id into acc;
      made_acc := made_acc + 1;
    end if;
    acc_to := null; cat := null; sub := null;
    if k = 'transfer' then
      select a.id into acc_to from public.accounts a where a.book_id = b and lower(a.name) = lower(btrim(r ->> 'to_account')) and a.deleted_at is null limit 1;
      if acc_to is null then
        insert into public.accounts (group_id, name) values (others, coalesce(nullif(btrim(r ->> 'to_account'), ''), 'Imported'))
        returning id into acc_to;
        made_acc := made_acc + 1;
      end if;
    elsif nullif(btrim(coalesce(r ->> 'category', '')), '') is not null then
      select c.id into cat from public.categories c where c.book_id = b and c.kind = k and c.parent_id is null and lower(c.name) = lower(btrim(r ->> 'category')) limit 1;
      if cat is null then
        insert into public.categories (kind, name, sort) values (k, btrim(r ->> 'category'), 1000 + made_cat) returning id into cat;
        made_cat := made_cat + 1;
      end if;
      if nullif(btrim(coalesce(r ->> 'subcategory', '')), '') is not null then
        select c.id into sub from public.categories c where c.parent_id = cat and lower(c.name) = lower(btrim(r ->> 'subcategory')) limit 1;
        if sub is null then
          insert into public.categories (kind, parent_id, name, sort) values (k, cat, btrim(r ->> 'subcategory'), 1000 + made_cat) returning id into sub;
          made_cat := made_cat + 1;
        end if;
      end if;
    end if;
    insert into public.txns (kind, at, account_id, to_account_id, category_id, amount, to_amount, rate, note, description)
    values (k, (r ->> 'date')::timestamp, acc, acc_to, coalesce(sub, cat), abs((r ->> 'amount')::numeric),
            nullif(r ->> 'to_amount', '')::numeric, nullif(r ->> 'rate', '')::numeric, r ->> 'note', r ->> 'description');
    n := n + 1;
  end loop;
  return jsonb_build_object('imported', n, 'accounts_made', made_acc, 'categories_made', made_cat);
end $$;
