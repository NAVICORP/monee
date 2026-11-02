-- Monee, stage 1: books and the people in them.
--
-- A book is one person's (or one family's) money: its accounts, categories
-- and transactions. Every row carries book_id, and one function,
-- current_book_id(), decides which book the signed-in person is working in.
-- Every policy asks it.
--
-- People sign in through SkAuth (account.skifi.co). Anyone signed in can start
-- a book and is its owner. Shared books (a partner who edits, a parent who
-- only looks) are book_members rows; the app sends the book it is working in
-- as the x-book-id header.

-- ---------------------------------------------------------------- small helpers

create or replace function public.clean_email(e text) returns text
language sql immutable set search_path = '' as $$
  select nullif(lower(btrim(coalesce(e, ''))), '');
$$;

create or replace function public.my_phone() returns text
language sql stable set search_path = '' as $$
  select nullif(regexp_replace(coalesce(auth.jwt() ->> 'phone', ''), '[^0-9]', '', 'g'), '');
$$;

create or replace function public.my_email() returns text
language sql stable set search_path = '' as $$
  select public.clean_email(auth.email());
$$;

-- The book the app asked for, when it is a valid id. The shared SkiFi app
-- base passes one app header through to the database, x-farm-id (named for
-- the first app on it), so the app sends the book there; x-book-id is read
-- too, for tests and a later base.
create or replace function public.requested_book() returns uuid
language plpgsql stable set search_path = '' as $$
declare v text := nullif(btrim(coalesce(current_setting('request.headers', true)::jsonb ->> 'x-book-id',
                                        current_setting('request.headers', true)::jsonb ->> 'x-farm-id', '')), '');
begin
  if v is null or v !~ '^[0-9a-fA-F-]{36}$' then return null; end if;
  return v::uuid;
exception when others then
  return null;
end $$;

-- True inside a security definer function or the server's own work, false for
-- a person writing through the API.
create or replace function public.trusted_writer() returns boolean
language sql stable set search_path = '' as $$
  select current_user not in ('anon', 'authenticated');
$$;

-- ---------------------------------------------------------------- books

create table public.books (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(btrim(name)) between 1 and 60),
  currency         text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),   -- the main currency
  timezone         text not null default 'Asia/Kolkata',
  -- Periods. A month runs from month_start_day; a day past the month's end
  -- means its last day. Weeks start on week_start (0 Sunday .. 6 Saturday).
  month_start_day  int  not null default 1 check (month_start_day between 1 and 31),
  week_start       int  not null default 0 check (week_start between 0 and 6),
  fy_start_month   int  not null default 1 check (fy_start_month between 1 and 12),
  -- How the Trans tab opens and adds up.
  start_screen     text not null default 'daily' check (start_screen in ('daily', 'calendar')),
  carry_over       boolean not null default false,
  subcategories    boolean not null default true,
  -- Card spending counts as expense on the day it was spent ('at_time'), or as
  -- one lump on the day the card is paid ('lump_sum').
  card_display     text not null default 'at_time' check (card_display in ('at_time', 'lump_sum')),
  -- Upcoming repeats show on their own date, or from the first day of their month.
  repeat_show      text not null default 'on_date' check (repeat_show in ('on_date', 'month_start')),
  created_by       uuid,
  created_at       timestamptz not null default now()
);

create or replace function public.books_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.name := btrim(new.name);
  new.currency := upper(btrim(new.currency));
  begin
    perform now() at time zone new.timezone;
  exception when others then
    raise exception 'Unknown time zone %.', new.timezone using errcode = '22023';
  end;
  if tg_op = 'UPDATE' then
    if not public.trusted_writer() then
      new.created_by := old.created_by;
      new.created_at := old.created_at;
    end if;
    -- The main currency changes through set_main_currency, which moves the rates with it.
    if new.currency is distinct from old.currency and not public.trusted_writer() then
      raise exception 'Change the main currency from Currencies.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger books_check before insert or update on public.books
  for each row execute function public.books_check();

-- The book's clock. Never current_date: the server runs in UTC.
create or replace function public.book_now(b uuid) returns timestamp
language sql stable set search_path = '' as $$
  select now() at time zone coalesce((select x.timezone from public.books x where x.id = b), 'Asia/Kolkata');
$$;

create or replace function public.book_today(b uuid) returns date
language sql stable set search_path = '' as $$
  select public.book_now(b)::date;
$$;

-- ---------------------------------------------------------------- members

create table public.book_members (
  id            uuid primary key default gen_random_uuid(),
  book_id       uuid not null references public.books (id) on delete cascade,
  user_id       uuid,                     -- the sign-in; null until they first sign in
  name          text not null check (char_length(btrim(name)) between 1 and 60),
  email         text check (email = lower(btrim(email))),
  phone         text check (phone ~ '^[0-9]{8,15}$'),
  role          text not null default 'editor' check (role in ('owner', 'editor', 'viewer')),
  created_at    timestamptz not null default now()
);
create unique index book_members_user on public.book_members (book_id, user_id) where user_id is not null;
create unique index book_members_email on public.book_members (book_id, email) where email is not null;
create unique index book_members_phone on public.book_members (book_id, phone) where phone is not null;
create index book_members_by_user on public.book_members (user_id) where user_id is not null;

-- ---------------------------------------------------------------- the boundary

create or replace function public.current_book_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.book_id from public.book_members m
  where m.user_id = auth.uid()
  order by (m.book_id = public.requested_book()) desc nulls last, m.created_at
  limit 1;
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select m.role from public.book_members m
  where m.user_id = auth.uid() and m.book_id = public.current_book_id()
  limit 1;
$$;

create or replace function public.can_edit() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_role() in ('owner', 'editor'), false);
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_role() = 'owner', false);
$$;

create or replace function public.my_name() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select m.name from public.book_members m where m.user_id = auth.uid() and m.book_id = public.current_book_id()),
    public.my_email(),
    case when public.my_phone() is not null then '+' || public.my_phone() end,
    'Someone');
$$;

-- Every book table's book_id defaults to the book being worked in.
alter table public.book_members alter column book_id set default public.current_book_id();

-- ---------------------------------------------------------------- member rules

create or replace function public.book_members_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.name := btrim(new.name);
  new.email := public.clean_email(new.email);
  new.phone := nullif(regexp_replace(coalesce(new.phone, ''), '[^0-9]', '', 'g'), '');
  if tg_op = 'UPDATE' and new.book_id is distinct from old.book_id then
    raise exception 'A member cannot move between books.' using errcode = '42501';
  end if;
  if public.trusted_writer() then return new; end if;
  -- A sign-in links itself when its owner first signs in (claim_books).
  if new.user_id is not null and (tg_op = 'INSERT' or new.user_id is distinct from old.user_id) then
    raise exception 'A person is linked when they first sign in.' using errcode = '42501';
  end if;
  if new.role = 'owner' and (tg_op = 'INSERT' or old.role <> 'owner') then
    raise exception 'A book has one owner.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner' then
    raise exception 'The owner stays the owner.' using errcode = '42501';
  end if;
  if new.email is null and new.phone is null then
    raise exception 'Add their email or WhatsApp number.' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger book_members_check before insert or update on public.book_members
  for each row execute function public.book_members_check();

create or replace function public.book_members_delete_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not public.trusted_writer() and old.role = 'owner'
     and exists (select 1 from public.books b where b.id = old.book_id) then
    raise exception 'The owner cannot be removed. Delete the book instead.' using errcode = '42501';
  end if;
  return old;
end $$;
create trigger book_members_delete_check before delete on public.book_members
  for each row execute function public.book_members_delete_check();

-- ---------------------------------------------------------------- row level security

alter table public.books enable row level security;
alter table public.book_members enable row level security;

create policy books_read on public.books for select to authenticated
  using (id in (select m.book_id from public.book_members m where m.user_id = auth.uid()));
create policy books_write on public.books for update to authenticated
  using (id = (select public.current_book_id()) and (select public.is_owner()))
  with check (id = (select public.current_book_id()));
revoke insert, delete on public.books from anon, authenticated;
revoke all on public.books from anon;

create policy members_read on public.book_members for select to authenticated
  using (book_id = (select public.current_book_id()));
create policy members_insert on public.book_members for insert to authenticated
  with check (book_id = (select public.current_book_id()) and (select public.is_owner()));
create policy members_update on public.book_members for update to authenticated
  using (book_id = (select public.current_book_id()) and (select public.is_owner()))
  with check (book_id = (select public.current_book_id()));
create policy members_delete on public.book_members for delete to authenticated
  using (book_id = (select public.current_book_id())
         and ((select public.is_owner()) or user_id = auth.uid()));
revoke all on public.book_members from anon;

-- ---------------------------------------------------------------- signing in

-- Links member rows waiting for this person (by verified number or email).
create or replace function public.claim_books() returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if auth.uid() is null then return 0; end if;
  update public.book_members m set user_id = auth.uid()
   where m.user_id is null
     and ((public.my_phone() is not null and m.phone = public.my_phone())
       or (public.my_email() is not null and m.email = public.my_email()))
     and not exists (select 1 from public.book_members o where o.book_id = m.book_id and o.user_id = auth.uid());
  get diagnostics n = row_count;
  return n;
end $$;

-- Who is signed in, and every book they can open.
create or replace function public.whoami() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare books jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('id', null, 'books', '[]'::jsonb);
  end if;
  perform public.claim_books();
  select coalesce(jsonb_agg(jsonb_build_object(
      'book_id', b.id, 'name', b.name, 'currency', b.currency, 'timezone', b.timezone,
      'role', m.role, 'member_name', m.name, 'today', public.book_today(b.id),
      'month_start_day', b.month_start_day, 'week_start', b.week_start, 'fy_start_month', b.fy_start_month,
      'start_screen', b.start_screen, 'carry_over', b.carry_over, 'subcategories', b.subcategories,
      'card_display', b.card_display, 'repeat_show', b.repeat_show)
      order by m.created_at), '[]'::jsonb)
    into books
    from public.book_members m join public.books b on b.id = m.book_id
   where m.user_id = auth.uid();
  return jsonb_build_object('id', auth.uid(), 'email', public.my_email(), 'phone', public.my_phone(), 'books', books);
end $$;

-- Filled in by later migrations (starter groups, accounts and categories).
create or replace function public.seed_book(b uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  null;
end $$;

-- Anyone signed in can start a book, and owns it.
create or replace function public.create_book(name text default 'My money', currency text default 'INR',
  timezone text default 'Asia/Kolkata', my_name text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b public.books%rowtype; n text := coalesce(nullif(btrim(create_book.name), ''), 'My money');
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  if (select count(*) from public.books x where x.created_by = auth.uid()) >= 10 then
    raise exception 'You already have 10 books.' using errcode = '22023';
  end if;
  insert into public.books (name, currency, timezone, created_by)
  values (n, upper(coalesce(nullif(btrim(create_book.currency), ''), 'INR')),
          coalesce(nullif(btrim(create_book.timezone), ''), 'Asia/Kolkata'), auth.uid())
  returning * into b;
  insert into public.book_members (book_id, user_id, name, email, phone, role)
  values (b.id, auth.uid(),
          coalesce(nullif(btrim(create_book.my_name), ''), public.my_email(), '+' || public.my_phone(), 'Me'),
          public.my_email(), public.my_phone(), 'owner');
  perform public.seed_book(b.id);
  return jsonb_build_object('book_id', b.id, 'name', b.name, 'currency', b.currency);
end $$;

-- The owner deletes the whole book, typing its name to confirm.
create or replace function public.delete_book(confirm_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare b public.books%rowtype;
begin
  if not public.is_owner() then raise exception 'Only the owner can delete the book.' using errcode = '42501'; end if;
  select * into b from public.books x where x.id = public.current_book_id();
  if lower(btrim(coalesce(confirm_name, ''))) <> lower(b.name) then
    raise exception 'Type the book''s name exactly to delete it.' using errcode = '22023';
  end if;
  delete from public.books x where x.id = b.id;
end $$;

-- Before an account is deleted (a store requirement): every book they own
-- goes, and they leave the books they were only a member of.
create or replace function public.delete_my_data() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  delete from public.books b
   where b.id in (select m.book_id from public.book_members m where m.user_id = auth.uid() and m.role = 'owner');
  delete from public.book_members m where m.user_id = auth.uid();
  delete from auth.users u where u.id = auth.uid();
end $$;
