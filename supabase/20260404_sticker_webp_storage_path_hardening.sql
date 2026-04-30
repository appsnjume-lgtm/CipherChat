alter table public.stickers
  drop constraint if exists stickers_storage_path_extension_check,
  drop constraint if exists stickers_storage_path_matches_mime_type_check;

alter table public.stickers
  add constraint stickers_storage_path_extension_check
    check (lower(storage_path) ~ '^(system|users)/.+\.(png|jpe?g|webp)$'),
  add constraint stickers_storage_path_matches_mime_type_check
    check (
      (mime_type = 'image/png' and lower(storage_path) like '%.png')
      or (mime_type = 'image/jpeg' and (lower(storage_path) like '%.jpg' or lower(storage_path) like '%.jpeg'))
      or (mime_type = 'image/webp' and lower(storage_path) like '%.webp')
    );

create or replace function public.can_manage_sticker_storage_object(
  p_object_name text,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
as $$
  select coalesce(p_object_name, '') ~
    ('^users/' || p_user_id::text || '/[^/]+\.(png|jpe?g|webp)$');
$$;
