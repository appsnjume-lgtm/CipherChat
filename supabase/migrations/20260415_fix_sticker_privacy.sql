begin;

drop policy if exists "stickers_select_public_or_owner" on public.stickers;

create policy "stickers_select_public_or_owner"
on public.stickers
for select
to anon, authenticated
using (
  is_public = true
  or user_id = auth.uid()
);

update storage.buckets
set public = false
where id = 'stickers';

drop policy if exists "stickers_select_public" on storage.objects;

create policy "stickers_select_public_or_owner"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'stickers'
  and exists (
    select 1
    from public.stickers s
    where s.storage_path = name
      and (
        s.is_public = true
        or s.user_id = auth.uid()
      )
  )
);

commit;
