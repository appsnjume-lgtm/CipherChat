-- Hybrid sticker system for CipherChat.
--
-- Recent stickers are intentionally derived from public.messages using the
-- sender_id + sticker_id + created_at indexes below, which avoids a third
-- write-path and keeps the source of truth single.

create extension if not exists pgcrypto;

create table if not exists public.stickers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete restrict,
  storage_path text not null,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  constraint stickers_storage_path_not_blank
    check (char_length(trim(storage_path)) > 0),
  constraint stickers_storage_path_prefix_check
    check (storage_path like 'system/%' or storage_path like 'users/%'),
  constraint stickers_owner_path_check
    check (
      (user_id is null and storage_path like 'system/%')
      or (user_id is not null and storage_path like ('users/' || user_id::text || '/%'))
    ),
  constraint stickers_system_public_check
    check (user_id is not null or is_public)
);

create table if not exists public.user_stickers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  sticker_id uuid not null references public.stickers (id) on delete cascade,
  is_favorite boolean not null default false,
  added_at timestamptz not null default now(),
  constraint user_stickers_unique unique (user_id, sticker_id)
);

alter table public.messages
  add column if not exists sticker_id uuid references public.stickers (id) on delete restrict;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stickers'::regclass
      and conname = 'stickers_storage_path_not_blank'
  ) then
    alter table public.stickers
      add constraint stickers_storage_path_not_blank
      check (char_length(trim(storage_path)) > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stickers'::regclass
      and conname = 'stickers_storage_path_prefix_check'
  ) then
    alter table public.stickers
      add constraint stickers_storage_path_prefix_check
      check (storage_path like 'system/%' or storage_path like 'users/%');
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stickers'::regclass
      and conname = 'stickers_owner_path_check'
  ) then
    alter table public.stickers
      add constraint stickers_owner_path_check
      check (
        (user_id is null and storage_path like 'system/%')
        or (user_id is not null and storage_path like ('users/' || user_id::text || '/%'))
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stickers'::regclass
      and conname = 'stickers_system_public_check'
  ) then
    alter table public.stickers
      add constraint stickers_system_public_check
      check (user_id is not null or is_public);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.user_stickers'::regclass
      and conname = 'user_stickers_unique'
  ) then
    alter table public.user_stickers
      add constraint user_stickers_unique unique (user_id, sticker_id);
  end if;
end
$$;

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages drop constraint if exists messages_sticker_reference_check;

alter table public.messages
  add constraint messages_type_check
  check (message_type in ('text', 'image', 'video', 'file', 'audio', 'sticker'));

alter table public.messages
  add constraint messages_sticker_reference_check
  check (
    (message_type = 'sticker' and (sticker_id is not null or deleted_for_everyone_at is not null))
    or (message_type <> 'sticker' and sticker_id is null)
  );

create index if not exists idx_messages_sticker_id
  on public.messages (sticker_id)
  where sticker_id is not null;

create index if not exists idx_messages_sender_sticker_recent
  on public.messages (sender_id, created_at desc)
  where message_type = 'sticker' and sticker_id is not null;

create index if not exists idx_stickers_public_created_at
  on public.stickers (created_at desc)
  where is_public = true;

create index if not exists idx_stickers_user_created_at
  on public.stickers (user_id, created_at desc)
  where user_id is not null;

create index if not exists idx_user_stickers_user_added_at
  on public.user_stickers (user_id, added_at desc);

create index if not exists idx_user_stickers_user_favorite_added_at
  on public.user_stickers (user_id, is_favorite, added_at desc);

create or replace function public.can_access_sticker(
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

create or replace function public.can_manage_sticker_storage_object(
  p_object_name text,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
as $$
  select
    split_part(coalesce(p_object_name, ''), '/', 1) = 'users'
    and split_part(coalesce(p_object_name, ''), '/', 2) = p_user_id::text
    and nullif(split_part(coalesce(p_object_name, ''), '/', 3), '') is not null;
$$;

create or replace function public.soft_delete_message_for_everyone(
  p_message_id uuid
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.messages;
begin
  update public.messages
  set payload_encrypted = jsonb_build_object('nonce', '', 'cipher_text', '', 'mac', ''),
      sticker_id = null,
      key_envelopes = '{}'::jsonb,
      deleted_for_everyone_at = coalesce(deleted_for_everyone_at, now()),
      deleted_for_everyone_by = coalesce(deleted_for_everyone_by, auth.uid())
  where id = p_message_id
    and sender_id = auth.uid()
  returning * into updated_row;

  if updated_row.id is null then
    raise exception 'Message not found or you do not have permission to delete it for everyone.';
  end if;

  update public.chats
  set updated_at = now()
  where id = updated_row.chat_id;

  return updated_row;
end;
$$;

grant select on public.stickers to anon, authenticated;
grant insert, update, delete on public.stickers to authenticated;
grant select, insert, update, delete on public.user_stickers to authenticated;
grant execute on function public.can_access_sticker(uuid, uuid) to authenticated;
grant execute on function public.can_manage_sticker_storage_object(text, uuid) to authenticated;

alter table public.stickers enable row level security;
alter table public.user_stickers enable row level security;

drop policy if exists "messages_insert_members_only" on public.messages;
create policy "messages_insert_members_only"
on public.messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and public.can_send_message_to_chat(chat_id, auth.uid())
  and (
    message_type <> 'sticker'
    or (sticker_id is not null and public.can_access_sticker(sticker_id, auth.uid()))
  )
);

drop policy if exists "stickers_select_public_or_owner" on public.stickers;
create policy "stickers_select_public_or_owner"
on public.stickers
for select
to anon, authenticated
using (is_public or auth.uid() = user_id);

drop policy if exists "stickers_insert_owner_only" on public.stickers;
create policy "stickers_insert_owner_only"
on public.stickers
for insert
to authenticated
with check (
  auth.uid() = user_id
  and storage_path like ('users/' || auth.uid()::text || '/%')
);

drop policy if exists "stickers_update_owner_only" on public.stickers;
create policy "stickers_update_owner_only"
on public.stickers
for update
to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and storage_path like ('users/' || auth.uid()::text || '/%')
);

drop policy if exists "stickers_delete_owner_only" on public.stickers;
create policy "stickers_delete_owner_only"
on public.stickers
for delete
to authenticated
using (auth.uid() = user_id);

drop policy if exists "user_stickers_select_owner_only" on public.user_stickers;
create policy "user_stickers_select_owner_only"
on public.user_stickers
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "user_stickers_insert_owner_only" on public.user_stickers;
create policy "user_stickers_insert_owner_only"
on public.user_stickers
for insert
to authenticated
with check (
  auth.uid() = user_id
  and public.can_access_sticker(sticker_id, auth.uid())
);

drop policy if exists "user_stickers_update_owner_only" on public.user_stickers;
create policy "user_stickers_update_owner_only"
on public.user_stickers
for update
to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and public.can_access_sticker(sticker_id, auth.uid())
);

drop policy if exists "user_stickers_delete_owner_only" on public.user_stickers;
create policy "user_stickers_delete_owner_only"
on public.user_stickers
for delete
to authenticated
using (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('stickers', 'stickers', true)
on conflict (id) do update
set public = excluded.public,
    name = excluded.name;

drop policy if exists "stickers_select_public" on storage.objects;
create policy "stickers_select_public"
on storage.objects
for select
to public
using (bucket_id = 'stickers');

drop policy if exists "stickers_insert_authenticated" on storage.objects;
create policy "stickers_insert_authenticated"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'stickers'
  and public.can_manage_sticker_storage_object(name, auth.uid())
);

drop policy if exists "stickers_update_authenticated" on storage.objects;
create policy "stickers_update_authenticated"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'stickers'
  and public.can_manage_sticker_storage_object(name, auth.uid())
)
with check (
  bucket_id = 'stickers'
  and public.can_manage_sticker_storage_object(name, auth.uid())
);

drop policy if exists "stickers_delete_authenticated" on storage.objects;
create policy "stickers_delete_authenticated"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'stickers'
  and public.can_manage_sticker_storage_object(name, auth.uid())
);
