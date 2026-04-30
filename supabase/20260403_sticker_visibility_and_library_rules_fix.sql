-- Make sticker metadata visible to all chat participants so sticker messages never
-- fail to render, while keeping library/favorite saves limited to public or
-- owner-controlled stickers.

create or replace function public.can_save_sticker(
  p_sticker_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.stickers s
    where s.id = p_sticker_id
      and (s.is_public or s.user_id = p_user_id)
  );
$$;

grant execute on function public.can_save_sticker(uuid, uuid) to authenticated;

drop policy if exists "stickers_select_public_or_owner" on public.stickers;
create policy "stickers_select_public_or_owner"
on public.stickers
for select
to anon, authenticated
using (is_public = true or user_id = auth.uid());

drop policy if exists "user_stickers_insert_owner_only" on public.user_stickers;
create policy "user_stickers_insert_owner_only"
on public.user_stickers
for insert
to authenticated
with check (
  auth.uid() = user_id
  and public.can_save_sticker(sticker_id, auth.uid())
);

drop policy if exists "user_stickers_update_owner_only" on public.user_stickers;
create policy "user_stickers_update_owner_only"
on public.user_stickers
for update
to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and public.can_save_sticker(sticker_id, auth.uid())
);
