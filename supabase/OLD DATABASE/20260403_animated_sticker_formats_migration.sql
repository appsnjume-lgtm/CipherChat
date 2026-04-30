-- Add explicit sticker mime-type support so static images and animated WebP
-- stickers can be rendered as images without flattening uploads.

alter table public.stickers
  add column if not exists mime_type text;

update public.stickers
set mime_type = case
  when lower(storage_path) like '%.webp' then 'image/webp'
  when lower(storage_path) like '%.jpg' then 'image/jpeg'
  when lower(storage_path) like '%.jpeg' then 'image/jpeg'
  when lower(storage_path) like '%.png' then 'image/png'
  else coalesce(nullif(trim(mime_type), ''), 'image/png')
end
where mime_type is null
   or trim(mime_type) = '';

alter table public.stickers
  alter column mime_type set default 'image/png';

alter table public.stickers
  alter column mime_type set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stickers'::regclass
      and conname = 'stickers_mime_type_check'
  ) then
    alter table public.stickers
      add constraint stickers_mime_type_check
      check (mime_type in ('image/png', 'image/jpeg', 'image/webp'));
  end if;
end
$$;
