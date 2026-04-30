-- Pre-production hardening for launch-blocking issues found during audit.
-- 1. Restrict group image reads to chat members.
-- 2. Prevent direct-message hard deletes; introduce per-user chat state.
-- 3. Move read/delivery timestamps to the database clock.
-- 4. Prevent overlapping active calls in the same chat.

begin;

drop policy if exists "group_images_select_authenticated" on storage.objects;

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

create table if not exists public.chat_user_state (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  archived_at timestamptz,
  hidden_at timestamptz,
  primary key (chat_id, user_id)
);

create index if not exists idx_chat_user_state_user_archived
on public.chat_user_state (user_id, archived_at desc);

alter table public.chat_user_state enable row level security;

drop policy if exists "chat_user_state_owner_only" on public.chat_user_state;

create policy "chat_user_state_owner_only"
on public.chat_user_state
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.delete_chat(
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

create or replace function public.mark_messages_read(
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

create or replace function public.mark_messages_delivered(
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

create unique index if not exists idx_call_sessions_one_active_call_per_chat
on public.call_sessions (chat_id)
where status in ('ringing', 'accepted');

commit;
