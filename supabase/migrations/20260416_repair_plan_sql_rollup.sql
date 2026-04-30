-- Rollup migration for the SQL-side CipherChat repair plan changes.
-- This is intentionally idempotent so it can be applied to databases that
-- already received part of the repair work from earlier migration files.

begin;

-- ---------------------------------------------------------------------------
-- Sticker privacy: metadata is public-or-owner only, and sticker objects are
-- served from a private bucket through signed URLs.
-- ---------------------------------------------------------------------------

drop policy if exists "stickers_select_public_or_owner" on public.stickers;

create policy "stickers_select_public_or_owner"
on public.stickers
for select
to anon, authenticated
using (
  is_public = true
  or user_id = auth.uid()
);

insert into storage.buckets (id, name, public)
values ('stickers', 'stickers', false)
on conflict (id) do update
set public = false;

drop policy if exists "stickers_select_public" on storage.objects;
drop policy if exists "stickers_select_public_or_owner" on storage.objects;

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

-- ---------------------------------------------------------------------------
-- Group image privacy: authenticated users can no longer read every group
-- image; only members of the owning chat can read the object.
-- ---------------------------------------------------------------------------

drop policy if exists "group_images_select_authenticated" on storage.objects;
drop policy if exists "group_images_select_members_only" on storage.objects;

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

-- ---------------------------------------------------------------------------
-- Per-user chat state: direct chats are hidden per user instead of hard-deleted.
-- ---------------------------------------------------------------------------

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

grant select, insert, update, delete on public.chat_user_state to authenticated;

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

grant execute on function public.delete_chat(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Receipt writes use database time, not client-supplied timestamps.
-- ---------------------------------------------------------------------------

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

grant execute on function public.mark_messages_read(uuid, uuid[]) to authenticated;
grant execute on function public.mark_messages_delivered(uuid, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Prevent overlapping active calls in the same chat.
-- ---------------------------------------------------------------------------

create unique index if not exists idx_call_sessions_one_active_call_per_chat
on public.call_sessions (chat_id)
where status in ('ringing', 'accepted');

-- ---------------------------------------------------------------------------
-- Chat inbox RPC: replaces client-side N+1 chat list hydration.
-- ---------------------------------------------------------------------------

create index if not exists idx_chat_members_user
on public.chat_members (user_id);

create index if not exists idx_messages_chat_created_at
on public.messages (chat_id, created_at desc);

create or replace function public.get_chat_inbox(
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

grant execute on function public.get_chat_inbox(uuid) to authenticated;

commit;
