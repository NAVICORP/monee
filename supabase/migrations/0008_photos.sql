-- Monee, stage 8: receipt photos.
--
-- The bytes sit on the server's disk (the app base's storage, volume
-- monee_storage); a row in storage.objects says the file exists, and these
-- policies decide who may see or change it. A photo's path starts with its
-- book: <book_id>/<txn_id>/<name>.jpg. txn_photos links it to a transaction.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('monee-photos', 'monee-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do nothing;

create or replace function public.path_book(name text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  return (string_to_array(name, '/'))[1]::uuid;
exception when others then
  return null;
end $$;

create policy monee_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'monee-photos' and public.path_book(name) = (select public.current_book_id()));
create policy monee_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'monee-photos' and public.path_book(name) = (select public.current_book_id()) and (select public.can_edit()));
create policy monee_photos_update on storage.objects for update to authenticated
  using (bucket_id = 'monee-photos' and public.path_book(name) = (select public.current_book_id()) and (select public.can_edit()));
create policy monee_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'monee-photos' and public.path_book(name) = (select public.current_book_id()) and (select public.can_edit()));

-- A photo row points at a file of its own book.
create or replace function public.txn_photos_path() returns trigger
language plpgsql set search_path = '' as $$
begin
  if public.path_book(new.path) is distinct from new.book_id then
    raise exception 'That photo is not in this book.' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger txn_photos_path before insert or update on public.txn_photos
  for each row execute function public.txn_photos_path();

revoke execute on function public.path_book(text), public.txn_photos_path() from public, anon, authenticated;
grant execute on function public.path_book(text) to authenticated;
