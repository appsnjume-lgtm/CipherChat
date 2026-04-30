-- ============================================================
-- Migration: add mime_type column to public.stickers
-- ============================================================
-- The column is declared in cipherchat_schema.sql but was not
-- yet present in the live database, which caused PostgREST to
-- return PGRST204 ("Could not find the 'mime_type' column …")
-- whenever the Flutter app tried to insert a new sticker.
--
-- This migration is safe to run multiple times (idempotent).
-- ============================================================

-- 1. Add the column if it does not exist yet.
alter table public.stickers
  add column if not exists mime_type text;

-- 2. Back-fill any existing rows that are still NULL.
--    All legacy stickers are PNG or JPEG; defaulting to 'image/png'
--    is the safest assumption.
update public.stickers
set mime_type = case
  when lower(storage_path) like '%.png'  then 'image/png'
  when lower(storage_path) like '%.jpg'  then 'image/jpeg'
  when lower(storage_path) like '%.jpeg' then 'image/jpeg'
  when lower(storage_path) like '%.webp' then 'image/webp'
  else 'image/png'
end
where mime_type is null;

-- 3. Make the column non-nullable with a sensible default going forward.
alter table public.stickers
  alter column mime_type set default 'image/png';

alter table public.stickers
  alter column mime_type set not null;

-- 4. Add the check constraint (drop first so re-runs don't error).
alter table public.stickers
  drop constraint if exists stickers_mime_type_check;

alter table public.stickers
  add constraint stickers_mime_type_check
  check (mime_type in ('image/png', 'image/jpeg', 'image/webp'));

-- ============================================================
-- Notify PostgREST to reload its schema cache.
-- (Supabase does this automatically after a migration runs;
--  the NOTIFY is included as a safety net for manual runs.)
-- ============================================================
notify pgrst, 'reload schema';
