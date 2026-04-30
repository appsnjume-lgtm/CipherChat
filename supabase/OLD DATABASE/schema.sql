-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $do `-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $do `-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.messages m
    where m.id = new.reply_to_message_id
      and m.chat_id = new.chat_id
  ) then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$$;

create or replace function public.is_chat_member(
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

create or replace function public.is_chat_admin(
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

create or replace function public.is_message_sender(
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

create or replace function public.is_call_participant(
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

create or replace function public.can_seed_chat_member(
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

create or replace function public.has_accepted_request_for_member_insert(
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

create or replace function public.handle_chat_request_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $do `-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.messages m
    where m.id = new.reply_to_message_id
      and m.chat_id = new.chat_id
  ) then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$$;

create or replace function public.is_chat_member(
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

create or replace function public.is_chat_admin(
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

create or replace function public.is_message_sender(
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

create or replace function public.is_call_participant(
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

create or replace function public.can_seed_chat_member(
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

create or replace function public.has_accepted_request_for_member_insert(
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

create or replace function public.handle_chat_request_status()
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

create or replace function public.add_member_on_request_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $do `-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.messages m
    where m.id = new.reply_to_message_id
      and m.chat_id = new.chat_id
  ) then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$$;

create or replace function public.is_chat_member(
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

create or replace function public.is_chat_admin(
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

create or replace function public.is_message_sender(
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

create or replace function public.is_call_participant(
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

create or replace function public.can_seed_chat_member(
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

create or replace function public.has_accepted_request_for_member_insert(
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

create or replace function public.handle_chat_request_status()
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

create or replace function public.add_member_on_request_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    insert into public.chat_members (chat_id, user_id, role)
    values (new.chat_id, new.user_id, 'member')
    on conflict (chat_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

create or replace function public.seed_message_receipts()
returns trigger
language plpgsql
security definer
set search_path = public
as $do `-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.messages m
    where m.id = new.reply_to_message_id
      and m.chat_id = new.chat_id
  ) then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$$;

create or replace function public.is_chat_member(
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

create or replace function public.is_chat_admin(
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

create or replace function public.is_message_sender(
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

create or replace function public.is_call_participant(
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

create or replace function public.can_seed_chat_member(
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

create or replace function public.has_accepted_request_for_member_insert(
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

create or replace function public.handle_chat_request_status()
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

create or replace function public.add_member_on_request_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    insert into public.chat_members (chat_id, user_id, role)
    values (new.chat_id, new.user_id, 'member')
    on conflict (chat_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

create or replace function public.seed_message_receipts()
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

create or replace function public.track_call_status_timestamps()
returns trigger
language plpgsql
security definer
set search_path = public
as $do `-- CipherChat secure messaging + free WebRTC calling schema.
-- This schema is intended for a fresh Supabase project.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique,
  gender text not null default 'male',
  avatar_id text not null default 'avatar_1',
  e2ee_public_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length_check
    check (char_length(trim(username::text)) between 3 and 32),
  constraint profiles_gender_check
    check (gender in ('male', 'female')),
  constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    )
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_title_check
    check ((is_group = false) or (char_length(coalesce(trim(title), '')) <= 120))
);

create table if not exists public.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  constraint chat_members_role_check check (role in ('admin', 'member')),
  constraint chat_members_unique unique (chat_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.messages (id) on delete set null,
  message_type text not null,
  payload_encrypted jsonb not null,
  key_envelopes jsonb not null,
  sender_key_public text not null,
  created_at timestamptz not null default now(),
  deleted_for_everyone_at timestamptz,
  deleted_for_everyone_by uuid references public.profiles (id) on delete set null,
  constraint messages_type_check
    check (message_type in ('text', 'image', 'video', 'file', 'audio')),
  constraint messages_payload_object_check
    check (jsonb_typeof(payload_encrypted) = 'object'),
  constraint messages_key_envelopes_object_check
    check (jsonb_typeof(key_envelopes) = 'object'),
  constraint messages_sender_key_not_blank
    check (char_length(trim(sender_key_public)) > 0)
);

create table if not exists public.message_receipts (
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

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint chat_requests_type_check check (type in ('join_request', 'invite')),
  constraint chat_requests_status_check check (status in ('pending', 'accepted', 'rejected')),
  constraint chat_requests_invite_actor_check
    check ((type = 'join_request') or (user_id <> requested_by))
);

create table if not exists public.call_sessions (
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

create table if not exists public.call_signals (
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

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin ((username::text) gin_trgm_ops);
create index if not exists idx_chats_created_by on public.chats (created_by);
create index if not exists idx_chats_group_created_at on public.chats (is_group, created_at desc);
create index if not exists idx_chat_members_chat on public.chat_members (chat_id);
create index if not exists idx_chat_members_user on public.chat_members (user_id);
create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_chat_requests_user_status on public.chat_requests (user_id, status, created_at desc);
create index if not exists idx_chat_requests_chat_status on public.chat_requests (chat_id, status, created_at desc);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);
create unique index if not exists idx_pending_chat_requests_unique
  on public.chat_requests (chat_id, user_id, type)
  where status = 'pending';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.messages m
    where m.id = new.reply_to_message_id
      and m.chat_id = new.chat_id
  ) then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$$;

create or replace function public.is_chat_member(
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

create or replace function public.is_chat_admin(
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

create or replace function public.is_message_sender(
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

create or replace function public.is_call_participant(
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

create or replace function public.can_seed_chat_member(
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

create or replace function public.has_accepted_request_for_member_insert(
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

create or replace function public.handle_chat_request_status()
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

create or replace function public.add_member_on_request_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    insert into public.chat_members (chat_id, user_id, role)
    values (new.chat_id, new.user_id, 'member')
    on conflict (chat_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

create or replace function public.seed_message_receipts()
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

create or replace function public.track_call_status_timestamps()
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

drop trigger if exists trg_profiles_set_updated_at on public.profiles;
create trigger trg_profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

drop trigger if exists trg_chats_set_updated_at on public.chats;
create trigger trg_chats_set_updated_at
before update on public.chats
for each row
execute function public.set_updated_at();

drop trigger if exists trg_messages_validate_reply_target on public.messages;
create trigger trg_messages_validate_reply_target
before insert or update on public.messages
for each row
execute function public.validate_message_reply_target();

drop trigger if exists trg_messages_seed_receipts on public.messages;
create trigger trg_messages_seed_receipts
after insert on public.messages
for each row
execute function public.seed_message_receipts();

drop trigger if exists trg_chat_requests_status on public.chat_requests;
create trigger trg_chat_requests_status
before update on public.chat_requests
for each row
execute function public.handle_chat_request_status();

drop trigger if exists trg_chat_requests_accept on public.chat_requests;
create trigger trg_chat_requests_accept
after update on public.chat_requests
for each row
execute function public.add_member_on_request_accept();

drop trigger if exists trg_call_sessions_status on public.call_sessions;
create trigger trg_call_sessions_status
before update on public.call_sessions
for each row
execute function public.track_call_status_timestamps();

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.chats to authenticated;
grant select, insert, update, delete on public.chat_members to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.message_receipts to authenticated;
grant select, insert, update, delete on public.chat_requests to authenticated;
grant select, insert, update, delete on public.call_sessions to authenticated;
grant select, insert, update, delete on public.call_signals to authenticated;
grant execute on function public.is_chat_member(uuid, uuid) to authenticated;
grant execute on function public.is_chat_admin(uuid, uuid) to authenticated;
grant execute on function public.is_message_sender(uuid, uuid) to authenticated;
grant execute on function public.is_call_participant(uuid, uuid) to authenticated;
grant execute on function public.soft_delete_message_for_everyone(uuid) to authenticated;
grant execute on function public.can_seed_chat_member(uuid, uuid, uuid) to authenticated;
grant execute on function public.has_accepted_request_for_member_insert(uuid, uuid, uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_receipts enable row level security;
alter table public.chat_requests enable row level security;
alter table public.call_sessions enable row level security;
alter table public.call_signals enable row level security;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
on public.profiles
for select
to authenticated
using (auth.role() = 'authenticated');

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "chats_select_members_or_groups" on public.chats;
create policy "chats_select_members_or_groups"
on public.chats
for select
to authenticated
using (
  is_group = true
  or created_by = auth.uid()
  or public.is_chat_member(id, auth.uid())
);

drop policy if exists "chats_insert_creator_only" on public.chats;
create policy "chats_insert_creator_only"
on public.chats
for insert
to authenticated
with check (auth.uid() = created_by);

drop policy if exists "chats_update_admin_only" on public.chats;
create policy "chats_update_admin_only"
on public.chats
for update
to authenticated
using (public.is_chat_admin(id, auth.uid()))
with check (public.is_chat_admin(id, auth.uid()));

drop policy if exists "chat_members_select_visible_groups_or_members" on public.chat_members;
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

drop policy if exists "chat_members_insert_seed_or_accepted_request" on public.chat_members;
create policy "chat_members_insert_seed_or_accepted_request"
on public.chat_members
for insert
to authenticated
with check (
  public.can_seed_chat_member(chat_id, auth.uid(), user_id)
  or public.has_accepted_request_for_member_insert(chat_id, auth.uid(), user_id)
);

drop policy if exists "chat_members_update_admin_only" on public.chat_members;
create policy "chat_members_update_admin_only"
on public.chat_members
for update
to authenticated
using (public.is_chat_admin(chat_id, auth.uid()))
with check (public.is_chat_admin(chat_id, auth.uid()));

drop policy if exists "messages_select_members_only" on public.messages;
create policy "messages_select_members_only"
on public.messages
for select
to authenticated
using (public.is_chat_member(chat_id, auth.uid()));

drop policy if exists "messages_insert_members_only" on public.messages;
create policy "messages_insert_members_only"
on public.messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and public.is_chat_member(chat_id, auth.uid())
);

drop policy if exists "message_receipts_select_sender_or_recipient" on public.message_receipts;
create policy "message_receipts_select_sender_or_recipient"
on public.message_receipts
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_message_sender(message_id, auth.uid())
);

drop policy if exists "message_receipts_update_recipient_only" on public.message_receipts;
create policy "message_receipts_update_recipient_only"
on public.message_receipts
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "chat_requests_select_related_parties" on public.chat_requests;
create policy "chat_requests_select_related_parties"
on public.chat_requests
for select
to authenticated
using (
  user_id = auth.uid()
  or requested_by = auth.uid()
  or public.is_chat_admin(chat_id, auth.uid())
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
    and requested_by = auth.uid()
    and user_id <> auth.uid()
    and public.is_chat_admin(chat_id, auth.uid())
    and not public.is_chat_member(chat_id, user_id)
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
    and public.is_chat_admin(chat_id, auth.uid())
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
      and public.is_chat_admin(chat_id, auth.uid())
    )
  )
);

drop policy if exists "call_sessions_select_participants_only" on public.call_sessions;
create policy "call_sessions_select_participants_only"
on public.call_sessions
for select
to authenticated
using (caller_id = auth.uid() or callee_id = auth.uid());

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
);

drop policy if exists "call_sessions_update_participants_only" on public.call_sessions;
create policy "call_sessions_update_participants_only"
on public.call_sessions
for update
to authenticated
using (caller_id = auth.uid() or callee_id = auth.uid())
with check (caller_id = auth.uid() or callee_id = auth.uid());

drop policy if exists "call_signals_select_participants_only" on public.call_signals;
create policy "call_signals_select_participants_only"
on public.call_signals
for select
to authenticated
using (public.is_call_participant(call_id, auth.uid()));

drop policy if exists "call_signals_insert_participants_only" on public.call_signals;
create policy "call_signals_insert_participants_only"
on public.call_signals
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.is_call_participant(call_id, auth.uid())
);

insert into storage.buckets (id, name, public)
values ('secure-media', 'secure-media', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "secure_media_select_authenticated" on storage.objects;
create policy "secure_media_select_authenticated"
on storage.objects
for select
to authenticated
using (bucket_id = 'secure-media');

drop policy if exists "secure_media_insert_authenticated" on storage.objects;
create policy "secure_media_insert_authenticated"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'secure-media');

drop policy if exists "secure_media_delete_authenticated" on storage.objects;
create policy "secure_media_delete_authenticated"
on storage.objects
for delete
to authenticated
using (bucket_id = 'secure-media');

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_receipts'
  ) then
    alter publication supabase_realtime add table public.message_receipts;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'call_sessions'
  ) then
    alter publication supabase_realtime add table public.call_sessions;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'call_signals'
  ) then
    alter publication supabase_realtime add table public.call_signals;
  end if;
end
$$;

alter table if exists public.profiles
  add column if not exists presence_heartbeat_at timestamptz,
  add column if not exists presence_expires_at timestamptz;

update public.profiles
set presence_heartbeat_at = coalesce(
      presence_heartbeat_at,
      last_seen,
      last_seen_at,
      updated_at,
      created_at,
      now()
    ),
    presence_expires_at = coalesce(
      presence_expires_at,
      case
        when coalesce(is_online, false) then
          coalesce(
            presence_heartbeat_at,
            last_seen,
            last_seen_at,
            updated_at,
            created_at,
            now()
          ) + interval '2 minutes'
        else
          coalesce(
            presence_heartbeat_at,
            last_seen,
            last_seen_at,
            updated_at,
            created_at,
            now()
          )
      end
    )
where presence_heartbeat_at is null
   or presence_expires_at is null;

alter table if exists public.profiles
  alter column presence_heartbeat_at set default now(),
  alter column presence_expires_at set default (now() + interval '2 minutes');

alter table if exists public.profiles
  alter column presence_heartbeat_at set not null,
  alter column presence_expires_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_presence_expiry_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_presence_expiry_check
      check (presence_expires_at >= presence_heartbeat_at);
  end if;
end
$$;

create or replace function public.sync_profile_presence_columns()
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

drop trigger if exists trg_profiles_sync_presence on public.profiles;
create trigger trg_profiles_sync_presence
before insert or update on public.profiles
for each row
execute function public.sync_profile_presence_columns();

create or replace function public.heartbeat_profile_presence()
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

create or replace function public.set_profile_presence_offline()
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

grant execute on function public.heartbeat_profile_presence() to authenticated;
grant execute on function public.set_profile_presence_offline() to authenticated;
