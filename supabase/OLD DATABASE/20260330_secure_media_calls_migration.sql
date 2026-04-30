-- Incremental migration for the secure messaging, encrypted media, receipts,
-- sender-only message deletion tombstones, and free WebRTC calling update.
--
-- This migration is written as an update for an existing CipherChat schema.
-- It expects `public.messages` to already exist. The only time it recreates the
-- table is when it detects an incompatible legacy shape that still uses
-- `content_encrypted`; in that case it first backs the legacy table up to
-- `public.messages_legacy_backup_20260330`.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists citext;

alter table if exists public.profiles
  add column if not exists e2ee_public_key text;

do $$
begin
  if to_regclass('public.messages') is null then
    if to_regclass('public.messages_legacy_backup_20260330') is null then
      raise exception 'Expected public.messages to exist before running 20260330_secure_media_calls_migration.sql';
    end if;
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'messages'
      and column_name = 'content_encrypted'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'messages'
      and column_name = 'payload_encrypted'
  ) then
    if to_regclass('public.messages_legacy_backup_20260330') is not null then
      raise exception 'Legacy messages backup already exists. Resolve public.messages manually before rerunning this migration.';
    end if;

    alter table public.messages rename to messages_legacy_backup_20260330;
  end if;

  if to_regclass('public.messages') is null then
    create table public.messages (
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
        check (message_type in ('text', 'image', 'video', 'file')),
      constraint messages_payload_object_check
        check (jsonb_typeof(payload_encrypted) = 'object'),
      constraint messages_key_envelopes_object_check
        check (jsonb_typeof(key_envelopes) = 'object'),
      constraint messages_sender_key_not_blank
        check (char_length(trim(sender_key_public)) > 0)
    );
  end if;
end
$$;

alter table public.messages
  add column if not exists reply_to_message_id uuid references public.messages (id) on delete set null;

alter table public.messages
  add column if not exists deleted_for_everyone_at timestamptz;

alter table public.messages
  add column if not exists deleted_for_everyone_by uuid references public.profiles (id) on delete set null;

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

create index if not exists idx_messages_chat_created_at on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_reply_to_message on public.messages (reply_to_message_id);
create index if not exists idx_message_receipts_chat_user on public.message_receipts (chat_id, user_id, created_at desc);
create index if not exists idx_message_receipts_message on public.message_receipts (message_id);
create index if not exists idx_call_sessions_callee_status on public.call_sessions (callee_id, status, created_at desc);
create index if not exists idx_call_sessions_chat_status on public.call_sessions (chat_id, status, created_at desc);
create index if not exists idx_call_signals_call_created_at on public.call_signals (call_id, created_at asc);

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

drop trigger if exists trg_call_sessions_status on public.call_sessions;
create trigger trg_call_sessions_status
before update on public.call_sessions
for each row
execute function public.track_call_status_timestamps();

grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.message_receipts to authenticated;
grant select, insert, update, delete on public.call_sessions to authenticated;
grant select, insert, update, delete on public.call_signals to authenticated;
grant execute on function public.is_message_sender(uuid, uuid) to authenticated;
grant execute on function public.is_call_participant(uuid, uuid) to authenticated;
grant execute on function public.soft_delete_message_for_everyone(uuid) to authenticated;

alter table public.messages enable row level security;
alter table public.message_receipts enable row level security;
alter table public.call_sessions enable row level security;
alter table public.call_signals enable row level security;

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
