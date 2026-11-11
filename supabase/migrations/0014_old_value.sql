-- Pursee, stage 14: old money keeps its old value.
--
-- A balance in another currency is worth, in the main currency, what each of
-- its entries was worth on its own day (txns.rate), not the balance at
-- today's rate. Only the opening balance, which has no date, uses today's
-- rate. A transfer into the account carries the main-currency value that
-- left the other account.

create or replace view public.account_moves with (security_invoker = true) as
  select t.book_id, t.id as txn_id, t.at, coalesce(a.linked_account_id, a.id) as account_id, t.account_id as via_account_id,
         case t.kind when 'income' then t.amount else -(t.amount + t.fee) end as delta,
         round(case t.kind when 'income' then t.amount else -(t.amount + t.fee) end * t.rate, 4) as delta_main
    from public.txns t join public.accounts a on a.id = t.account_id
  union all
  select t.book_id, t.id, t.at, coalesce(a.linked_account_id, a.id), t.to_account_id, t.to_amount,
         round(t.amount * t.rate, 4)
    from public.txns t join public.accounts a on a.id = t.to_account_id
   where t.kind = 'transfer';
revoke all on public.account_moves from anon;
revoke insert, update, delete on public.account_moves from authenticated;

-- An account's balance at the end of a day, in the main currency, at the
-- rates of the days its money came and went.
create or replace function public.balance_main_at(account uuid, until date) returns numeric
language sql stable security definer set search_path = '' as $$
  select case when a.currency = b.currency then public.balance_at(a.id, until)
              when public.balance_at(a.id, until) = 0 then 0
              else case when a.opening_balance = 0 then 0 else round(a.opening_balance * public.rate_of(b.id, a.currency), 4) end
                   + coalesce((select sum(m.delta_main) from public.account_moves m
                                where m.account_id = a.id and m.at < until + 1), 0) end
    from public.accounts a join public.books b on b.id = a.book_id
   where a.id = account and a.book_id = public.current_book_id();
$$;
revoke execute on function public.balance_main_at(uuid, date) from public, anon, authenticated;
grant execute on function public.balance_main_at(uuid, date) to authenticated;

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
    select x.*, case when x.balance is null then null else public.balance_main_at(x.id, today) end as balance_main,
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

-- Assets, liabilities and total at each month's end, each entry at its own day's rate.
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
        from (select coalesce(public.balance_main_at(a.id, d), 0) as v
                from public.accounts a join public.account_groups g on g.id = a.group_id
               where a.book_id = b and a.in_totals and a.deleted_at is null and g.kind <> 'debit_card') x;
      out := jsonb_build_object('year', y, 'month', m, 'to', d, 'assets', pos, 'liabilities', neg, 'total', pos - neg) || out;
    end if;
    m := m - 1; if m < 1 then m := 12; y := y - 1; end if;
  end loop;
  return out;
end $$;
