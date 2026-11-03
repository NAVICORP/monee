-- Pursee, stage 10: one entry paid from several accounts.
--
-- A purchase paid partly in cash and partly by card is saved as one
-- transaction per account, linked by the same pay_group. Each part is an
-- ordinary transaction, so balances, cards, budgets, stats and exports need
-- nothing new. The app opens, edits, copies and deletes the parts together.

alter table public.txns add column if not exists pay_group uuid;
create index if not exists txns_pay_group on public.txns (pay_group) where pay_group is not null;

-- Saves every part of an entry in one go. `parts` holds what save_txn takes,
-- one per account (with id for a part that is already there). `group_id` is
-- the entry's group when it already has one: parts left out are deleted.
-- One part alone is an ordinary transaction again.
create or replace function public.save_txn_group(parts jsonb, group_id uuid default null) returns jsonb
language plpgsql set search_path = '' as $$
declare g uuid := coalesce(group_id, gen_random_uuid()); part jsonb; res jsonb; ids uuid[] := '{}'; n int;
begin
  if not public.can_edit() then raise exception 'You can only look at this book.' using errcode = '42501'; end if;
  if jsonb_typeof(parts) is distinct from 'array' or jsonb_array_length(parts) < 1 then
    raise exception 'There is nothing to save.' using errcode = '22023';
  end if;
  n := jsonb_array_length(parts);
  if n > 10 then raise exception 'Pay from up to 10 accounts.' using errcode = '22023'; end if;
  for part in select * from jsonb_array_elements(parts) loop
    if n > 1 and coalesce(part ->> 'kind', '') not in ('income', 'expense') then
      raise exception 'Only income and expenses can be split between accounts.' using errcode = '22023';
    end if;
    res := public.save_txn(part);
    ids := ids || (res ->> 'id')::uuid;
  end loop;
  if (select count(distinct t.account_id) from public.txns t where t.id = any(ids)) < n then
    raise exception 'Use a different account for each part.' using errcode = '22023';
  end if;
  update public.txns t set pay_group = case when n > 1 then g end where t.id = any(ids);
  if group_id is not null then
    delete from public.txns t where t.pay_group = group_id and not (t.id = any(ids));
  end if;
  return jsonb_build_object('ids', to_jsonb(ids), 'group', case when n > 1 then g end);
end $$;

-- The list rows also say which entry a part belongs to, and how many parts it has.
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
               t.pay_group, (select count(*) from public.txns g where g.pay_group = t.pay_group) as pay_parts,
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

revoke execute on function public.save_txn_group(jsonb, uuid), public.txn_list(date, date, jsonb, int) from public, anon, authenticated;
grant execute on function public.save_txn_group(jsonb, uuid), public.txn_list(date, date, jsonb, int) to authenticated;
