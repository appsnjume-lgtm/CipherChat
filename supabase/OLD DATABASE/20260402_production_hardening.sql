-- Production hardening migration for CipherChat.
--
-- This migration closes the highest-risk privacy gaps identified in the
-- 2026-04-02 audit by moving profile privacy enforcement into the database,
-- tightening secure-media access to membership/ownership, removing plaintext
-- server-side message search, and making direct chat creation canonical.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create table if not exists public.direct_chat_pairs (
  left_user_id uuid not null references public.profiles (id) on delete cascade,
  right_user_id uuid not null references public.profiles (id) on delete cascade,
  chat_id uuid not null unique references public.chats (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint direct_chat_pairs_pk primary key (left_user_id, right_user_id),
  constraint direct_chat_pairs_order_check check (left_user_id < right_user_id)
);

with direct_pairs as (
  select
    c.id as chat_id,
    least(min(cm.user_id), max(cm.user_id)) as left_user_id,
    greatest(min(cm.user_id), max(cm.user_id)) as right_user_id,
    c.created_at
  from public.chats c
  join public.chat_members cm on cm.chat_id = c.id
  where c.is_group = false
  group by c.id, c.created_at
  having count(*) = 2 and count(distinct cm.user_id) = 2
),
ranked as (
  select
    direct_pairs.*,
    row_number() over (
      partition by direct_pairs.left_user_id, direct_pairs.right_user_id
      order by direct_pairs.created_at asc, direct_pairs.chat_id asc
    ) as rn
  from direct_pairs
)
insert into public.direct_chat_pairs (left_user_id, right_user_id, chat_id)
select left_user_id, right_user_id, chat_id
from ranked
where rn = 1
on conflict (left_user_id, right_user_id) do nothing;

create or replace function public.is_private_account(
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.account_privacy = 'private'
  );
$$;

create or replace function public.can_view_profile_field(
  p_owner_id uuid,
  p_viewer_id uuid default auth.uid(),
  p_visibility text default 'everyone'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_owner_id = p_viewer_id then
    return true;
  end if;

  if public.is_user_blocked(p_owner_id, p_viewer_id) then
    return false;
  end if;

  if coalesce(p_visibility, 'everyone') = 'nobody' then
    return false;
  end if;

  if coalesce(p_visibility, 'everyone') = 'contacts' then
    return public.are_users_contacts(p_owner_id, p_viewer_id);
  end if;

  return true;
end;
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
  select coalesce(
    (
      select dcp.chat_id
      from public.direct_chat_pairs dcp
      where dcp.left_user_id = least(p_left_user_id, p_right_user_id)
        and dcp.right_user_id = greatest(p_left_user_id, p_right_user_id)
      limit 1
    ),
    (
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
      limit 1
    )
  );
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
  canonical_left uuid := least(p_left_user_id, p_right_user_id);
  canonical_right uuid := greatest(p_left_user_id, p_right_user_id);
  existing_chat_id uuid;
  created_chat_id uuid;
begin
  if canonical_left = canonical_right then
    raise exception 'Direct chats require two distinct users.';
  end if;

  existing_chat_id := public.find_direct_chat_between(canonical_left, canonical_right);
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

  insert into public.direct_chat_pairs (left_user_id, right_user_id, chat_id)
  values (canonical_left, canonical_right, created_chat_id)
  on conflict (left_user_id, right_user_id) do nothing;

  select dcp.chat_id
  into existing_chat_id
  from public.direct_chat_pairs dcp
  where dcp.left_user_id = canonical_left
    and dcp.right_user_id = canonical_right;

  if existing_chat_id <> created_chat_id then
    delete from public.chat_members where chat_id = created_chat_id;
    delete from public.chats where id = created_chat_id;
    return existing_chat_id;
  end if;

  return created_chat_id;
end;
$$;

create or replace function public.get_visible_profiles_by_ids(
  p_user_ids uuid[]
)
returns table (
  id uuid,
  username text,
  gender text,
  avatar_id text,
  profile_image_url text,
  bio text,
  gender_visibility text,
  profile_photo_visibility text,
  last_seen_visibility text,
  about_visibility text,
  account_privacy text,
  read_receipts_enabled boolean,
  typing_indicator_enabled boolean,
  enter_to_send_enabled boolean,
  message_notifications_enabled boolean,
  group_notifications_enabled boolean,
  notification_preview_enabled boolean,
  auto_download_media text,
  media_quality_preference text,
  who_can_call text,
  is_online boolean,
  created_at timestamptz,
  last_seen timestamptz,
  updated_at timestamptz,
  presence_expires_at timestamptz,
  can_view_profile_photo boolean,
  can_view_gender boolean,
  can_view_about boolean,
  can_view_last_seen boolean,
  is_contact boolean,
  is_blocked boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select auth.uid() as viewer_id
  ),
  source as (
    select
      p.*,
      v.viewer_id,
      public.are_users_contacts(p.id, v.viewer_id) as is_contact,
      public.is_user_blocked(p.id, v.viewer_id) as is_blocked,
      public.can_access_profile_image(p.id, v.viewer_id) as can_view_profile_photo,
      public.can_view_profile_field(p.id, v.viewer_id, p.gender_visibility) as can_view_gender,
      public.can_view_profile_field(p.id, v.viewer_id, p.about_visibility) as can_view_about,
      public.can_view_profile_field(p.id, v.viewer_id, p.last_seen_visibility) as can_view_last_seen
    from public.profiles p
    cross join viewer v
    where p.id = any(p_user_ids)
  )
  select
    s.id,
    s.username::text,
    case when s.can_view_gender then s.gender else 'prefer_not_to_say' end as gender,
    s.avatar_id,
    case when s.can_view_profile_photo then s.profile_image_url else null end as profile_image_url,
    case when s.can_view_about then s.bio else '' end as bio,
    case when s.id = s.viewer_id then s.gender_visibility else 'nobody' end as gender_visibility,
    case when s.id = s.viewer_id then s.profile_photo_visibility else 'nobody' end as profile_photo_visibility,
    case when s.id = s.viewer_id then s.last_seen_visibility else 'nobody' end as last_seen_visibility,
    case when s.id = s.viewer_id then s.about_visibility else 'nobody' end as about_visibility,
    s.account_privacy,
    case when s.id = s.viewer_id then s.read_receipts_enabled else true end as read_receipts_enabled,
    case when s.id = s.viewer_id then s.typing_indicator_enabled else true end as typing_indicator_enabled,
    case when s.id = s.viewer_id then s.enter_to_send_enabled else false end as enter_to_send_enabled,
    case when s.id = s.viewer_id then s.message_notifications_enabled else true end as message_notifications_enabled,
    case when s.id = s.viewer_id then s.group_notifications_enabled else true end as group_notifications_enabled,
    case when s.id = s.viewer_id then s.notification_preview_enabled else true end as notification_preview_enabled,
    case when s.id = s.viewer_id then s.auto_download_media else 'wifi_only' end as auto_download_media,
    case when s.id = s.viewer_id then s.media_quality_preference else 'standard' end as media_quality_preference,
    case when s.id = s.viewer_id then s.who_can_call else 'everyone' end as who_can_call,
    case when s.can_view_last_seen then s.is_online else false end as is_online,
    s.created_at,
    case when s.can_view_last_seen then coalesce(s.last_seen, s.last_seen_at) else null end as last_seen,
    s.updated_at,
    case when s.can_view_last_seen then s.presence_expires_at else null end as presence_expires_at,
    s.can_view_profile_photo,
    s.can_view_gender,
    s.can_view_about,
    s.can_view_last_seen,
    s.is_contact,
    s.is_blocked
  from source s
  order by array_position(p_user_ids, s.id);
$$;

create or replace function public.search_visible_profiles(
  p_query text default null,
  p_limit integer default 30
)
returns table (
  id uuid,
  username text,
  gender text,
  avatar_id text,
  profile_image_url text,
  bio text,
  gender_visibility text,
  profile_photo_visibility text,
  last_seen_visibility text,
  about_visibility text,
  account_privacy text,
  read_receipts_enabled boolean,
  typing_indicator_enabled boolean,
  enter_to_send_enabled boolean,
  message_notifications_enabled boolean,
  group_notifications_enabled boolean,
  notification_preview_enabled boolean,
  auto_download_media text,
  media_quality_preference text,
  who_can_call text,
  is_online boolean,
  created_at timestamptz,
  last_seen timestamptz,
  updated_at timestamptz,
  presence_expires_at timestamptz,
  can_view_profile_photo boolean,
  can_view_gender boolean,
  can_view_about boolean,
  can_view_last_seen boolean,
  is_contact boolean,
  is_blocked boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select auth.uid() as viewer_id,
           nullif(btrim(p_query), '') as query,
           greatest(1, least(coalesce(p_limit, 30), 100)) as limit_value
  ),
  source as (
    select
      p.*,
      v.viewer_id,
      v.query,
      public.are_users_contacts(p.id, v.viewer_id) as is_contact,
      public.is_user_blocked(p.id, v.viewer_id) as is_blocked,
      public.can_access_profile_image(p.id, v.viewer_id) as can_view_profile_photo,
      public.can_view_profile_field(p.id, v.viewer_id, p.gender_visibility) as can_view_gender,
      public.can_view_profile_field(p.id, v.viewer_id, p.about_visibility) as can_view_about,
      public.can_view_profile_field(p.id, v.viewer_id, p.last_seen_visibility) as can_view_last_seen
    from public.profiles p
    cross join viewer v
    where p.id <> v.viewer_id
      and (
        v.query is null
        or p.username::text ilike '%' || v.query || '%'
        or p.username::text % v.query
      )
  )
  select
    s.id,
    s.username::text,
    case when s.can_view_gender then s.gender else 'prefer_not_to_say' end as gender,
    s.avatar_id,
    case when s.can_view_profile_photo then s.profile_image_url else null end as profile_image_url,
    case when s.can_view_about then s.bio else '' end as bio,
    'nobody'::text as gender_visibility,
    'nobody'::text as profile_photo_visibility,
    'nobody'::text as last_seen_visibility,
    'nobody'::text as about_visibility,
    s.account_privacy,
    true as read_receipts_enabled,
    true as typing_indicator_enabled,
    false as enter_to_send_enabled,
    true as message_notifications_enabled,
    true as group_notifications_enabled,
    true as notification_preview_enabled,
    'wifi_only'::text as auto_download_media,
    'standard'::text as media_quality_preference,
    'everyone'::text as who_can_call,
    case when s.can_view_last_seen then s.is_online else false end as is_online,
    s.created_at,
    case when s.can_view_last_seen then coalesce(s.last_seen, s.last_seen_at) else null end as last_seen,
    s.updated_at,
    case when s.can_view_last_seen then s.presence_expires_at else null end as presence_expires_at,
    s.can_view_profile_photo,
    s.can_view_gender,
    s.can_view_about,
    s.can_view_last_seen,
    s.is_contact,
    s.is_blocked
  from source s
  cross join viewer v
  order by
    (case when v.query is null then 0 else 1 end) desc,
    (case when v.query is null then 0 else similarity(s.username::text, v.query) end) desc,
    s.created_at desc,
    s.username::text asc
  limit (select limit_value from viewer);
$$;

create or replace function public.get_chat_participant_keys(
  p_chat_id uuid
)
returns table (
  id uuid,
  e2ee_public_key text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.e2ee_public_key
  from public.chat_members cm
  join public.profiles p on p.id = cm.user_id
  where public.is_chat_member(p_chat_id, auth.uid())
    and cm.chat_id = p_chat_id
    and p.e2ee_public_key is not null
    and btrim(p.e2ee_public_key) <> '';
$$;

create or replace function public.secure_media_chat_id(
  p_object_name text
)
returns uuid
language sql
stable
as $$
  select case
    when split_part(p_object_name, '/', 1) ~* '^[0-9a-f-]{36}$'
      then split_part(p_object_name, '/', 1)::uuid
    else null
  end;
$$;

create or replace function public.secure_media_message_id(
  p_object_name text
)
returns uuid
language sql
stable
as $$
  select case
    when split_part(split_part(p_object_name, '/', 2), '.', 1) ~* '^[0-9a-f-]{36}$'
      then split_part(split_part(p_object_name, '/', 2), '.', 1)::uuid
    else null
  end;
$$;

create or replace function public.can_upload_secure_media_object(
  p_object_name text,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  resolved_chat_id uuid := public.secure_media_chat_id(p_object_name);
  resolved_message_id uuid := public.secure_media_message_id(p_object_name);
begin
  if resolved_chat_id is null or resolved_message_id is null then
    return false;
  end if;

  return public.is_chat_member(resolved_chat_id, p_user_id);
end;
$$;

create or replace function public.can_access_secure_media_object(
  p_object_name text,
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
    from public.messages m
    where m.chat_id = public.secure_media_chat_id(p_object_name)
      and m.id = public.secure_media_message_id(p_object_name)
      and public.is_chat_member(m.chat_id, p_user_id)
  );
$$;

create or replace function public.can_delete_secure_media_object(
  p_object_name text,
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
    from public.messages m
    where m.chat_id = public.secure_media_chat_id(p_object_name)
      and m.id = public.secure_media_message_id(p_object_name)
      and m.sender_id = p_user_id
  );
$$;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles
for select
to authenticated
using (auth.uid() = id);

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
    and public.is_private_account(user_id)
    and public.find_direct_chat_between(requested_by, user_id) is null
  )
);

drop policy if exists "secure_media_select_authenticated" on storage.objects;
create policy "secure_media_select_authenticated"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'secure-media'
  and public.can_access_secure_media_object(name, auth.uid())
);

drop policy if exists "secure_media_insert_authenticated" on storage.objects;
create policy "secure_media_insert_authenticated"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'secure-media'
  and public.can_upload_secure_media_object(name, auth.uid())
);

drop policy if exists "secure_media_delete_authenticated" on storage.objects;
create policy "secure_media_delete_authenticated"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'secure-media'
  and public.can_delete_secure_media_object(name, auth.uid())
);

drop trigger if exists trg_messages_normalize_search_text on public.messages;
drop function if exists public.normalize_message_search_text();
drop function if exists public.search_chat_messages(uuid, text, integer, integer);
drop function if exists public.search_global_messages(text, integer, integer);
drop function if exists public.build_search_snippet(text, text, integer);
drop index if exists idx_messages_search_text_trgm;
drop index if exists idx_messages_search_text_fts;
alter table if exists public.messages drop column if exists search_text;

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

update public.profiles
set profile_image_url = regexp_replace(
      profile_image_url,
      '^.*?/object/(?:public|sign|authenticated)/profile-images/([^?]+).*$','\1'
    )
where profile_image_url is not null
  and profile_image_url like '%/object/%/profile-images/%';

grant select on public.direct_chat_pairs to authenticated;
grant execute on function public.is_private_account(uuid) to authenticated;
grant execute on function public.can_view_profile_field(uuid, uuid, text) to authenticated;
grant execute on function public.get_visible_profiles_by_ids(uuid[]) to authenticated;
grant execute on function public.search_visible_profiles(text, integer) to authenticated;
grant execute on function public.get_chat_participant_keys(uuid) to authenticated;
grant execute on function public.secure_media_chat_id(text) to authenticated;
grant execute on function public.secure_media_message_id(text) to authenticated;
grant execute on function public.can_upload_secure_media_object(text, uuid) to authenticated;
grant execute on function public.can_access_secure_media_object(text, uuid) to authenticated;
grant execute on function public.can_delete_secure_media_object(text, uuid) to authenticated;
grant execute on function public.soft_delete_message_for_everyone(uuid) to authenticated;
