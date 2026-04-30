-- Adds a server-side chat deletion RPC.
--
-- Direct chats can be deleted by any participant.
-- Group chats can only be deleted by a group admin.
-- Deleting a chat cascades to members, messages, receipts, requests, and calls.

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
begin
  if not exists (
    select 1
    from public.chats c
    where c.id = p_chat_id
  ) then
    raise exception 'Chat not found.';
  end if;

  if exists (
    select 1
    from public.chats c
    where c.id = p_chat_id
      and c.is_group = true
  ) then
    if not public.is_chat_admin(p_chat_id, auth.uid()) then
      raise exception 'Only group admins can delete this chat.';
    end if;
  elsif not public.is_chat_member(p_chat_id, auth.uid()) then
    raise exception 'You do not have permission to delete this chat.';
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
