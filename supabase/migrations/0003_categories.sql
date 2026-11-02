-- Monee, stage 3: categories (one level of subcategories), tags, and what a
-- new book starts with.

create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  kind        text not null check (kind in ('income', 'expense')),
  parent_id   uuid references public.categories (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  emoji       text check (char_length(emoji) <= 16),
  sort        int  not null default 0,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index categories_book on public.categories (book_id, kind, sort);
create index categories_parent on public.categories (parent_id) where parent_id is not null;

create table public.tags (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null default public.current_book_id() references public.books (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 30),
  created_at  timestamptz not null default now()
);
create unique index tags_book_name on public.tags (book_id, lower(name));

create or replace function public.categories_check() returns trigger
language plpgsql set search_path = '' as $$
declare p public.categories%rowtype;
begin
  new.name := btrim(new.name);
  new.emoji := nullif(btrim(coalesce(new.emoji, '')), '');
  if tg_op = 'UPDATE' then
    if new.book_id is distinct from old.book_id then
      raise exception 'A category cannot move between books.' using errcode = '42501';
    end if;
    if new.kind is distinct from old.kind then
      raise exception 'An income category stays income, an expense category stays expense.' using errcode = '22023';
    end if;
  end if;
  if new.parent_id is not null then
    select * into p from public.categories c where c.id = new.parent_id;
    if p.book_id is distinct from new.book_id or p.kind is distinct from new.kind or p.id = new.id then
      raise exception 'A subcategory sits under a category of the same kind in this book.' using errcode = '22023';
    end if;
    if p.parent_id is not null then
      raise exception 'Subcategories go one level deep.' using errcode = '22023';
    end if;
    if exists (select 1 from public.categories c where c.parent_id = new.id) then
      raise exception 'This category has its own subcategories, so it cannot become one.' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
create trigger categories_check before insert or update on public.categories
  for each row execute function public.categories_check();

create or replace function public.tags_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.name := regexp_replace(btrim(new.name), '^#', '');
  if tg_op = 'UPDATE' and new.book_id is distinct from old.book_id then
    raise exception 'A tag cannot move between books.' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger tags_check before insert or update on public.tags
  for each row execute function public.tags_check();

do $$
declare t text;
begin
  foreach t in array array['categories', 'tags'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (book_id = (select public.current_book_id()))', t || '_read', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit())) with check (book_id = (select public.current_book_id()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (book_id = (select public.current_book_id()) and (select public.can_edit()))', t || '_delete', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- a new book

create or replace function public.seed_book(b uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare g_cash uuid; g_bank uuid; cur text := (select x.currency from public.books x where x.id = b);
  r record; parent uuid; i int := 0; j int;
begin
  -- Groups, in the order the Accounts tab shows them.
  insert into public.account_groups (book_id, name, emoji, kind, sort) values (b, 'Cash', '💵', 'cash', 10) returning id into g_cash;
  insert into public.account_groups (book_id, name, emoji, kind, sort) values (b, 'Bank', '🏦', 'bank', 20) returning id into g_bank;
  insert into public.account_groups (book_id, name, emoji, kind, sort) values
    (b, 'Cards',        '💳', 'card',       30),
    (b, 'Debit cards',  '🪪', 'debit_card', 40),
    (b, 'Wallets',      '👛', 'prepaid',    50),
    (b, 'Savings',      '🐷', 'savings',    60),
    (b, 'Investments',  '📈', 'investment', 70),
    (b, 'Loans',        '🏠', 'loan',       80),
    (b, 'Insurance',    '☂️', 'insurance',  90),
    (b, 'Others',       '🗂️', 'other',     100);
  insert into public.accounts (book_id, group_id, name, currency, sort) values
    (b, g_cash, 'Cash', cur, 10),
    (b, g_bank, 'Bank account', cur, 10);

  -- Categories, each with a few subcategories.
  for r in select * from (values
      ('expense', 'Food',          '🍜', array['Groceries', 'Eating out', 'Snacks']),
      ('expense', 'Transport',     '🚕', array['Fuel', 'Taxi', 'Bus and train', 'Parking']),
      ('expense', 'Home',          '🏠', array['Rent', 'Maintenance', 'Household']),
      ('expense', 'Bills',         '🧾', array['Electricity', 'Water', 'Phone', 'Internet']),
      ('expense', 'Shopping',      '🛍️', array['Clothes', 'Electronics']),
      ('expense', 'Health',        '💊', array['Doctor', 'Medicine']),
      ('expense', 'Family',        '👨‍👩‍👧', array['Support', 'Kids']),
      ('expense', 'Education',     '📚', array[]::text[]),
      ('expense', 'Entertainment', '🎬', array[]::text[]),
      ('expense', 'Travel',        '✈️', array[]::text[]),
      ('expense', 'Gifts',         '🎁', array[]::text[]),
      ('expense', 'Personal care', '💇', array[]::text[]),
      ('expense', 'Other',         '🗂️', array[]::text[]),
      ('income',  'Salary',        '💼', array[]::text[]),
      ('income',  'Bonus',         '🎉', array[]::text[]),
      ('income',  'Business',      '🧾', array[]::text[]),
      ('income',  'Interest',      '🏦', array[]::text[]),
      ('income',  'Refund',        '↩️', array[]::text[]),
      ('income',  'Other',         '🗂️', array[]::text[])
    ) as v(kind, name, emoji, subs)
  loop
    i := i + 10;
    insert into public.categories (book_id, kind, name, emoji, sort) values (b, r.kind, r.name, r.emoji, i) returning id into parent;
    j := 0;
    for k in 1 .. coalesce(array_length(r.subs, 1), 0) loop
      j := j + 10;
      insert into public.categories (book_id, kind, parent_id, name, sort) values (b, r.kind, parent, r.subs[k], j);
    end loop;
  end loop;
end $$;
