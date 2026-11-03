-- Pursee, stage 11: feature requests. Anyone signed in asks for something new
-- from inside the app (More > Request a feature) and follows what happened
-- to it; the people who make Pursee read every request in the app's own
-- inbox, which shows only for them. The same as Kuree's.
--
-- Who counts as an owner is listed in app_owners, by email. To add or
-- remove someone, run on the database:
--   insert into public.app_owners (email) values ('someone@skifi.co');
--   delete from public.app_owners where email = 'someone@skifi.co';

-- ---------------------------------------------------------------- tables

create table public.app_owners (
  email    text primary key check (email = lower(btrim(email)) and email like '%_@_%._%'),
  added_at timestamptz not null default now()
);
insert into public.app_owners (email) values ('contact@skifi.co'), ('ishaque@skifi.co')
  on conflict do nothing;

create table public.feature_requests (
  id          bigserial primary key,
  user_id     uuid,
  email       text,
  phone       text,
  name        text check (char_length(name) <= 60),
  title       text not null check (char_length(title) between 3 and 100),
  details     text not null default '' check (char_length(details) <= 2000),
  importance  text check (importance in ('nice', 'important', 'must')),
  app_version text check (char_length(app_version) <= 32),
  platform    text check (platform in ('android', 'ios', 'web', 'other')),
  language    text check (char_length(language) <= 16),
  status      text not null default 'new' check (status in ('new', 'planned', 'done', 'declined')),
  owner_note  text not null default '' check (char_length(owner_note) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index feature_requests_new on public.feature_requests (created_at desc, id desc);
create index feature_requests_by_user on public.feature_requests (user_id, created_at desc) where user_id is not null;

-- Nothing is read or written directly: only through the functions below.
alter table public.app_owners enable row level security;
alter table public.feature_requests enable row level security;
revoke all on public.app_owners, public.feature_requests from anon, authenticated;
revoke all on sequence public.feature_requests_id_seq from anon, authenticated;

-- ---------------------------------------------------------------- helpers

-- Text as people type it, made safe to keep and show: no control characters
-- or angle brackets, no spaces at the ends, at most two empty lines in a row.
create or replace function public.clean_text(t text, one_line boolean default false) returns text
language sql immutable set search_path = '' as $$
  select case when one_line
    then btrim(regexp_replace(regexp_replace(coalesce(t, ''), '[[:cntrl:]<>]', ' ', 'g'), '\s+', ' ', 'g'))
    else btrim(regexp_replace(
           regexp_replace(regexp_replace(coalesce(t, ''), E'\r\n?', E'\n', 'g'), E'[\\x01-\\x09\\x0B-\\x1F\\x7F<>]', ' ', 'g'),
           E'\n{3,}', E'\n\n', 'g'))
  end;
$$;

-- Is the signed-in person one of the people who make Pursee?
create or replace function public.feature_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.my_email() is not null and exists (select 1 from public.app_owners o where o.email = public.my_email());
$$;

-- One request as the app shows it. Owners also see who sent it.
create or replace function public.feature_request_json(r public.feature_requests, with_sender boolean) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'title', r.title, 'details', r.details, 'importance', r.importance,
    'status', r.status, 'owner_note', r.owner_note, 'created_at', r.created_at, 'updated_at', r.updated_at)
    || case when with_sender then jsonb_build_object(
      'name', r.name, 'email', r.email, 'phone', r.phone, 'app_version', r.app_version,
      'platform', r.platform, 'language', r.language, 'signed_up', r.user_id is not null)
    else '{}'::jsonb end;
$$;

-- ---------------------------------------------------------------- asking

-- Someone asks for a feature. Up to 5 an hour and 20 a day per person.
create or replace function public.request_feature(
  title text, details text default '', importance text default null,
  app_version text default null, platform text default null, language text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t text := public.clean_text(request_feature.title, true);
  d text := public.clean_text(request_feature.details);
  i text := nullif(lower(btrim(coalesce(request_feature.importance, ''))), '');
  v text := nullif(btrim(coalesce(request_feature.app_version, '')), '');
  p text := lower(btrim(coalesce(request_feature.platform, '')));
  l text := nullif(btrim(coalesce(request_feature.language, '')), '');
  rec public.feature_requests;
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  if char_length(t) < 3 then raise exception 'Give your idea a short title.' using errcode = '22023'; end if;
  if char_length(t) > 100 then raise exception 'Keep the title under 100 characters.' using errcode = '22023'; end if;
  if char_length(d) > 2000 then raise exception 'Keep the details under 2000 characters.' using errcode = '22023'; end if;
  if i is not null and i not in ('nice', 'important', 'must') then i := null; end if;
  if v is not null and v !~ '^[0-9A-Za-z.+_-]{1,32}$' then v := null; end if;
  if p not in ('android', 'ios', 'web') then p := case when p = '' then null else 'other' end; end if;
  if l is not null and l !~ '^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})?$' then l := null; end if;
  if (select count(*) from public.feature_requests f
       where f.user_id = auth.uid() and f.created_at > now() - interval '1 hour') >= 5
     or (select count(*) from public.feature_requests f
       where f.user_id = auth.uid() and f.created_at > now() - interval '1 day') >= 20 then
    raise exception 'Too many requests for now. Try again later.' using errcode = '54000';
  end if;
  insert into public.feature_requests (user_id, email, phone, name, title, details, importance, app_version, platform, language)
  values (auth.uid(), public.my_email(), public.my_phone(), left(public.my_name(), 60), t, d, i, v, p, l)
  returning * into rec;
  return public.feature_request_json(rec, false);
end $$;

-- The signed-in person's own requests, newest first, with their status.
create or replace function public.my_feature_requests() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(public.feature_request_json(f.x, false) order by (f.x).created_at desc, (f.x).id desc)
    from (select x from public.feature_requests x where x.user_id = auth.uid() order by x.created_at desc, x.id desc limit 100) f
  ), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------- the owner inbox

-- Every request, newest first, optionally only one status. Owners only.
create or replace function public.all_feature_requests(status text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare s text := nullif(lower(btrim(coalesce(all_feature_requests.status, ''))), '');
begin
  if not public.feature_owner() then
    raise exception 'Only the Pursee team can see every request.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'counts', (select jsonb_build_object(
        'new', count(*) filter (where f.status = 'new'),
        'planned', count(*) filter (where f.status = 'planned'),
        'done', count(*) filter (where f.status = 'done'),
        'declined', count(*) filter (where f.status = 'declined'),
        'all', count(*))
      from public.feature_requests f),
    'requests', coalesce((
      select jsonb_agg(public.feature_request_json(f.x, true) order by (f.x).created_at desc, (f.x).id desc)
      from (select x from public.feature_requests x
             where s is null or x.status = s
             order by x.created_at desc, x.id desc limit 500) f
    ), '[]'::jsonb));
end $$;

-- An owner marks a request as new, planned, done or declined, with an
-- optional note the person who asked can read. Owners only.
create or replace function public.set_feature_request_status(id bigint, status text, note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s text := lower(btrim(coalesce(set_feature_request_status.status, '')));
  n text := public.clean_text(set_feature_request_status.note);
  rec public.feature_requests;
begin
  if not public.feature_owner() then
    raise exception 'Only the Pursee team can change a request.' using errcode = '42501';
  end if;
  if s not in ('new', 'planned', 'done', 'declined') then
    raise exception 'Pick new, planned, done or declined.' using errcode = '22023';
  end if;
  if char_length(n) > 500 then raise exception 'Keep the note under 500 characters.' using errcode = '22023'; end if;
  update public.feature_requests f
     set status = s,
         owner_note = case when set_feature_request_status.note is null then f.owner_note else n end,
         updated_at = now()
   where f.id = set_feature_request_status.id
  returning * into rec;
  if not found then raise exception 'That request was not found.' using errcode = 'P0002'; end if;
  return public.feature_request_json(rec, true);
end $$;

-- ---------------------------------------------------------------- deleting an account

-- When an account is deleted, its requests stay as ideas but without the
-- name, email or number of the person who sent them.
create or replace function public.forget_feature_requests() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.feature_requests f set user_id = null, email = null, phone = null, name = null
   where f.user_id = old.id;
  return old;
end $$;
drop trigger if exists feature_requests_forget on auth.users;
create trigger feature_requests_forget after delete on auth.users
  for each row execute function public.forget_feature_requests();

-- ---------------------------------------------------------------- who may call what

revoke execute on function
  public.clean_text(text, boolean), public.feature_owner(), public.feature_request_json(public.feature_requests, boolean),
  public.request_feature(text, text, text, text, text, text), public.my_feature_requests(),
  public.all_feature_requests(text), public.set_feature_request_status(bigint, text, text),
  public.forget_feature_requests()
  from public, anon, authenticated;
grant execute on function
  public.feature_owner(), public.request_feature(text, text, text, text, text, text), public.my_feature_requests(),
  public.all_feature_requests(text), public.set_feature_request_status(bigint, text, text)
  to authenticated;
