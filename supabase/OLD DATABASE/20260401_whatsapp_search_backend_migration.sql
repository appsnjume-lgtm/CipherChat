-- WhatsApp-style search backend primitives for CipherChat.
--
-- Important privacy note:
-- Messages are stored end-to-end encrypted in `payload_encrypted`, so Postgres
-- cannot search message bodies unless the client also writes a separate
-- searchable plaintext copy. This migration adds `public.messages.search_text`
-- for that purpose.
--
-- Recommended app behavior:
-- - Text messages: write normalized plaintext into `search_text`.
-- - Media/file messages: write searchable captions or filenames into `search_text`.
-- - If you want maximum privacy instead, leave `search_text` null and perform
--   message search only on-device.

create extension if not exists pg_trgm;

alter table if exists public.messages
  add column if not exists search_text text;

comment on column public.messages.search_text is
  'Optional plaintext search index written by the client to support server-side message search alongside encrypted payload_encrypted.';

update public.messages
set search_text = null
where deleted_for_everyone_at is not null
  and search_text is not null;

create or replace function public.normalize_message_search_text()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_for_everyone_at is not null then
    new.search_text = null;
    return new;
  end if;

  if new.search_text is not null then
    new.search_text = nullif(
      regexp_replace(btrim(new.search_text), '\s+', ' ', 'g'),
      ''
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_messages_normalize_search_text on public.messages;
create trigger trg_messages_normalize_search_text
before insert or update of search_text, deleted_for_everyone_at on public.messages
for each row
execute function public.normalize_message_search_text();

create index if not exists idx_messages_search_text_trgm
  on public.messages using gin (search_text gin_trgm_ops)
  where search_text is not null and deleted_for_everyone_at is null;

create index if not exists idx_messages_search_text_fts
  on public.messages using gin (to_tsvector('simple', coalesce(search_text, '')))
  where deleted_for_everyone_at is null;

create index if not exists idx_chats_group_title_trgm
  on public.chats using gin ((coalesce(title, '')::text) gin_trgm_ops)
  where is_group = true;

create or replace function public.build_search_snippet(
  p_text text,
  p_query text,
  p_context integer default 48
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized_text text := coalesce(p_text, '');
  normalized_query text := coalesce(btrim(p_query), '');
  context_size integer := greatest(coalesce(p_context, 48), 8);
  match_pos integer;
  snippet_start integer;
  snippet_length integer;
begin
  if normalized_text = '' then
    return '';
  end if;

  if normalized_query = '' then
    return left(normalized_text, context_size * 2);
  end if;

  match_pos := strpos(lower(normalized_text), lower(normalized_query));

  if match_pos <= 0 then
    return left(normalized_text, context_size * 2);
  end if;

  snippet_start := greatest(match_pos - context_size, 1);
  snippet_length := least(
    char_length(normalized_text) - snippet_start + 1,
    char_length(normalized_query) + (context_size * 2)
  );

  return concat(
    case when snippet_start > 1 then '...' else '' end,
    substr(normalized_text, snippet_start, snippet_length),
    case
      when snippet_start + snippet_length - 1 < char_length(normalized_text)
        then '...'
      else ''
    end
  );
end;
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
      search_text = null,
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

create or replace function public.search_chat_messages(
  p_chat_id uuid,
  p_query text,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (
  message_id uuid,
  chat_id uuid,
  sender_id uuid,
  message_type text,
  created_at timestamptz,
  search_text text,
  snippet text,
  match_position integer,
  total_matches bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select
      nullif(btrim(p_query), '') as query,
      greatest(1, least(coalesce(p_limit, 200), 500)) as limit_value,
      greatest(coalesce(p_offset, 0), 0) as offset_value
  ),
  matches as (
    select
      m.id as message_id,
      m.chat_id,
      m.sender_id,
      m.message_type,
      m.created_at,
      m.search_text,
      public.build_search_snippet(m.search_text, n.query) as snippet,
      strpos(lower(m.search_text), lower(n.query)) as match_position,
      count(*) over () as total_matches
    from normalized n
    join public.messages m on n.query is not null
    where public.is_chat_member(p_chat_id, auth.uid())
      and m.chat_id = p_chat_id
      and m.deleted_for_everyone_at is null
      and m.search_text is not null
      and (
        m.search_text ilike '%' || n.query || '%'
        or to_tsvector('simple', m.search_text) @@ websearch_to_tsquery('simple', n.query)
      )
  )
  select
    matches.message_id,
    matches.chat_id,
    matches.sender_id,
    matches.message_type,
    matches.created_at,
    matches.search_text,
    matches.snippet,
    matches.match_position,
    matches.total_matches
  from matches
  cross join normalized
  order by matches.created_at asc, matches.message_id asc
  limit (select limit_value from normalized)
  offset (select offset_value from normalized);
$$;

create or replace function public.search_global_messages(
  p_query text,
  p_limit integer default 40,
  p_offset integer default 0
)
returns table (
  message_id uuid,
  chat_id uuid,
  sender_id uuid,
  message_type text,
  created_at timestamptz,
  search_text text,
  snippet text,
  chat_label text,
  is_group boolean,
  sender_username text,
  match_position integer,
  relevance real,
  total_matches bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select
      nullif(btrim(p_query), '') as query,
      greatest(1, least(coalesce(p_limit, 40), 200)) as limit_value,
      greatest(coalesce(p_offset, 0), 0) as offset_value
  ),
  member_chats as (
    select cm.chat_id
    from public.chat_members cm
    where cm.user_id = auth.uid()
  ),
  chat_context as (
    select
      c.id as chat_id,
      c.is_group,
      case
        when c.is_group then coalesce(nullif(btrim(c.title), ''), 'Unnamed group')
        else coalesce(peer.username::text, 'Direct chat')
      end as chat_label
    from public.chats c
    join member_chats mc on mc.chat_id = c.id
    left join lateral (
      select p.username
      from public.chat_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.chat_id = c.id
        and cm.user_id <> auth.uid()
      order by cm.joined_at asc
      limit 1
    ) peer on true
  ),
  matches as (
    select
      m.id as message_id,
      m.chat_id,
      m.sender_id,
      m.message_type,
      m.created_at,
      m.search_text,
      public.build_search_snippet(m.search_text, n.query) as snippet,
      ctx.chat_label,
      ctx.is_group,
      sender.username::text as sender_username,
      strpos(lower(m.search_text), lower(n.query)) as match_position,
      greatest(
        similarity(coalesce(m.search_text, ''), n.query),
        similarity(coalesce(ctx.chat_label, ''), n.query),
        similarity(coalesce(sender.username::text, ''), n.query)
      )::real as relevance,
      count(*) over () as total_matches
    from normalized n
    join member_chats mc on n.query is not null
    join public.messages m on m.chat_id = mc.chat_id
    join chat_context ctx on ctx.chat_id = m.chat_id
    join public.profiles sender on sender.id = m.sender_id
    where m.deleted_for_everyone_at is null
      and m.search_text is not null
      and (
        m.search_text ilike '%' || n.query || '%'
        or to_tsvector('simple', m.search_text) @@ websearch_to_tsquery('simple', n.query)
      )
  )
  select
    matches.message_id,
    matches.chat_id,
    matches.sender_id,
    matches.message_type,
    matches.created_at,
    matches.search_text,
    matches.snippet,
    matches.chat_label,
    matches.is_group,
    matches.sender_username,
    matches.match_position,
    matches.relevance,
    matches.total_matches
  from matches
  cross join normalized
  order by matches.relevance desc, matches.created_at desc, matches.message_id desc
  limit (select limit_value from normalized)
  offset (select offset_value from normalized);
$$;

create or replace function public.search_global_contacts(
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

grant execute on function public.build_search_snippet(text, text, integer) to authenticated;
grant execute on function public.search_chat_messages(uuid, text, integer, integer) to authenticated;
grant execute on function public.search_global_messages(text, integer, integer) to authenticated;
grant execute on function public.search_global_contacts(text, integer) to authenticated;
grant execute on function public.soft_delete_message_for_everyone(uuid) to authenticated;
