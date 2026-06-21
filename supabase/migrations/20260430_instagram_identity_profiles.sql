begin;

alter table public.profiles
add column if not exists display_name text;

do $$
declare
  collision_count integer;
  invalid_count integer;
begin
  select count(*)
  into collision_count
  from (
    select lower(trim(username::text)) as normalized_username
    from public.profiles
    where username is not null
    group by lower(trim(username::text))
    having count(*) > 1
  ) collisions;

  if collision_count > 0 then
    raise exception 'Cannot normalize usernames: % normalized username collision(s) found.', collision_count;
  end if;

  select count(*)
  into invalid_count
  from public.profiles
  where username is not null
    and (
      lower(trim(username::text)) !~ '^[a-z0-9._]+$'
      or char_length(trim(username::text)) not between 3 and 24
    );

  if invalid_count > 0 then
    raise exception 'Cannot enforce strict usernames: % existing username(s) would fail the new rules.', invalid_count;
  end if;
end;
$$;

update public.profiles
set username = lower(trim(username::text))
where username is not null;

update public.profiles
set display_name = username::text
where display_name is null;

alter table public.profiles
drop constraint if exists profiles_username_format_check;

alter table public.profiles
add constraint profiles_username_format_check
check (username::text ~ '^[a-z0-9._]+$');

alter table public.profiles
drop constraint if exists profiles_username_length_check;

alter table public.profiles
add constraint profiles_username_length_check
check (char_length(trim(username::text)) between 3 and 24);

drop function if exists public.get_visible_profiles_by_ids(uuid[]);
drop function if exists public.search_visible_profiles(text, integer);
drop function if exists public.search_global_contacts(text, integer);

create function public.get_visible_profiles_by_ids(
  p_user_ids uuid[]
)
returns table (
  id uuid,
  username text,
  display_name text,
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
    coalesce(nullif(s.display_name, ''), s.username::text) as display_name,
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
  display_name text,
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
    coalesce(nullif(s.display_name, ''), s.username::text) as display_name,
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
  display_name text,
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
      coalesce(nullif(p.display_name, ''), p.username::text) as display_name,
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
    ranked.display_name,
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

grant execute on function public.get_visible_profiles_by_ids(uuid[]) to authenticated;
grant execute on function public.search_visible_profiles(text, integer) to authenticated;
grant execute on function public.search_global_contacts(text, integer) to authenticated;

commit;
