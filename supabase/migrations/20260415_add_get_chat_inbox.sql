begin;

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
