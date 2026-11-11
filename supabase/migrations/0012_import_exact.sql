-- Import from Excel, exactly as the file has it (11 Nov 2026).
--
-- Each row now says the account's own currency, the amount in it, the rate
-- of that day (main currency per unit), and for transfers the other
-- account's currency and what arrived there. New accounts are made in
-- their own currency (the other side of a transfer too), tags are kept,
-- and an owner can start the book over: its entries and accounts are
-- deleted before the first rows go in. Currencies without a rate in the
-- book get the latest rate the file used.

drop function if exists public.import_rows(jsonb);

create or replace function public.import_rows(rows jsonb, fresh boolean default false) returns jsonb
language plpgsql set search_path = '' as $$
declare b uuid := public.current_book_id(); r jsonb; acc uuid; acc_to uuid; cat uuid; sub uuid; k text; n int := 0;
  others uuid; made_acc int := 0; made_cat int := 0; t_id uuid; tag text; tag_id uuid; main text; c text;
begin
  if not public.can_edit() then raise exception 'You can only look at this book.' using errcode = '42501'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) > 20000 then
    raise exception 'Import up to 20000 rows at a time.' using errcode = '22023';
  end if;
  main := (select x.currency from public.books x where x.id = b);
  if fresh then
    if not public.is_owner() then raise exception 'Only the book''s owner can start it over.' using errcode = '42501'; end if;
    delete from public.txns t where t.book_id = b;
    delete from public.accounts a where a.book_id = b;
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
    -- The account, by name, made in its own currency when new.
    select a.id into acc from public.accounts a where a.book_id = b and lower(a.name) = lower(btrim(r ->> 'account')) and a.deleted_at is null limit 1;
    if acc is null then
      insert into public.accounts (group_id, name, currency)
      values (others, coalesce(nullif(btrim(r ->> 'account'), ''), 'Imported'), nullif(upper(btrim(coalesce(r ->> 'currency', ''))), ''))
      returning id into acc;
      made_acc := made_acc + 1;
    end if;
    acc_to := null; cat := null; sub := null;
    if k = 'transfer' then
      select a.id into acc_to from public.accounts a where a.book_id = b and lower(a.name) = lower(btrim(r ->> 'to_account')) and a.deleted_at is null limit 1;
      if acc_to is null then
        insert into public.accounts (group_id, name, currency)
        values (others, coalesce(nullif(btrim(r ->> 'to_account'), ''), 'Imported'),
                nullif(upper(btrim(coalesce(r ->> 'to_currency', r ->> 'currency', ''))), ''))
        returning id into acc_to;
        made_acc := made_acc + 1;
      end if;
    elsif nullif(btrim(coalesce(r ->> 'category', '')), '') is not null then
      select c2.id into cat from public.categories c2 where c2.book_id = b and c2.kind = k and c2.parent_id is null and lower(c2.name) = lower(btrim(r ->> 'category')) limit 1;
      if cat is null then
        insert into public.categories (kind, name, sort) values (k, btrim(r ->> 'category'), 1000 + made_cat) returning id into cat;
        made_cat := made_cat + 1;
      end if;
      if nullif(btrim(coalesce(r ->> 'subcategory', '')), '') is not null then
        select c2.id into sub from public.categories c2 where c2.parent_id = cat and lower(c2.name) = lower(btrim(r ->> 'subcategory')) limit 1;
        if sub is null then
          insert into public.categories (kind, parent_id, name, sort) values (k, cat, btrim(r ->> 'subcategory'), 1000 + made_cat) returning id into sub;
          made_cat := made_cat + 1;
        end if;
      end if;
    end if;
    -- A currency the book has no rate for yet takes the first rate the file gives.
    c := (select a.currency from public.accounts a where a.id = acc);
    if c <> main and nullif(r ->> 'rate', '') is not null
       and not exists (select 1 from public.currency_rates x where x.book_id = b and x.currency = c) then
      insert into public.currency_rates (currency, rate) values (c, (r ->> 'rate')::numeric);
    end if;
    -- A rate the file gives is the rate of that day; it is only kept for an
    -- account in another currency (the main currency is always 1).
    insert into public.txns (kind, at, account_id, to_account_id, category_id, amount, to_amount, rate, note, description)
    values (k, (r ->> 'date')::timestamp, acc, acc_to, coalesce(sub, cat), abs((r ->> 'amount')::numeric),
            case when k = 'transfer' then nullif(r ->> 'to_amount', '')::numeric end,
            case when (select a.currency from public.accounts a where a.id = acc) = main then null
                 else nullif(r ->> 'rate', '')::numeric end,
            nullif(r ->> 'note', ''), nullif(r ->> 'description', ''))
    returning id into t_id;
    if jsonb_typeof(r -> 'tags') = 'array' then
      for tag in select left(btrim(x), 30) from jsonb_array_elements_text(r -> 'tags') x where btrim(x) <> '' loop
        select g.id into tag_id from public.tags g where g.book_id = b and lower(g.name) = lower(tag);
        if tag_id is null then insert into public.tags (name) values (tag) returning id into tag_id; end if;
        insert into public.txn_tags (txn_id, tag_id) values (t_id, tag_id) on conflict do nothing;
      end loop;
    end if;
    n := n + 1;
  end loop;
  -- Rates in the book follow the latest rate the file used.
  for c in select distinct a.currency from public.accounts a where a.book_id = b and a.currency <> main loop
    update public.currency_rates x set rate = l.rate
      from (select t.rate from public.txns t join public.accounts a on a.id = t.account_id
             where t.book_id = b and a.currency = c and t.rate is not null order by t.at desc limit 1) l
     where x.book_id = b and x.currency = c and fresh;
  end loop;
  return jsonb_build_object('imported', n, 'accounts_made', made_acc, 'categories_made', made_cat);
end $$;

revoke execute on function public.import_rows(jsonb, boolean) from public, anon, authenticated;
grant execute on function public.import_rows(jsonb, boolean) to authenticated;
