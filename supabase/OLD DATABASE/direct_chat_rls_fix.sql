-- Fix direct 1v1 chat creation under RLS.
-- Existing app flow creates a chat row and immediately requests the inserted row
-- back with insert(...).select().single(). Direct chats are not groups, so the
-- creator must be allowed to select their own newly created row before members
-- are inserted.

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
