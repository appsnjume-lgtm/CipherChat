-- Settings, privacy, profile media, blocking, and group customization migration.
--
-- This migration extends the existing CipherChat schema without removing
-- current group invites, join requests, media, or call behavior.
--
-- Notes:
-- 1. `public.chat_requests` already exists for group requests, so this migration
--    expands it to also support `direct_request` rows for private 1v1 chat flows.
-- 2. `public.chats.title` already serves as the editable group name, so this
--    migration keeps it and adds `group_image_url`.
-- 3. `profile_image_url` and `group_image_url` store Supabase Storage object
--    paths. Flutter resolves signed URLs at runtime.

create extension if not exists pgcrypto;

alter table if exists public.profiles
  add column if not exists profile_image_url text,
  add column if not exists bio text,
  add column if not exists gender_visibility text,
  add column if not exists profile_photo_visibility text,
  add column if not exists last_seen_visibility text,
  add column if not exists about_visibility text,
  add column if not exists account_privacy text,
  add column if not exists read_receipts_enabled boolean,
  add column if not exists typing_indicator_enabled boolean,
  add column if not exists enter_to_send_enabled boolean,
  add column if not exists message_notifications_enabled boolean,
  add column if not exists group_notifications_enabled boolean,
  add column if not exists notification_preview_enabled boolean,
  add column if not exists auto_download_media text,
  add column if not exists media_quality_preference text,
  add column if not exists who_can_call text,
  add column if not exists last_seen_at timestamptz;

update public.profiles
set bio = coalesce(nullif(btrim(bio), ''), '')
where bio is null or btrim(bio) = '';

update public.profiles
set gender_visibility = coalesce(nullif(btrim(gender_visibility), ''), 'everyone'),
    profile_photo_visibility = coalesce(nullif(btrim(profile_photo_visibility), ''), 'everyone'),
    last_seen_visibility = coalesce(nullif(btrim(last_seen_visibility), ''), 'everyone'),
    about_visibility = coalesce(nullif(btrim(about_visibility), ''), 'everyone'),
    account_privacy = coalesce(nullif(btrim(account_privacy), ''), 'public'),
    read_receipts_enabled = coalesce(read_receipts_enabled, true),
    typing_indicator_enabled = coalesce(typing_indicator_enabled, true),
    enter_to_send_enabled = coalesce(enter_to_send_enabled, false),
    message_notifications_enabled = coalesce(message_notifications_enabled, true),
    group_notifications_enabled = coalesce(group_notifications_enabled, true),
    notification_preview_enabled = coalesce(notification_preview_enabled, true),
    auto_download_media = coalesce(nullif(btrim(auto_download_media), ''), 'wifi_only'),
    media_quality_preference = coalesce(nullif(btrim(media_quality_preference), ''), 'standard'),
    who_can_call = coalesce(nullif(btrim(who_can_call), ''), 'everyone'),
    last_seen_at = coalesce(last_seen_at, updated_at, created_at, now())
where gender_visibility is null
   or profile_photo_visibility is null
   or last_seen_visibility is null
   or about_visibility is null
   or account_privacy is null
   or read_receipts_enabled is null
   or typing_indicator_enabled is null
   or enter_to_send_enabled is null
   or message_notifications_enabled is null
   or group_notifications_enabled is null
   or notification_preview_enabled is null
   or auto_download_media is null
   or media_quality_preference is null
   or who_can_call is null
   or last_seen_at is null;

alter table public.profiles
  alter column bio set default '',
  alter column gender set default 'male',
  alter column gender_visibility set default 'everyone',
  alter column profile_photo_visibility set default 'everyone',
  alter column last_seen_visibility set default 'everyone',
  alter column about_visibility set default 'everyone',
  alter column account_privacy set default 'public',
  alter column read_receipts_enabled set default true,
  alter column typing_indicator_enabled set default true,
  alter column enter_to_send_enabled set default false,
  alter column message_notifications_enabled set default true,
  alter column group_notifications_enabled set default true,
  alter column notification_preview_enabled set default true,
  alter column auto_download_media set default 'wifi_only',
  alter column media_quality_preference set default 'standard',
  alter column who_can_call set default 'everyone',
  alter column last_seen_at set default now();

alter table public.profiles
  alter column bio set not null,
  alter column gender_visibility set not null,
  alter column profile_photo_visibility set not null,
  alter column last_seen_visibility set not null,
  alter column about_visibility set not null,
  alter column account_privacy set not null,
  alter column read_receipts_enabled set not null,
  alter column typing_indicator_enabled set not null,
  alter column enter_to_send_enabled set not null,
  alter column message_notifications_enabled set not null,
  alter column group_notifications_enabled set not null,
  alter column notification_preview_enabled set not null,
  alter column auto_download_media set not null,
  alter column media_quality_preference set not null,
  alter column who_can_call set not null,
  alter column last_seen_at set not null;

alter table if exists public.profiles
  drop constraint if exists profiles_gender_check;

alter table if exists public.profiles
  drop constraint if exists profiles_avatar_id_check;

alter table public.profiles
  add constraint profiles_gender_check
  check (gender in ('male', 'female', 'other', 'prefer_not_to_say'));

alter table public.profiles
  add constraint profiles_avatar_id_check
  check (avatar_id in ('avatar_1', 'avatar_2', 'avatar_3', 'avatar_4', 'avatar_5', 'avatar_6'));

alter table public.profiles
  add constraint profiles_bio_length_check
  check (char_length(bio) <= 280);

alter table public.profiles
  add constraint profiles_gender_visibility_check
  check (gender_visibility in ('everyone', 'contacts', 'nobody'));

alter table public.profiles
  add constraint profiles_photo_visibility_check
  check (profile_photo_visibility in ('everyone', 'contacts', 'nobody'));

alter table public.profiles
  add constraint profiles_last_seen_visibility_check
  check (last_seen_visibility in ('everyone', 'contacts', 'nobody'));

alter table public.profiles
  add constraint profiles_about_visibility_check
  check (about_visibility in ('everyone', 'contacts', 'nobody'));

alter table public.profiles
  add constraint profiles_account_privacy_check
  check (account_privacy in ('public', 'private'));

alter table public.profiles
  add constraint profiles_auto_download_media_check
  check (auto_download_media in ('never', 'wifi_only', 'wifi_and_mobile'));

alter table public.profiles
  add constraint profiles_media_quality_check
  check (media_quality_preference in ('low', 'standard', 'high'));

alter table public.profiles
  add constraint profiles_who_can_call_check
  check (who_can_call in ('everyone', 'contacts', 'nobody'));

alter table if exists public.chats
  add column if not exists group_image_url text;

create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocked_users_unique unique (blocker_id, blocked_user_id),
  constraint blocked_users_self_block_check check (blocker_id <> blocked_user_id)
);

create index if not exists idx_blocked_users_blocker
  on public.blocked_users (blocker_id, created_at desc);

create index if not exists idx_blocked_users_blocked
  on public.blocked_users (blocked_user_id, created_at desc);

alter table public.chat_requests
  alter column chat_id drop not null;

alter table public.chat_requests
  drop constraint if exists chat_requests_type_check;

alter table public.chat_requests
  drop constraint if exists chat_requests_status_check;

alter table public.chat_requests
  drop constraint if exists chat_requests_invite_actor_check;

alter table public.chat_requests
  add constraint chat_requests_type_check
  check (type in ('join_request', 'invite', 'direct_request'));

alter table public.chat_requests
  add constraint chat_requests_status_check
  check (status in ('pending', 'accepted', 'rejected'));

alter table public.chat_requests
  add constraint chat_requests_shape_check
  check (
    (
      type in ('join_request', 'invite')
      and chat_id is not null
    )
    or
    (
      type = 'direct_request'
      and chat_id is null
      and user_id <> requested_by
    )
  );

create unique index if not exists idx_pending_direct_chat_requests_unique
  on public.chat_requests (least(requested_by, user_id), greatest(requested_by, user_id))
  where type = 'direct_request' and status = 'pending';

create or replace function public.is_user_blocked(
  p_left_user_id uuid,
  p_right_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocked_users bu
    where (bu.blocker_id = p_left_user_id and bu.blocked_user_id = p_right_user_id)
       or (bu.blocker_id = p_right_user_id and bu.blocked_user_id = p_left_user_id)
  );
$$;

create or replace function public.find_direct_chat_between(
  p_left_user_id uuid,
  p_right_user_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with shared_chats as (
    select cm.chat_id
    from public.chat_members cm
    where cm.user_id in (p_left_user_id, p_right_user_id)
    group by cm.chat_id
    having count(distinct cm.user_id) = 2
  )
  select c.id
  from public.chats c
  join shared_chats sc on sc.chat_id = c.id
  where c.is_group = false
  order by c.created_at asc
  limit 1;
$$;

create or replace function public.are_users_contacts(
  p_left_user_id uuid,
  p_right_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.find_direct_chat_between(p_left_user_id, p_right_user_id) is not null;
$$;

create or replace function public.can_access_profile_image(
  p_owner_id uuid,
  p_viewer_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  visibility_setting text;
begin
  if p_owner_id = p_viewer_id then
    return true;
  end if;

  if public.is_user_blocked(p_owner_id, p_viewer_id) then
    return false;
  end if;

  select profile_photo_visibility
  into visibility_setting
  from public.profiles
  where id = p_owner_id;

  if visibility_setting = 'nobody' then
    return false;
  end if;

  if visibility_setting = 'contacts' then
    return public.are_users_contacts(p_owner_id, p_viewer_id);
  end if;

  return true;
end;
$$;

create or replace function public.can_receive_call(
  p_caller_id uuid,
  p_receiver_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  call_setting text;
begin
  if p_caller_id = p_receiver_id then
    return false;
  end if;

  if public.is_user_blocked(p_caller_id, p_receiver_id) then
    return false;
  end if;

  select who_can_call
  into call_setting
  from public.profiles
  where id = p_receiver_id;

  if call_setting = 'nobody' then
    return false;
  end if;

  if call_setting = 'contacts' then
    return public.are_users_contacts(p_caller_id, p_receiver_id);
  end if;

  return true;
end;
$$;

create or replace function public.can_send_message_to_chat(
  p_chat_id uuid,
  p_sender_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  peer_user_id uuid;
  is_group_chat boolean;
begin
  select c.is_group
  into is_group_chat
  from public.chats c
  where c.id = p_chat_id;

  if coalesce(is_group_chat, false) then
    return public.is_chat_member(p_chat_id, p_sender_id);
  end if;

  select cm.user_id
  into peer_user_id
  from public.chat_members cm
  where cm.chat_id = p_chat_id
    and cm.user_id <> p_sender_id
  limit 1;

  return peer_user_id is not null
    and public.is_chat_member(p_chat_id, p_sender_id)
    and not public.is_user_blocked(p_sender_id, peer_user_id);
end;
$$;

create or replace function public.ensure_direct_chat(
  p_left_user_id uuid,
  p_right_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_chat_id uuid;
  created_chat_id uuid;
begin
  existing_chat_id := public.find_direct_chat_between(p_left_user_id, p_right_user_id);
  if existing_chat_id is not null then
    return existing_chat_id;
  end if;

  insert into public.chats (is_group, created_by)
  values (false, p_left_user_id)
  returning id into created_chat_id;

  insert into public.chat_members (chat_id, user_id, role)
  values
    (created_chat_id, p_left_user_id, 'member'),
    (created_chat_id, p_right_user_id, 'member')
  on conflict (chat_id, user_id) do nothing;

  return created_chat_id;
end;
$$;

create or replace function public.attach_direct_chat_on_request_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type = 'direct_request'
     and new.status = 'accepted'
     and old.status is distinct from 'accepted' then
    new.chat_id = public.ensure_direct_chat(new.requested_by, new.user_id);
  end if;

  return new;
end;
$$;

create or replace function public.add_member_on_request_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type in ('join_request', 'invite')
     and new.status = 'accepted'
     and old.status is distinct from 'accepted' then
    insert into public.chat_members (chat_id, user_id, role)
    values (new.chat_id, new.user_id, 'member')
    on conflict (chat_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_chat_requests_attach_direct_chat on public.chat_requests;
create trigger trg_chat_requests_attach_direct_chat
before update on public.chat_requests
for each row
execute function public.attach_direct_chat_on_request_accept();

drop trigger if exists trg_chat_requests_accept on public.chat_requests;
create trigger trg_chat_requests_accept
after update on public.chat_requests
for each row
execute function public.add_member_on_request_accept();

grant select, insert, update, delete on public.blocked_users to authenticated;
grant execute on function public.is_user_blocked(uuid, uuid) to authenticated;
grant execute on function public.find_direct_chat_between(uuid, uuid) to authenticated;
grant execute on function public.are_users_contacts(uuid, uuid) to authenticated;
grant execute on function public.can_access_profile_image(uuid, uuid) to authenticated;
grant execute on function public.can_receive_call(uuid, uuid) to authenticated;
grant execute on function public.can_send_message_to_chat(uuid, uuid) to authenticated;
grant execute on function public.ensure_direct_chat(uuid, uuid) to authenticated;

alter table public.blocked_users enable row level security;

drop policy if exists "blocked_users_select_own" on public.blocked_users;
create policy "blocked_users_select_own"
on public.blocked_users
for select
to authenticated
using (blocker_id = auth.uid());

drop policy if exists "blocked_users_insert_own" on public.blocked_users;
create policy "blocked_users_insert_own"
on public.blocked_users
for insert
to authenticated
with check (blocker_id = auth.uid());

drop policy if exists "blocked_users_delete_own" on public.blocked_users;
create policy "blocked_users_delete_own"
on public.blocked_users
for delete
to authenticated
using (blocker_id = auth.uid());

drop policy if exists "messages_insert_members_only" on public.messages;
create policy "messages_insert_members_only"
on public.messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and public.can_send_message_to_chat(chat_id, auth.uid())
);

drop policy if exists "call_sessions_insert_caller_only" on public.call_sessions;
create policy "call_sessions_insert_caller_only"
on public.call_sessions
for insert
to authenticated
with check (
  caller_id = auth.uid()
  and exists (
    select 1
    from public.chats c
    where c.id = chat_id
      and c.is_group = false
  )
  and public.is_chat_member(chat_id, caller_id)
  and public.is_chat_member(chat_id, callee_id)
  and public.can_receive_call(caller_id, callee_id)
);

drop policy if exists "chat_requests_insert_join_or_invite" on public.chat_requests;
create policy "chat_requests_insert_join_or_invite"
on public.chat_requests
for insert
to authenticated
with check (
  (
    type = 'join_request'
    and user_id = auth.uid()
    and requested_by = auth.uid()
    and chat_id is not null
    and exists (
      select 1
      from public.chats c
      where c.id = chat_id
        and c.is_group = true
    )
    and not public.is_chat_member(chat_id, auth.uid())
  )
  or
  (
    type = 'invite'
    and chat_id is not null
    and requested_by = auth.uid()
    and user_id <> auth.uid()
    and public.is_chat_admin(chat_id, auth.uid())
    and not public.is_chat_member(chat_id, user_id)
    and not public.is_user_blocked(requested_by, user_id)
  )
  or
  (
    type = 'direct_request'
    and chat_id is null
    and requested_by = auth.uid()
    and user_id <> auth.uid()
    and not public.is_user_blocked(requested_by, user_id)
    and exists (
      select 1
      from public.profiles p
      where p.id = user_id
        and p.account_privacy = 'private'
    )
    and public.find_direct_chat_between(requested_by, user_id) is null
  )
);

drop policy if exists "chat_requests_update_invited_user_or_admin" on public.chat_requests;
create policy "chat_requests_update_invited_user_or_admin"
on public.chat_requests
for update
to authenticated
using (
  (
    type = 'invite'
    and user_id = auth.uid()
  )
  or
  (
    type = 'join_request'
    and chat_id is not null
    and public.is_chat_admin(chat_id, auth.uid())
  )
  or
  (
    type = 'direct_request'
    and user_id = auth.uid()
  )
)
with check (
  status in ('accepted', 'rejected')
  and (
    (
      type = 'invite'
      and user_id = auth.uid()
    )
    or
    (
      type = 'join_request'
      and chat_id is not null
      and public.is_chat_admin(chat_id, auth.uid())
    )
    or
    (
      type = 'direct_request'
      and user_id = auth.uid()
    )
  )
);

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', false)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('group-images', 'group-images', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "profile_images_select_visible" on storage.objects;
create policy "profile_images_select_visible"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'profile-images'
  and public.can_access_profile_image(((storage.foldername(name))[1])::uuid, auth.uid())
);

drop policy if exists "profile_images_insert_own" on storage.objects;
create policy "profile_images_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

drop policy if exists "profile_images_update_own" on storage.objects;
create policy "profile_images_update_own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

drop policy if exists "profile_images_delete_own" on storage.objects;
create policy "profile_images_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

drop policy if exists "group_images_select_authenticated" on storage.objects;
create policy "group_images_select_authenticated"
on storage.objects
for select
to authenticated
using (bucket_id = 'group-images');

drop policy if exists "group_images_insert_admin" on storage.objects;
create policy "group_images_insert_admin"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'group-images'
  and public.is_chat_admin(((storage.foldername(name))[1])::uuid, auth.uid())
);

drop policy if exists "group_images_update_admin" on storage.objects;
create policy "group_images_update_admin"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'group-images'
  and public.is_chat_admin(((storage.foldername(name))[1])::uuid, auth.uid())
)
with check (
  bucket_id = 'group-images'
  and public.is_chat_admin(((storage.foldername(name))[1])::uuid, auth.uid())
);

drop policy if exists "group_images_delete_admin" on storage.objects;
create policy "group_images_delete_admin"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'group-images'
  and public.is_chat_admin(((storage.foldername(name))[1])::uuid, auth.uid())
);
