-- CipherChat canonical bootstrap schema.
--
-- This file is intended for a brand-new Supabase project and is not designed
-- to be rerun. It contains only the final end-state schema for CipherChat,
-- without migration-era drop statements, backfills, or existence guards.

-- ============================================================================
-- Extensions
-- ============================================================================

create extension pgcrypto;
create extension pg_trgm;
create extension citext;

-- ============================================================================
-- Tables
-- ============================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  profile_image_url text,
  bio text not null default '',
  gender_visibility text not null default 'everyone',
  profile_photo_visibility text not null default 'everyone',
  last_seen_visibility text not null default 'everyone',
  about_visibility text not null default 'everyone',
  account_privacy text not null default 'public',
  read_receipts_enabled boolean not null default true,
  typing_indicator_enabled boolean not null default true,
  enter_to_send_enabled boolean not null default false,
  message_notifications_enabled boolean not null default true,
  group_notifications_enabled boolean not null default true,
  notification_preview_enabled boolean not null default true,
  auto_download_media text not null default 'wifi_only',
  media_quality_preference text not null default 'standard',
  who_can_call text not null default 'everyone',
  last_seen timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  is_online boolean not null default false,
  presence_heartbeat_at timestamptz not null default now(),
  presence_expires_at timestamptz not null default (now() + interval '2 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female', 'other', 'prefer_not_to_say')),
  constraint profiles_avatar_id_check
    check (avatar_id in ('avatar_1', 'avatar_2', 'avatar_3', 'avatar_4', 'avatar_5', 'avatar_6')),
  constraint profiles_bio_length_check
    check (char_length(bio) <= 280),
  constraint profiles_gender_visibility_check
    check (gender_visibility in ('everyone', 'contacts', 'nobody')),
  constraint profiles_photo_visibility_check
    check (profile_photo_visibility in ('everyone', 'contacts', 'nobody')),
  constraint profiles_last_seen_visibility_check
    check (last_seen_visibility in ('everyone', 'contacts', 'nobody')),
  constraint profiles_about_visibility_check
    check (about_visibility in ('everyone', 'contacts', 'nobody')),
  constraint profiles_account_privacy_check
    check (account_privacy in ('public', 'private')),
  constraint profiles_auto_download_media_check
    check (auto_download_media in ('never', 'wifi_only', 'wifi_and_mobile')),
  constraint profiles_media_quality_check
    check (media_quality_preference in ('low', 'standard', 'high')),
  constraint profiles_who_can_call_check
    check (who_can_call in ('everyone', 'contacts', 'nobody')),
  constraint profiles_presence_expiry_check
    check (presence_expires_at >= presence_heartbeat_at)
);

create table public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  group_image_url text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table public.stickers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete restrict,
  storage_path text not null,
  mime_type text not null default 'image/png',
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  constraint stickers_storage_path_not_blank
    check (char_length(trim(storage_path)) > 0),
  constraint stickers_mime_type_check
    check (mime_type in ('image/png', 'image/jpeg', 'image/webp')),
  constraint stickers_storage_path_prefix_check
    check (storage_path like 'system/%' or storage_path like 'users/%'),
  constraint stickers_storage_path_extension_check
    check (lower(storage_path) ~ '^(system|users)/.+\.(png|jpe?g|webp)$'),
  constraint stickers_storage_path_matches_mime_type_check
    check (
      (mime_type = 'image/png' and lower(storage_path) like '%.png')
      or (mime_type = 'image/jpeg' and (lower(storage_path) like '%.jpg' or lower(storage_path) like '%.jpeg'))
      or (mime_type = 'image/webp' and lower(storage_path) like '%.webp')
    ),
  constraint stickers_owner_path_check
    check (
      (user_id is null and storage_path like 'system/%')
      or (user_id is not null and storage_path like ('users/' || user_id::text || '/%'))
    ),
  constraint stickers_system_public_check
    check (user_id is not null or is_public)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  sticker_id uuid references public.stickers (id) on delete restrict,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio', 'sticker', 'grid_breach')),
  constraint messages_sticker_reference_check
    check (
      (message_type = 'sticker' and (sticker_id is not null or deleted_for_everyone_at is not null))
      or (message_type <> 'sticker' and sticker_id is null)
    ),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table public.message_receipts (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages (id) on delete cascade,
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint message_receipts_unique unique (message_id, user_id)
);

create table public.user_stickers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  sticker_id uuid not null references public.stickers (id) on delete cascade,
  is_favorite boolean not null default false,
  added_at timestamptz not null default now(),
  constraint user_stickers_unique unique (user_id, sticker_id)
);

create table public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  receiver_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite', 'direct_request')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_shape_check
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
    )
);

create table public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  caller_id uuid not null references public.profiles (id) on delete cascade,
  callee_id uuid not null references public.profiles (id) on delete cascade,
  call_type text not null,
  status text not null default 'ringing',
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  constraint call_sessions_type_check check (call_type in ('audio', 'video')),
  constraint call_sessions_status_check check (status in ('ringing', 'accepted', 'rejected', 'ended', 'missed')),
  constraint call_sessions_different_participants_check check (caller_id <> callee_id)
);

create table public.call_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.call_sessions (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint call_signals_event_check
    check (event_type in ('offer', 'answer', 'candidate', 'hangup')),
  constraint call_signals_payload_object_check check (jsonb_typeof(payload) = 'object')
);

create table public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocked_users_unique unique (blocker_id, blocked_user_id),
  constraint blocked_users_self_block_check check (blocker_id <> blocked_user_id)
);

create table public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_user_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null default 'profile_report',
  created_at timestamptz not null default now(),
  constraint user_reports_self_report_check check (reporter_id <> reported_user_id)
);

create table public.direct_chat_pairs (
  left_user_id uuid not null references public.profiles (id) on delete cascade,
  right_user_id uuid not null references public.profiles (id) on delete cascade,
  chat_id uuid not null unique references public.chats (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint direct_chat_pairs_pk primary key (left_user_id, right_user_id),
  constraint direct_chat_pairs_order_check check (left_user_id < right_user_id)
);

create table public.chat_user_state (
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  archived_at timestamptz,
  hidden_at timestamptz,
  constraint chat_user_state_pk primary key (chat_id, user_id)
);

-- ============================================================================
-- Indexes
-- ============================================================================

create index idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);

create index idx_chats_created_by on public.chats (created_by);
create index idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index idx_chats_group_title_trgm
  on public.chats using gin ((coalesce(title, '')::text) gin_trgm_ops)
  where is_group = true;

create index idx_chat_members_chat on public.chat_members (chat_id);
create index idx_chat_members_user on public.chat_members (user_id);

create index idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index idx_messages_type on public.messages (message_type);
create index idx_messages_sticker_id on public.messages (sticker_id) where sticker_id is not null;
create index idx_messages_sender_sticker_recent on public.messages (sender_id, created_at desc)
  where message_type = 'sticker' and sticker_id is not null;

create index idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index idx_message_receipts_message on public.message_receipts (message_id);
create index idx_message_receipts_user_unread_chat
  on public.message_receipts (user_id, chat_id)
  where read_at is null;
create index idx_stickers_public_created_at on public.stickers (created_at desc)
  where is_public = true;
create index idx_stickers_user_created_at on public.stickers (user_id, created_at desc)
  where user_id is not null;
create index idx_user_stickers_user_added_at on public.user_stickers (user_id, added_at desc);
create index idx_user_stickers_user_favorite_added_at on public.user_stickers (user_id, is_favorite, added_at desc);

create index idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index idx_chat_requests_sender_status on public.chat_requests (sender_id, status, created_at desc);
create index idx_chat_requests_receiver_status on public.chat_requests (receiver_id, status, created_at desc);
create index idx_chat_requests_requested_by_status
  on public.chat_requests (requested_by, status, created_at desc);
create unique index idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';
create unique index idx_pending_direct_chat_requests_unique
  on public.chat_requests (least(requested_by, user_id), greatest(requested_by, user_id))
  where type = 'direct_request' and status = 'pending';

create index idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create unique index idx_call_sessions_one_active_call_per_chat
  on public.call_sessions (chat_id)
  where status in ('ringing', 'accepted');
create index idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);

create index idx_blocked_users_blocker on public.blocked_users (blocker_id, created_at desc);
create index idx_blocked_users_blocked on public.blocked_users (blocked_user_id, created_at desc);

create index idx_user_reports_reporter on public.user_reports (reporter_id, created_at desc);
create index idx_user_reports_reported on public.user_reports (reported_user_id, created_at desc);
create index idx_chat_user_state_user_archived
  on public.chat_user_state (user_id, archived_at desc);

-- ============================================================================
-- Functions
-- ============================================================================

create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  perform 1
  from public.messages m
  where m.id = new.reply_to_message_id
    and m.chat_id = new.chat_id;

  if not found then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$;

create function public.sync_profile_presence_columns()
returns trigger
language plpgsql
as $$
declare
  effective_last_seen timestamptz;
  heartbeat_at timestamptz;
begin
  if new.last_seen is null and new.last_seen_at is not null then
    new.last_seen = new.last_seen_at;
  elsif new.last_seen is not null and new.last_seen_at is null then
    new.last_seen_at = new.last_seen;
  elsif tg_op = 'UPDATE' and new.last_seen is distinct from old.last_seen then
    new.last_seen_at = new.last_seen;
  elsif tg_op = 'UPDATE' and new.last_seen_at is distinct from old.last_seen_at then
    new.last_seen = new.last_seen_at;
  end if;

  effective_last_seen := coalesce(new.last_seen_at, new.last_seen, now());
  heartbeat_at := coalesce(new.presence_heartbeat_at, effective_last_seen, now());
  new.presence_heartbeat_at = heartbeat_at;

  if coalesce(new.is_online, false) then
    new.presence_expires_at = greatest(
      coalesce(new.presence_expires_at, heartbeat_at + interval '2 minutes'),
      heartbeat_at + interval '2 minutes'
    );
  else
    new.presence_expires_at = effective_last_seen;
  end if;

  return new;
end;
$$;

create function public.sync_chat_request_parties()
returns trigger
language plpgsql
as $$
begin
  new.sender_id = coalesce(new.sender_id, new.requested_by);
  new.receiver_id = coalesce(new.receiver_id, new.user_id);
  return new;
end;
$$;

create function public.is_chat_member(
  p_chat_id uuid,
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
    from public.chat_members cm
    where cm.chat_id = p_chat_id
      and cm.user_id = p_user_id
  );
$$;

create function public.is_chat_admin(
  p_chat_id uuid,
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
    from public.chats c
    left join public.chat_members cm
      on cm.chat_id = c.id
     and cm.user_id = p_user_id
    where c.id = p_chat_id
      and (
        c.created_by = p_user_id
        or cm.role = 'admin'
      )
  );
$$;

create function public.is_message_sender(
  p_message_id uuid,
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
    where m.id = p_message_id
      and m.sender_id = p_user_id
  );
$$;

create function public.is_call_participant(
  p_call_id uuid,
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
    from public.call_sessions cs
    where cs.id = p_call_id
      and (cs.caller_id = p_user_id or cs.callee_id = p_user_id)
  );
$$;

create function public.is_user_blocked(
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

create function public.find_direct_chat_between(
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

create function public.are_users_contacts(
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

create function public.can_access_profile_image(
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

create function public.can_view_profile_field(
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

create function public.is_private_account(
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

create function public.can_receive_call(
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

create function public.can_send_message_to_chat(
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

create function public.can_seed_chat_member(
  p_chat_id uuid,
  p_actor_id uuid,
  p_target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chats c
    where c.id = p_chat_id
      and c.created_by = p_actor_id
      and (
        (
          c.is_group = true
          and p_target_user_id = p_actor_id
          and not exists (
            select 1
            from public.chat_members cm
            where cm.chat_id = p_chat_id
          )
        )
        or (
          c.is_group = false
          and (
            select count(*)
            from public.chat_members cm
            where cm.chat_id = p_chat_id
          ) < 2
        )
      )
  );
$$;

create function public.has_accepted_request_for_member_insert(
  p_chat_id uuid,
  p_actor_id uuid,
  p_target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_requests cr
    join public.chats c on c.id = cr.chat_id
    where cr.chat_id = p_chat_id
      and cr.user_id = p_target_user_id
      and cr.status = 'accepted'
      and (
        p_actor_id = p_target_user_id
        or c.created_by = p_actor_id
        or exists (
          select 1
          from public.chat_members cm
          where cm.chat_id = p_chat_id
            and cm.user_id = p_actor_id
            and cm.role = 'admin'
        )
      )
  );
$$;

create function public.ensure_direct_chat(
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

create function public.get_visible_profiles_by_ids(
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

create function public.search_visible_profiles(
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

create function public.search_global_contacts(
  p_query text,
  p_limit integer default 30
)
returns table (
  user_id uuid,
  username text,
  avatar_id text,
  direct_chat_id uuid,
  shared_chat_count bigint,
  relevance real
)
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select
      nullif(btrim(p_query), '') as query,
      greatest(1, least(coalesce(p_limit, 30), 100)) as limit_value
  ),
  shared_chats as (
    select
      other.user_id as peer_user_id,
      count(distinct mine.chat_id)::bigint as shared_chat_count
    from public.chat_members mine
    join public.chat_members other
      on other.chat_id = mine.chat_id
     and other.user_id <> mine.user_id
    where mine.user_id = auth.uid()
    group by other.user_id
  ),
  ranked as (
    select
      p.id as user_id,
      p.username::text as username,
      p.avatar_id,
      public.find_direct_chat_between(auth.uid(), p.id) as direct_chat_id,
      coalesce(sc.shared_chat_count, 0)::bigint as shared_chat_count,
      similarity(p.username::text, n.query)::real as relevance
    from normalized n
    join public.profiles p on n.query is not null
    left join shared_chats sc on sc.peer_user_id = p.id
    where p.id <> auth.uid()
      and (
        p.username::text ilike '%' || n.query || '%'
        or p.username::text % n.query
      )
  )
  select
    ranked.user_id,
    ranked.username,
    ranked.avatar_id,
    ranked.direct_chat_id,
    ranked.shared_chat_count,
    ranked.relevance
  from ranked
  cross join normalized
  order by
    (ranked.direct_chat_id is not null) desc,
    ranked.shared_chat_count desc,
    ranked.relevance desc,
    ranked.username asc
  limit (select limit_value from normalized);
$$;

create function public.get_chat_participant_keys(
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

create function public.get_chat_inbox(
  p_user_id uuid
)
returns table (
  id uuid,
  is_group boolean,
  title text,
  group_image_url text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  members jsonb,
  latest_message jsonb,
  unread_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'get_chat_inbox can only be called for the authenticated user.';
  end if;

  return query
  select
    c.id,
    c.is_group,
    c.title,
    c.group_image_url,
    c.created_by,
    c.created_at,
    c.updated_at,
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(cm.*)
          || jsonb_build_object('profile', to_jsonb(vp.*))
          order by cm.joined_at
        )
        from public.chat_members cm
        left join lateral (
          select *
          from public.get_visible_profiles_by_ids(array[cm.user_id]) visible_profile
          limit 1
        ) vp on true
        where cm.chat_id = c.id
      ),
      '[]'::jsonb
    ) as members,
    (
      select to_jsonb(m.*)
        || jsonb_build_object(
          'message_receipts',
          coalesce(
            (
              select jsonb_agg(to_jsonb(mr.*))
              from public.message_receipts mr
              where mr.message_id = m.id
            ),
            '[]'::jsonb
          )
        )
      from public.messages m
      where m.chat_id = c.id
      order by m.created_at desc
      limit 1
    ) as latest_message,
    coalesce(
      (
        select count(*)
        from public.message_receipts mr
        where mr.chat_id = c.id
          and mr.user_id = p_user_id
          and mr.read_at is null
      ),
      0
    )::bigint as unread_count
  from public.chat_members own_membership
  join public.chats c on c.id = own_membership.chat_id
  left join public.chat_user_state state
    on state.chat_id = c.id
   and state.user_id = p_user_id
  where own_membership.user_id = p_user_id
    and state.hidden_at is null
  order by c.updated_at desc;
end;
$$;

create function public.secure_media_chat_id(
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

create function public.secure_media_message_id(
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

create function public.can_upload_secure_media_object(
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

create function public.can_access_secure_media_object(
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

create function public.can_delete_secure_media_object(
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

create function public.can_access_sticker(
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

create function public.can_save_sticker(
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

create function public.can_manage_sticker_storage_object(
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

create function public.soft_delete_message_for_everyone(
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

create function public.delete_chat(
  p_chat_id uuid
)
returns public.chats
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_row public.chats;
  is_group_chat boolean;
begin
  select c.is_group
  into is_group_chat
  from public.chats c
  where c.id = p_chat_id;

  if not found then
    raise exception 'Chat not found.';
  end if;

  if not coalesce(is_group_chat, false) then
    raise exception 'Direct chats cannot be hard-deleted.';
  end if;

  if not public.is_chat_admin(p_chat_id, auth.uid()) then
    raise exception 'Only group admins can delete this chat.';
  end if;

  delete from public.chats
  where id = p_chat_id
  returning * into deleted_row;

  if deleted_row.id is null then
    raise exception 'Chat could not be deleted.';
  end if;

  return deleted_row;
end;
$$;

create function public.mark_messages_read(
  p_chat_id uuid,
  p_message_ids uuid[]
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.message_receipts
  set delivered_at = coalesce(delivered_at, now()),
      read_at = now()
  where chat_id = p_chat_id
    and user_id = auth.uid()
    and message_id = any(p_message_ids);
$$;

create function public.mark_messages_delivered(
  p_chat_id uuid,
  p_message_ids uuid[]
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.message_receipts
  set delivered_at = coalesce(delivered_at, now())
  where chat_id = p_chat_id
    and user_id = auth.uid()
    and message_id = any(p_message_ids);
$$;

create function public.handle_chat_request_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('accepted', 'rejected')
     and new.responded_at is null then
    new.responded_at = now();
  end if;

  return new;
end;
$$;

create function public.attach_direct_chat_on_request_accept()
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

create function public.add_member_on_request_accept()
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

create function public.seed_message_receipts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.message_receipts (message_id, chat_id, user_id)
  select new.id, new.chat_id, cm.user_id
  from public.chat_members cm
  where cm.chat_id = new.chat_id
    and cm.user_id <> new.sender_id
  on conflict (message_id, user_id) do nothing;

  update public.chats
  set updated_at = now()
  where id = new.chat_id;

  return new;
end;
$$;

create function public.track_call_status_timestamps()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' and new.answered_at is null then
    new.answered_at = now();
  end if;

  if new.status in ('rejected', 'ended', 'missed') and old.status is distinct from new.status and new.ended_at is null then
    new.ended_at = now();
  end if;

  return new;
end;
$$;

create function public.heartbeat_profile_presence()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.profiles;
  heartbeat_at timestamptz := now();
begin
  update public.profiles
  set is_online = true,
      last_seen = heartbeat_at,
      last_seen_at = heartbeat_at,
      presence_heartbeat_at = heartbeat_at,
      presence_expires_at = heartbeat_at + interval '2 minutes'
  where id = auth.uid()
  returning * into updated_row;

  if updated_row.id is null then
    raise exception 'Profile not found for current user.';
  end if;

  return updated_row;
end;
$$;

create function public.set_profile_presence_offline()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.profiles;
  heartbeat_at timestamptz := now();
begin
  update public.profiles
  set is_online = false,
      last_seen = heartbeat_at,
      last_seen_at = heartbeat_at,
      presence_heartbeat_at = heartbeat_at,
      presence_expires_at = heartbeat_at
  where id = auth.uid()
  returning * into updated_row;

  if updated_row.id is null then
    raise exception 'Profile not found for current user.';
  end if;

  return updated_row;
end;
$$;

-- ============================================================================
-- Triggers
-- ============================================================================

create trigger trg_profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create trigger trg_chats_set_updated_at
before update on public.chats
for each row
execute function public.set_updated_at();

create trigger trg_messages_validate_reply_target
before insert or update on public.messages
for each row
execute function public.validate_message_reply_target();

create trigger trg_messages_seed_receipts
after insert on public.messages
for each row
execute function public.seed_message_receipts();

create trigger trg_chat_requests_status
before update on public.chat_requests
for each row
execute function public.handle_chat_request_status();

create trigger trg_chat_requests_attach_direct_chat
before update on public.chat_requests
for each row
execute function public.attach_direct_chat_on_request_accept();

create trigger trg_chat_requests_accept
after update on public.chat_requests
for each row
execute function public.add_member_on_request_accept();

create trigger trg_chat_requests_sync_parties
before insert or update on public.chat_requests
for each row
execute function public.sync_chat_request_parties();

create trigger trg_call_sessions_status
before update on public.call_sessions
for each row
execute function public.track_call_status_timestamps();

create trigger trg_profiles_sync_presence
before insert or update on public.profiles
for each row
execute function public.sync_profile_presence_columns();

-- ============================================================================
-- Grants
-- ============================================================================

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.chats to authenticated;
grant select, insert, update, delete on public.chat_members to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.message_receipts to authenticated;
grant select on public.stickers to anon, authenticated;
grant insert, update, delete on public.stickers to authenticated;
grant select, insert, update, delete on public.user_stickers to authenticated;
grant select, insert, update, delete on public.chat_requests to authenticated;
grant select, insert, update, delete on public.call_sessions to authenticated;
grant select, insert, update, delete on public.call_signals to authenticated;
grant select, insert, update, delete on public.blocked_users to authenticated;
grant insert on public.user_reports to authenticated;
grant select, insert, update, delete on public.chat_user_state to authenticated;

revoke all on public.direct_chat_pairs from public, anon, authenticated;

grant execute on function public.is_chat_member(uuid, uuid) to authenticated;
grant execute on function public.is_chat_admin(uuid, uuid) to authenticated;
grant execute on function public.is_message_sender(uuid, uuid) to authenticated;
grant execute on function public.is_call_participant(uuid, uuid) to authenticated;
grant execute on function public.is_user_blocked(uuid, uuid) to authenticated;
grant execute on function public.find_direct_chat_between(uuid, uuid) to authenticated;
grant execute on function public.are_users_contacts(uuid, uuid) to authenticated;
grant execute on function public.can_access_profile_image(uuid, uuid) to authenticated;
grant execute on function public.can_view_profile_field(uuid, uuid, text) to authenticated;
grant execute on function public.is_private_account(uuid) to authenticated;
grant execute on function public.can_receive_call(uuid, uuid) to authenticated;
grant execute on function public.can_send_message_to_chat(uuid, uuid) to authenticated;
grant execute on function public.can_seed_chat_member(uuid, uuid, uuid) to authenticated;
grant execute on function public.has_accepted_request_for_member_insert(uuid, uuid, uuid) to authenticated;
grant execute on function public.ensure_direct_chat(uuid, uuid) to authenticated;
grant execute on function public.get_visible_profiles_by_ids(uuid[]) to authenticated;
grant execute on function public.search_visible_profiles(text, integer) to authenticated;
grant execute on function public.search_global_contacts(text, integer) to authenticated;
grant execute on function public.get_chat_participant_keys(uuid) to authenticated;
grant execute on function public.get_chat_inbox(uuid) to authenticated;
grant execute on function public.secure_media_chat_id(text) to authenticated;
grant execute on function public.secure_media_message_id(text) to authenticated;
grant execute on function public.can_upload_secure_media_object(text, uuid) to authenticated;
grant execute on function public.can_access_secure_media_object(text, uuid) to authenticated;
grant execute on function public.can_delete_secure_media_object(text, uuid) to authenticated;
grant execute on function public.can_access_sticker(uuid, uuid) to authenticated;
grant execute on function public.can_save_sticker(uuid, uuid) to authenticated;
grant execute on function public.can_manage_sticker_storage_object(text, uuid) to authenticated;
grant execute on function public.soft_delete_message_for_everyone(uuid) to authenticated;
grant execute on function public.delete_chat(uuid) to authenticated;
grant execute on function public.mark_messages_read(uuid, uuid[]) to authenticated;
grant execute on function public.mark_messages_delivered(uuid, uuid[]) to authenticated;
grant execute on function public.heartbeat_profile_presence() to authenticated;
grant execute on function public.set_profile_presence_offline() to authenticated;

-- ============================================================================
-- Row Level Security
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_receipts enable row level security;
alter table public.stickers enable row level security;
alter table public.user_stickers enable row level security;
alter table public.chat_requests enable row level security;
alter table public.call_sessions enable row level security;
alter table public.call_signals enable row level security;
alter table public.blocked_users enable row level security;
alter table public.user_reports enable row level security;
alter table public.direct_chat_pairs enable row level security;
alter table public.chat_user_state enable row level security;

-- ============================================================================
-- Storage Buckets
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', false);

insert into storage.buckets (id, name, public)
values ('group-images', 'group-images', false);

insert into storage.buckets (id, name, public)
values ('secure-media', 'secure-media', false);

insert into storage.buckets (id, name, public)
values ('stickers', 'stickers', false);

-- ============================================================================
-- Policies
-- ============================================================================

create policy "profiles_select_authenticated"
on public.profiles
for select
to authenticated
using (auth.uid() = id);

create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "chats_select_members_or_groups"
on public.chats
for select
to authenticated
using (
  is_group = true
  or created_by = auth.uid()
  or public.is_chat_member(id, auth.uid())
);

create policy "chats_insert_creator_only"
on public.chats
for insert
to authenticated
with check (auth.uid() = created_by);

create policy "chats_update_admin_only"
on public.chats
for update
to authenticated
using (public.is_chat_admin(id, auth.uid()))
with check (public.is_chat_admin(id, auth.uid()));

create policy "chat_members_select_visible_groups_or_members"
on public.chat_members
for select
to authenticated
using (
  public.is_chat_member(chat_id, auth.uid())
  or exists (
    select 1
    from public.chats c
    where c.id = chat_id
      and c.is_group = true
  )
);

create policy "chat_members_insert_seed_or_accepted_request"
on public.chat_members
for insert
to authenticated
with check (
  public.can_seed_chat_member(chat_id, auth.uid(), user_id)
  or public.has_accepted_request_for_member_insert(chat_id, auth.uid(), user_id)
);

create policy "chat_members_update_admin_only"
on public.chat_members
for update
to authenticated
using (public.is_chat_admin(chat_id, auth.uid()))
with check (public.is_chat_admin(chat_id, auth.uid()));

create policy "messages_select_members_only"
on public.messages
for select
to authenticated
using (public.is_chat_member(chat_id, auth.uid()));

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

create policy "message_receipts_select_sender_or_recipient"
on public.message_receipts
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_message_sender(message_id, auth.uid())
);

create policy "message_receipts_update_recipient_only"
on public.message_receipts
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "stickers_select_public_or_owner"
on public.stickers
for select
to anon, authenticated
using (
  is_public = true
  or user_id = auth.uid()
);

create policy "stickers_insert_owner_only"
on public.stickers
for insert
to authenticated
with check (
  auth.uid() = user_id
  and storage_path like ('users/' || auth.uid()::text || '/%')
);

create policy "stickers_update_owner_only"
on public.stickers
for update
to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and storage_path like ('users/' || auth.uid()::text || '/%')
);

create policy "stickers_delete_owner_only"
on public.stickers
for delete
to authenticated
using (auth.uid() = user_id);

create policy "user_stickers_select_owner_only"
on public.user_stickers
for select
to authenticated
using (auth.uid() = user_id);

create policy "user_stickers_insert_owner_only"
on public.user_stickers
for insert
to authenticated
with check (
  auth.uid() = user_id
  and public.can_save_sticker(sticker_id, auth.uid())
);

create policy "user_stickers_update_owner_only"
on public.user_stickers
for update
to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and public.can_save_sticker(sticker_id, auth.uid())
);

create policy "user_stickers_delete_owner_only"
on public.user_stickers
for delete
to authenticated
using (auth.uid() = user_id);

create policy "chat_requests_select_related_parties"
on public.chat_requests
for select
to authenticated
using (
  user_id = auth.uid()
  or requested_by = auth.uid()
  or public.is_chat_admin(chat_id, auth.uid())
);

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

create policy "call_sessions_select_participants_only"
on public.call_sessions
for select
to authenticated
using (caller_id = auth.uid() or callee_id = auth.uid());

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

create policy "call_sessions_update_participants_only"
on public.call_sessions
for update
to authenticated
using (caller_id = auth.uid() or callee_id = auth.uid())
with check (caller_id = auth.uid() or callee_id = auth.uid());

create policy "call_signals_select_participants_only"
on public.call_signals
for select
to authenticated
using (public.is_call_participant(call_id, auth.uid()));

create policy "call_signals_insert_participants_only"
on public.call_signals
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.is_call_participant(call_id, auth.uid())
);

create policy "blocked_users_select_own"
on public.blocked_users
for select
to authenticated
using (blocker_id = auth.uid());

create policy "blocked_users_insert_own"
on public.blocked_users
for insert
to authenticated
with check (blocker_id = auth.uid());

create policy "blocked_users_delete_own"
on public.blocked_users
for delete
to authenticated
using (blocker_id = auth.uid());

create policy "user_reports_insert_own"
on public.user_reports
for insert
to authenticated
with check (reporter_id = auth.uid());

create policy "chat_user_state_owner_only"
on public.chat_user_state
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "profile_images_select_visible"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'profile-images'
  and public.can_access_profile_image(((storage.foldername(name))[1])::uuid, auth.uid())
);

create policy "profile_images_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

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

create policy "profile_images_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

create policy "group_images_select_members_only"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'group-images'
  and exists (
    select 1
    from public.chat_members cm
    where cm.chat_id::text = split_part(name, '/', 1)
      and cm.user_id = auth.uid()
  )
);

create policy "group_images_insert_admin"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'group-images'
  and public.is_chat_admin(((storage.foldername(name))[1])::uuid, auth.uid())
);

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

create policy "group_images_delete_admin"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'group-images'
  and public.is_chat_admin(((storage.foldername(name))[1])::uuid, auth.uid())
);

create policy "secure_media_select_authenticated"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'secure-media'
  and public.can_access_secure_media_object(name, auth.uid())
);

create policy "secure_media_insert_authenticated"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'secure-media'
  and public.can_upload_secure_media_object(name, auth.uid())
);

create policy "secure_media_delete_authenticated"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'secure-media'
  and public.can_delete_secure_media_object(name, auth.uid())
);

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

create policy "stickers_insert_authenticated"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'stickers'
  and public.can_manage_sticker_storage_object(name, auth.uid())
);

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

create policy "stickers_delete_authenticated"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'stickers'
  and public.can_manage_sticker_storage_object(name, auth.uid())
);

-- ============================================================================
-- Realtime Publication
-- ============================================================================

alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.message_receipts;
alter publication supabase_realtime add table public.call_sessions;
alter publication supabase_realtime add table public.call_signals;

